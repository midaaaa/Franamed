// Low-level crypto helpers built on WebCrypto, which Workers exposes natively.

const encoder = new TextEncoder();

export function base64UrlEncode(bytes) {
    const binary = String.fromCharCode(...new Uint8Array(bytes));
    return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function base64UrlDecode(value) {
    const padded = value.replace(/-/g, "+").replace(/_/g, "/");
    const binary = atob(padded.padEnd(padded.length + ((4 - (padded.length % 4)) % 4), "="));
    return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

export function randomToken(byteLength = 32) {
    const bytes = new Uint8Array(byteLength);
    crypto.getRandomValues(bytes);
    return base64UrlEncode(bytes);
}

export async function sha256Hex(value) {
    const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
    return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Comparison that does not leak how many leading characters matched. Used for
// anything an attacker could probe repeatedly.
export function timingSafeEqual(a, b) {
    if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
    let mismatch = 0;
    for (let i = 0; i < a.length; i += 1) mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
    return mismatch === 0;
}

async function hmacKey(secret) {
    return crypto.subtle.importKey(
        "raw",
        encoder.encode(secret),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign", "verify"]
    );
}

export async function signJWT(payload, secret, ttlSeconds) {
    const issuedAt = Math.floor(Date.now() / 1000);
    const body = { ...payload, iat: issuedAt, exp: issuedAt + ttlSeconds };

    const segments = [
        base64UrlEncode(encoder.encode(JSON.stringify({ alg: "HS256", typ: "JWT" }))),
        base64UrlEncode(encoder.encode(JSON.stringify(body)))
    ];

    const signature = await crypto.subtle.sign("HMAC", await hmacKey(secret), encoder.encode(segments.join(".")));
    segments.push(base64UrlEncode(signature));
    return segments.join(".");
}

export async function verifyJWT(token, secret) {
    const segments = String(token || "").split(".");
    if (segments.length !== 3) return null;

    const [header, body, signature] = segments;

    // The algorithm is pinned rather than read from the header: trusting the
    // header is the classic "alg: none" JWT forgery.
    let parsedHeader;
    try {
        parsedHeader = JSON.parse(new TextDecoder().decode(base64UrlDecode(header)));
    } catch {
        return null;
    }
    if (parsedHeader.alg !== "HS256") return null;

    const valid = await crypto.subtle.verify(
        "HMAC",
        await hmacKey(secret),
        base64UrlDecode(signature),
        encoder.encode(`${header}.${body}`)
    );
    if (!valid) return null;

    let payload;
    try {
        payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(body)));
    } catch {
        return null;
    }

    if (typeof payload.exp !== "number" || payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
}
