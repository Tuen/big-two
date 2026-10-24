const pageUrl =
  "https://ascorkeijzrpmfykpcrb.supabase.co/storage/v1/object/public/game/web/index.html";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "access-control-allow-origin": "*",
        "access-control-allow-headers": "authorization, apikey, content-type",
      },
    });
  }
  const source = await fetch(pageUrl);
  if (!source.ok) {
    return new Response("The Big Two page is not available.", { status: 502 });
  }
  return new Response(await source.text(), {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=60",
      "access-control-allow-origin": "*",
    },
  });
});
