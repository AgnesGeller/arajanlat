// Quote-only worker. Source requests are GET and insert-only POST.
const cors = {
  "Access-Control-Allow-Origin": "https://agnesgeller.github.io",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function reply(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
const normalize = (name: string) => name.trim().replace(/\s+/g, " ").replace(/ zoli$/i, " Zoltán").toLocaleLowerCase("hu");
const eq = (value: string) => 'eq."' + value.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return reply(405, { message: "Nem támogatott kérés." });
  const url = Deno.env.get("SUPABASE_URL")!;
  const ownKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return reply(401, { message: "Belépés szükséges." });
  try {
    const auth = await fetch(url + "/auth/v1/user", {
      headers: { apikey: ownKey, Authorization: authorization }, signal: AbortSignal.timeout(15000),
    });
    if (!auth.ok) return reply(401, { message: "Belépés szükséges." });
    const user = await auth.json();
    async function own(path: string, method = "GET", body?: unknown) {
      const response = await fetch(url + "/rest/v1/" + path, {
        method, headers: { apikey: ownKey, Authorization: "Bearer " + ownKey,
          "Content-Type": "application/json", Prefer: "return=representation" },
        body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(15000),
      });
      if (!response.ok) throw Error("Az ügyfélátadás állapota nem menthető.");
      return response.status === 204 ? null : response.json();
    }
    const staff = await own("quote_staff?user_id=eq." + encodeURIComponent(user.id) + "&select=company_id");
    if (staff.length !== 1) return reply(403, { message: "Árajánlat-hozzáférés szükséges." });
    const sourceKey = Deno.env.get("KASSZA_SERVICE_ROLE_KEY");
    if (!sourceKey) return reply(503, { message: "Az ügyfél mentve az Árajánlatban; a közös ügyféllista kapcsolata még nincs beállítva." });
    async function source(path: string, body?: unknown) {
      const response = await fetch("https://wojgdfojupnfldrmqaht.supabase.co/rest/v1/" + path, {
        method: body === undefined ? "GET" : "POST",
        headers: { apikey: sourceKey!, Authorization: "Bearer " + sourceKey,
          "Accept-Profile": "munkalap", "Content-Profile": "munkalap", "Content-Type": "application/json",
          Prefer: "resolution=ignore-duplicates,return=representation" },
        body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(15000),
      });
      if (!response.ok) throw Error("A közös ügyféllistába történő átadás sikertelen. Később újra megpróbáljuk.");
      return response.status === 204 ? [] : response.json();
    }
    const pending = await own("quote_customer_sync?select=client_id,quote_clients!inner(*)&synced_at=is.null&quote_clients.company_id=eq." +
      encodeURIComponent(staff[0].company_id) + "&order=created_at&limit=10");
    let synced = 0, failed = 0;
    for (const entry of pending) {
      const c = entry.quote_clients;
      const filter = new URLSearchParams({ normalized_name: eq(normalize(c.name)), select: "id,full_name,active,review_status" });
      try {
        let matches = await source("customers?" + filter);
        if (!matches.length) {
          await source("customers?on_conflict=normalized_name", {
            id: c.id, full_name: c.name.trim().replace(/\s+/g, " "), active: true, review_status: "approved",
          });
          matches = await source("customers?" + filter);
        }
        if (matches.length !== 1) throw Error("Az ügyfél neve nem azonosítható egyértelműen a közös listában.");
        const remote = matches[0];
        if (!remote.active || remote.review_status !== "approved")
          throw Error("A közös listában ez az ügyfél már létezik, de jóváhagyásra vár vagy inaktív. Ott nem módosítottuk.");
        await own("quote_clients?id=eq." + c.id + "&company_id=eq." + staff[0].company_id, "PATCH", { source_customer_id: remote.id });
        await own("quote_customer_sync?client_id=eq." + c.id, "PATCH", { synced_at: new Date().toISOString(),
          last_attempt_at: new Date().toISOString(), last_error: null });
        synced++;
      } catch (error) {
        failed++;
        await own("quote_customer_sync?client_id=eq." + c.id, "PATCH", {
          last_attempt_at: new Date().toISOString(), last_error: error instanceof Error ? error.message : "Sikertelen átadás.",
        });
      }
    }
    return reply(200, { synced, failed });
  } catch {
    return reply(502, { message: "Az ügyfélátadás most nem elérhető. Az Árajánlatban mentett ügyfél megmarad." });
  }
});
