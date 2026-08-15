const TMDB_API_ORIGIN = "https://api.themoviedb.org";
const TMDB_IMAGE_ORIGIN = "https://image.tmdb.org";

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const origin = url.pathname.startsWith("/t/p/") ? TMDB_IMAGE_ORIGIN : TMDB_API_ORIGIN;
    const targetURL = new URL(url.pathname + url.search, origin);

    const proxiedRequest = new Request(targetURL, request);
    const response = await fetch(proxiedRequest);

    const proxiedResponse = new Response(response.body, response);
    proxiedResponse.headers.set("Access-Control-Allow-Origin", "*");
    return proxiedResponse;
  },
};
