// Request/response plumbing shared by every route.

const CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,PATCH,DELETE,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
    "Access-Control-Max-Age": "86400"
};

export function json(body, status = 200, extraHeaders = {}) {
    return new Response(JSON.stringify(body), {
        status,
        headers: { "Content-Type": "application/json; charset=utf-8", ...CORS_HEADERS, ...extraHeaders }
    });
}

export function noContent() {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
}

export function preflight() {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
}

// Thrown anywhere in a route; the top-level handler turns it into a response.
// Anything *not* an APIError is treated as a bug and reported as a bare 500, so
// internal messages never leak to clients.
export class APIError extends Error {
    constructor(status, code, message) {
        super(message || code);
        this.status = status;
        this.code = code;
    }
}

export const badRequest = (message) => new APIError(400, "bad_request", message);
export const unauthorized = (message) => new APIError(401, "unauthorized", message);
export const forbidden = (message) => new APIError(403, "forbidden", message);
export const notFound = (message) => new APIError(404, "not_found", message);
export const conflict = (message) => new APIError(409, "conflict", message);
export const tooManyRequests = (message) => new APIError(429, "too_many_requests", message);

export async function readJSON(request) {
    try {
        const body = await request.json();
        if (body === null || typeof body !== "object" || Array.isArray(body)) {
            throw badRequest("Body must be a JSON object");
        }
        return body;
    } catch (error) {
        if (error instanceof APIError) throw error;
        throw badRequest("Malformed JSON body");
    }
}

export function requireString(body, field, { maxLength = 512 } = {}) {
    const value = body[field];
    if (typeof value !== "string" || value.length === 0) throw badRequest(`Missing "${field}"`);
    if (value.length > maxLength) throw badRequest(`"${field}" is too long`);
    return value;
}

export function optionalString(body, field, { maxLength = 512 } = {}) {
    const value = body[field];
    if (value === undefined || value === null) return null;
    if (typeof value !== "string") throw badRequest(`"${field}" must be a string`);
    if (value.length > maxLength) throw badRequest(`"${field}" is too long`);
    return value;
}

export function requireEnum(body, field, allowed) {
    const value = requireString(body, field);
    if (!allowed.includes(value)) throw badRequest(`"${field}" must be one of: ${allowed.join(", ")}`);
    return value;
}

export function parseInteger(value, { fallback = null, min = null, max = null } = {}) {
    if (value === null || value === undefined || value === "") return fallback;
    const parsed = Number.parseInt(value, 10);
    if (Number.isNaN(parsed)) return fallback;
    if (min !== null && parsed < min) return min;
    if (max !== null && parsed > max) return max;
    return parsed;
}
