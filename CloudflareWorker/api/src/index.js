// Franamed API.
//
// Every route lives behind /v1/. The client never talks to the database, only
// to these handlers, which is what makes authorisation a property of this code
// rather than of a rules file that has to be kept in sync with it.

import { APIError, json, preflight } from "./lib/http.js";
import { handleAuth } from "./routes/auth.js";
import { handleCatalog } from "./routes/catalog.js";
import { handleRound } from "./routes/round.js";
import { handleCuration } from "./routes/curation.js";
import { handlePlaylists } from "./routes/playlists.js";
import { handleProfile } from "./routes/profile.js";
import { handleAdmin } from "./routes/admin.js";

const HANDLERS = {
    auth: handleAuth,
    catalog: handleCatalog,
    round: handleRound,
    curation: handleCuration,
    playlists: handlePlaylists,
    profile: handleProfile,
    admin: handleAdmin
};

export default {
    async fetch(request, env, ctx) {
        if (request.method === "OPTIONS") return preflight();

        const url = new URL(request.url);
        const segments = url.pathname.split("/").filter(Boolean);

        if (segments[0] === "health") {
            return json({ ok: true, time: Date.now() });
        }

        if (segments[0] !== "v1") {
            return json({ error: "not_found", message: "Expected a /v1/ path" }, 404);
        }

        const handler = HANDLERS[segments[1]];
        if (!handler) {
            return json({ error: "not_found", message: `Unknown resource "${segments[1] || ""}"` }, 404);
        }

        try {
            const response = await handler(request, env, segments.slice(2), url, ctx);
            if (response) return response;
            return json({ error: "not_found", message: "No route matches this method and path" }, 404);
        } catch (error) {
            if (error instanceof APIError) {
                return json({ error: error.code, message: error.message }, error.status);
            }

            // An unexpected throw is a bug, not something a client should learn
            // the shape of. The detail goes to the log, not the response.
            console.error("Unhandled error", error?.stack || error);
            return json({ error: "internal_error", message: "Something went wrong" }, 500);
        }
    }
};
