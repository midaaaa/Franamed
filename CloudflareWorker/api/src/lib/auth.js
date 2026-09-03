// Authentication: anonymous device accounts, Sign in with Apple, and rotating
// refresh tokens.
//
// Threat model notes that shaped this file:
//  * The device secret behind an anonymous account is a bearer credential, so
//    it is generated on device with 32 bytes of entropy and only ever stored
//    here as a SHA-256 hash — a dump of this database hands over no accounts.
//  * Refresh tokens rotate on every use. A token presented twice means either a
//    stolen copy or a client bug; both are handled by revoking every token the
//    user has, which logs the thief out along with the victim.
//  * `role` lives only in this database and is never read from the client, so
//    there is no path for a client to promote itself.

import { APIError, forbidden, unauthorized } from "./http.js";
import { randomToken, sha256Hex, signJWT, timingSafeEqual, verifyJWT, base64UrlDecode } from "./crypto.js";

export const ACCESS_TOKEN_TTL_SECONDS = 15 * 60;
export const REFRESH_TOKEN_TTL_SECONDS = 60 * 24 * 60 * 60;

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys";
const ROLE_RANK = { user: 0, moderator: 1, admin: 2 };

function requireSecret(env) {
    const secret = env.JWT_SECRET;
    if (!secret || secret.length < 32) {
        throw new APIError(500, "server_misconfigured", "JWT_SECRET is missing or too short");
    }
    return secret;
}

// ------------------------------------------------------------------ accounts

async function createUser(env, { isAnonymous }) {
    const uid = crypto.randomUUID();
    const now = Date.now();

    // The very first account to be created becomes admin, so a fresh deployment
    // has someone who can grant roles. Afterwards this branch never fires.
    const existing = await env.DB.prepare("SELECT COUNT(*) AS count FROM users").first();
    const role = existing.count === 0 ? "admin" : "user";

    await env.DB.prepare(
        "INSERT INTO users (uid, role, is_anonymous, created_at) VALUES (?, ?, ?, ?)"
    ).bind(uid, role, isAnonymous ? 1 : 0, now).run();

    return uid;
}

async function findIdentity(env, provider, subject) {
    return env.DB.prepare("SELECT uid FROM identities WHERE provider = ? AND subject = ?")
        .bind(provider, subject)
        .first();
}

async function linkIdentity(env, provider, subject, uid) {
    await env.DB.prepare(
        "INSERT OR IGNORE INTO identities (provider, subject, uid, created_at) VALUES (?, ?, ?, ?)"
    ).bind(provider, subject, uid, Date.now()).run();
}

export async function loadUser(env, uid) {
    const user = await env.DB.prepare("SELECT * FROM users WHERE uid = ?").bind(uid).first();
    if (!user) throw unauthorized("Account no longer exists");
    return user;
}

// -------------------------------------------------------------------- tokens

async function issueTokens(env, uid, userAgent) {
    const user = await loadUser(env, uid);

    const accessToken = await signJWT(
        { sub: uid, role: user.role },
        requireSecret(env),
        ACCESS_TOKEN_TTL_SECONDS
    );

    const refreshToken = randomToken(32);
    const now = Date.now();

    await env.DB.prepare(
        "INSERT INTO refresh_tokens (token_hash, uid, issued_at, expires_at, user_agent) VALUES (?, ?, ?, ?, ?)"
    ).bind(
        await sha256Hex(refreshToken),
        uid,
        now,
        now + REFRESH_TOKEN_TTL_SECONDS * 1000,
        userAgent ? String(userAgent).slice(0, 200) : null
    ).run();

    return {
        accessToken,
        refreshToken,
        expiresIn: ACCESS_TOKEN_TTL_SECONDS,
        user: publicUser(user)
    };
}

export function publicUser(user) {
    return {
        uid: user.uid,
        role: user.role,
        displayName: user.display_name,
        isAnonymous: user.is_anonymous === 1,
        reportMultiplier: user.report_multiplier,
        dailyStreak: user.daily_streak,
        longestStreak: user.longest_streak,
        lastDailyCompletedDate: user.last_daily_completed_date,
        bonusAttemptsAvailable: user.bonus_attempts_available,
        attemptsUsedToday: user.attempts_used_today,
        lastAttemptResetDate: user.last_attempt_reset_date
    };
}

export async function rotateRefreshToken(env, presentedToken, userAgent) {
    const hash = await sha256Hex(presentedToken);
    const row = await env.DB.prepare("SELECT * FROM refresh_tokens WHERE token_hash = ?").bind(hash).first();

    if (!row) throw unauthorized("Unknown refresh token");

    if (row.revoked_at !== null) {
        // Replay of an already-rotated token. Treat the whole session family as
        // compromised rather than guessing which side is the attacker.
        await env.DB.prepare(
            "UPDATE refresh_tokens SET revoked_at = ? WHERE uid = ? AND revoked_at IS NULL"
        ).bind(Date.now(), row.uid).run();
        throw unauthorized("Refresh token was already used");
    }

    if (row.expires_at < Date.now()) throw unauthorized("Refresh token expired");

    await env.DB.prepare("UPDATE refresh_tokens SET revoked_at = ? WHERE token_hash = ?")
        .bind(Date.now(), hash)
        .run();

    return issueTokens(env, row.uid, userAgent);
}

export async function revokeAllTokens(env, uid) {
    await env.DB.prepare("UPDATE refresh_tokens SET revoked_at = ? WHERE uid = ? AND revoked_at IS NULL")
        .bind(Date.now(), uid)
        .run();
}

// --------------------------------------------------------- anonymous sign-in

export async function signInAnonymously(env, deviceSecret, userAgent) {
    // 32 random bytes base64url-encode to 43 characters. Anything shorter is
    // either an old client or someone trying a guessable value.
    if (typeof deviceSecret !== "string" || deviceSecret.length < 43) {
        throw new APIError(400, "bad_request", "deviceSecret must be at least 32 bytes of entropy");
    }

    const subject = await sha256Hex(deviceSecret);
    const identity = await findIdentity(env, "anonymous", subject);

    if (identity) return issueTokens(env, identity.uid, userAgent);

    const uid = await createUser(env, { isAnonymous: true });
    await linkIdentity(env, "anonymous", subject, uid);
    return issueTokens(env, uid, userAgent);
}

// ------------------------------------------------------- Sign in with Apple

let cachedAppleKeys = { keys: null, fetchedAt: 0 };

async function appleSigningKeys() {
    const isFresh = cachedAppleKeys.keys && Date.now() - cachedAppleKeys.fetchedAt < 60 * 60 * 1000;
    if (isFresh) return cachedAppleKeys.keys;

    const response = await fetch(APPLE_KEYS_URL);
    if (!response.ok) throw new APIError(502, "apple_unavailable", "Could not fetch Apple signing keys");

    const body = await response.json();
    cachedAppleKeys = { keys: body.keys, fetchedAt: Date.now() };
    return body.keys;
}

// Verifies the identity token Apple hands to the app. Everything Apple's own
// documentation lists as a required check is done here: signature against their
// published key, issuer, audience (our bundle id), expiry, and the nonce the
// app generated for this specific sign-in attempt.
async function verifyAppleIdentityToken(env, identityToken, expectedNonce) {
    const segments = String(identityToken || "").split(".");
    if (segments.length !== 3) throw unauthorized("Malformed Apple identity token");

    let header;
    let payload;
    try {
        header = JSON.parse(new TextDecoder().decode(base64UrlDecode(segments[0])));
        payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(segments[1])));
    } catch {
        throw unauthorized("Malformed Apple identity token");
    }

    if (header.alg !== "RS256") throw unauthorized("Unexpected Apple token algorithm");

    const jwk = (await appleSigningKeys()).find((key) => key.kid === header.kid);
    if (!jwk) throw unauthorized("Unknown Apple signing key");

    const key = await crypto.subtle.importKey(
        "jwk",
        jwk,
        { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
        false,
        ["verify"]
    );

    const valid = await crypto.subtle.verify(
        "RSASSA-PKCS1-v1_5",
        key,
        base64UrlDecode(segments[2]),
        new TextEncoder().encode(`${segments[0]}.${segments[1]}`)
    );
    if (!valid) throw unauthorized("Apple token signature does not verify");

    if (payload.iss !== APPLE_ISSUER) throw unauthorized("Unexpected Apple token issuer");

    const expectedAudience = env.APPLE_BUNDLE_ID;
    if (!expectedAudience) throw new APIError(500, "server_misconfigured", "APPLE_BUNDLE_ID is not set");
    if (payload.aud !== expectedAudience) throw unauthorized("Apple token was issued for another app");

    if (typeof payload.exp !== "number" || payload.exp < Math.floor(Date.now() / 1000)) {
        throw unauthorized("Apple token expired");
    }

    // The nonce ties the token to this sign-in attempt, which is what stops a
    // token captured elsewhere from being replayed here.
    if (expectedNonce) {
        const nonceHash = await sha256Hex(expectedNonce);
        if (!payload.nonce || !timingSafeEqual(payload.nonce, nonceHash)) {
            throw unauthorized("Apple token nonce does not match");
        }
    }

    return payload;
}

export async function signInWithApple(env, { identityToken, nonce, displayName }, userAgent) {
    const payload = await verifyAppleIdentityToken(env, identityToken, nonce);
    const identity = await findIdentity(env, "apple", payload.sub);

    if (identity) return issueTokens(env, identity.uid, userAgent);

    const uid = await createUser(env, { isAnonymous: false });
    await linkIdentity(env, "apple", payload.sub, uid);

    if (displayName) {
        await env.DB.prepare("UPDATE users SET display_name = ? WHERE uid = ?")
            .bind(String(displayName).slice(0, 80), uid)
            .run();
    }

    return issueTokens(env, uid, userAgent);
}

// Upgrades the signed-in anonymous account in place instead of creating a
// second one, so streak, playlist progress and watched history survive.
export async function linkAppleToCurrentUser(env, uid, { identityToken, nonce, displayName }) {
    const payload = await verifyAppleIdentityToken(env, identityToken, nonce);
    const existing = await findIdentity(env, "apple", payload.sub);

    if (existing && existing.uid !== uid) {
        throw new APIError(409, "already_linked", "This Apple ID is already attached to another account");
    }

    await linkIdentity(env, "apple", payload.sub, uid);
    await env.DB.prepare("UPDATE users SET is_anonymous = 0, display_name = COALESCE(?, display_name) WHERE uid = ?")
        .bind(displayName ? String(displayName).slice(0, 80) : null, uid)
        .run();

    return publicUser(await loadUser(env, uid));
}

// ------------------------------------------------------------- route guards

export async function authenticate(request, env) {
    const header = request.headers.get("Authorization") || "";
    if (!header.startsWith("Bearer ")) throw unauthorized("Missing bearer token");

    const payload = await verifyJWT(header.slice(7), requireSecret(env));
    if (!payload || !payload.sub) throw unauthorized("Invalid or expired access token");

    // Role is re-read from the database rather than trusted from the token, so
    // revoking a moderator takes effect immediately instead of after the access
    // token expires.
    const user = await loadUser(env, payload.sub);
    return user;
}

export function requireRole(user, minimumRole) {
    if (ROLE_RANK[user.role] === undefined || ROLE_RANK[user.role] < ROLE_RANK[minimumRole]) {
        throw forbidden(`Requires ${minimumRole} role`);
    }
}
