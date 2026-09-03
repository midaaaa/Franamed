import { json, noContent, readJSON, requireString, optionalString } from "../lib/http.js";
import { limitByIP } from "../lib/limits.js";
import {
    authenticate,
    linkAppleToCurrentUser,
    publicUser,
    revokeAllTokens,
    rotateRefreshToken,
    signInAnonymously,
    signInWithApple
} from "../lib/auth.js";

export async function handleAuth(request, env, segments) {
    const action = segments[0];
    const userAgent = request.headers.get("User-Agent");

    if (action === "anonymous" && request.method === "POST") {
        await limitByIP(env, request, "AUTH_LIMITER");
        const body = await readJSON(request);
        return json(await signInAnonymously(env, requireString(body, "deviceSecret", { maxLength: 200 }), userAgent));
    }

    if (action === "apple" && request.method === "POST") {
        await limitByIP(env, request, "AUTH_LIMITER");
        const body = await readJSON(request);
        return json(
            await signInWithApple(
                env,
                {
                    identityToken: requireString(body, "identityToken", { maxLength: 4096 }),
                    nonce: optionalString(body, "nonce", { maxLength: 200 }),
                    displayName: optionalString(body, "displayName", { maxLength: 80 })
                },
                userAgent
            )
        );
    }

    if (action === "refresh" && request.method === "POST") {
        await limitByIP(env, request, "AUTH_LIMITER");
        const body = await readJSON(request);
        return json(await rotateRefreshToken(env, requireString(body, "refreshToken", { maxLength: 200 }), userAgent));
    }

    if (action === "link-apple" && request.method === "POST") {
        const user = await authenticate(request, env);
        const body = await readJSON(request);
        return json(
            await linkAppleToCurrentUser(env, user.uid, {
                identityToken: requireString(body, "identityToken", { maxLength: 4096 }),
                nonce: optionalString(body, "nonce", { maxLength: 200 }),
                displayName: optionalString(body, "displayName", { maxLength: 80 })
            })
        );
    }

    if (action === "logout" && request.method === "POST") {
        const user = await authenticate(request, env);
        await revokeAllTokens(env, user.uid);
        return noContent();
    }

    if (action === "me" && request.method === "GET") {
        return json(publicUser(await authenticate(request, env)));
    }

    return null;
}
