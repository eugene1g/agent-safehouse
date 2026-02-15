export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/api/healthz") {
      return new Response("ok\n", {
        status: 200,
        headers: { "content-type": "text/plain; charset=utf-8" },
      });
    }

    if (url.pathname === "/api/version") {
      const body = JSON.stringify({ sha: env.GIT_SHA ?? null });
      return new Response(body, {
        status: 200,
        headers: { "content-type": "application/json; charset=utf-8" },
      });
    }

    if (url.pathname.startsWith("/api/")) {
      return new Response(JSON.stringify({ error: "not_found" }), {
        status: 404,
        headers: { "content-type": "application/json; charset=utf-8" },
      });
    }

    // For non-API routes, delegate to static assets.
    return env.ASSETS.fetch(request);
  },
};
