// Only common CUSTOMER DATA changes in Kassza; no source code, schema, Auth or financial fields.
const cors = {
  "Access-Control-Allow-Origin": "https://agnesgeller.github.io",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const projection = "*,details:customer_details(*),locations:customer_locations(*)";
// URLSearchParams encodes values; PostgREST binds the RHS as a typed literal.
const eq = (value: string) => 'eq.' + value;
const tidy = (value: string) => value.trim().replace(/\s+/g, " ");
const addresses = (value: string | null) => [...new Set((value || "").split("\n").map(tidy).filter(Boolean))];
function reply(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
function dirtyFields(c: any) {
  const result: Record<string, any> = {};
  for (const [key, value] of Object.entries(c.fields)) {
    if (!c.sync_base || JSON.stringify(value) !== JSON.stringify(c.sync_base[key])) result[key] = value;
  }
  return result;
}
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return reply(405, { message: "Nem támogatott kérés." });
  const started = Date.now(), leaseOwner = crypto.randomUUID();
  const url = Deno.env.get("SUPABASE_URL")!, ownKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  let company: string | null = null, leased = false;
  async function own(path: string, method = "GET", body?: unknown) {
    const response = await fetch(url + "/rest/v1/" + path, {
      method, headers: { apikey: ownKey, Authorization: "Bearer " + ownKey,
        "Content-Type": "application/json", Prefer: "return=representation" },
      body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) {
      const error = await response.json().catch(() => ({}));
      console.error("quote_sync_api", { system: "quote", resource: path.split("?")[0], status: response.status, code: error.code });
      throw Error("Az ügyféladatok frissítése nem menthető. Próbáld újra.");
    }
    return response.status === 204 ? null : response.json();
  }
  const ownRpc = (name: string, data: unknown) => own("rpc/" + name, "POST", data);
  try {
    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) return reply(401, { message: "Belépés szükséges." });
    const auth = await fetch(url + "/auth/v1/user", {
      headers: { apikey: ownKey, Authorization: authorization }, signal: AbortSignal.timeout(15000),
    });
    if (!auth.ok) return reply(401, { message: "Belépés szükséges." });
    const user = await auth.json();
    const staff = await own("quote_staff?user_id=eq." + encodeURIComponent(user.id) + "&select=company_id");
    if (staff.length !== 1) return reply(403, { message: "Árajánlat-hozzáférés szükséges." });
    company = staff[0].company_id;
    const sourceKey = Deno.env.get("KASSZA_SERVICE_ROLE_KEY");
    if (!sourceKey) return reply(503, { message: "A közös ügyféllista kapcsolata nincs beállítva. Az itt mentett adatok megmaradnak." });
    leased = await ownRpc("quote_customer_sync_lease", { p_company: company, p_owner: leaseOwner });
    if (!leased) return reply(200, { busy: true, imported: 0, synced: 0, failed: 0 });
    async function source(path: string, method = "GET", body?: unknown, insertOnly = false) {
      if (Date.now() - started > 85000) throw Error("A többi ügyfél frissítése a következő alkalommal folytatódik.");
      const response = await fetch("https://wojgdfojupnfldrmqaht.supabase.co/rest/v1/" + path, {
        method, headers: { apikey: sourceKey!, Authorization: "Bearer " + sourceKey,
          "Accept-Profile": "munkalap", "Content-Profile": "munkalap", "Content-Type": "application/json",
          Prefer: (insertOnly ? "resolution=ignore-duplicates," : "") + "return=representation" },
        body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(15000),
      });
      if (!response.ok) {
        const error = await response.json().catch(() => ({}));
        console.error("quote_sync_api", { system: "common", resource: path.split("?")[0], status: response.status, code: error.code });
        throw Error("A közös ügyféllista most nem frissíthető. Az itt mentett adatok megmaradnak.");
      }
      return response.status === 204 ? [] : response.json();
    }
    const findById = (id: string) => source("customers?" + new URLSearchParams({ id: eq(id), select: projection }));
    const reconcile = (customers: any[]) => ownRpc("quote_customers_reconcile", { p_company: company, p_customers: customers });
    const pendingRows = () => ownRpc("quote_customers_pending", { p_company: company });
    let imported = 0;
    for (let offset = 0; ; offset += 250) {
      const page = await source("customers?" + new URLSearchParams({ select: projection, order: "id", offset: String(offset), limit: "250" }));
      if (page.length) imported += await reconcile(page);
      if (page.length < 250) break;
    }
    let input: any = {};
    try { input = await req.json(); } catch { /* Empty requests use normal sync. */ }
    if (input.pull_only === true) return reply(200, { imported, synced: 0, failed: 0 });
    const pending = await pendingRows();
    let synced = 0, failed = 0, conflicts = 0;
    for (const c of pending) {
      if (Date.now() - started > 70000) break;
      if (Object.keys(c.sync_conflicts).length) { conflicts++; continue; }
      try {
        let remote: any;
        if (c.source_customer_id) {
          const rows = await findById(c.source_customer_id);
          if (rows.length !== 1) throw Error("A közös ügyfél nem található. Ellenőrizd a kapcsolatát.");
          remote = rows[0];
        } else {
          const filter = new URLSearchParams({ normalized_name: eq(tidy(c.name).toLocaleLowerCase("hu")), select: projection });
          let matches = await source("customers?" + filter);
          if (!matches.length) {
            await source("customers?on_conflict=normalized_name", "POST", {
              id: c.id, full_name: tidy(c.name), active: true, review_status: "approved",
            }, true);
            matches = await source("customers?" + filter);
          }
          if (matches.length !== 1) throw Error("Az ügyfél nem azonosítható egyértelműen a közös listában.");
          remote = matches[0];
          const existing = await own("quote_clients?" + new URLSearchParams({ company_id: eq(company!), source_customer_id: eq(remote.id), select: "id" }));
          if (existing.some((row: any) => row.id !== c.id))
            throw Error("Ez az ügyfél már szerepel a közös listában. Válaszd a „Meglévő közös ügyfélhez kapcsolás” gombot.");
          await own("quote_clients?" + new URLSearchParams({ id: eq(c.id), company_id: eq(company!) }), "PATCH", { source_customer_id: remote.id });
        }
        if (!remote.active || remote.review_status !== "approved")
          throw Error("A közös ügyfél inaktív vagy jóváhagyásra vár. Ezt itt nem változtatjuk meg.");
        // Reconcile again immediately before writing: never overwrite a new remote edit.
        await reconcile([remote]);
        const latest = (await pendingRows()).find((row: any) => row.id === c.id);
        if (!latest) { synced++; continue; }
        if (Object.keys(latest.sync_conflicts).length) { conflicts++; continue; }
        const dirty = dirtyFields(latest);
        if ("name" in dirty) {
          const changed = await source("customers?" + new URLSearchParams({ id: eq(remote.id), updated_at: eq(remote.updated_at) }), "PATCH", { full_name: tidy(dirty.name) });
          if (changed.length !== 1) throw Error("Az ügyfél közben máshol is módosult. A frissítést újra ellenőrizzük.");
        }
        const detailMap: Record<string, string> = { client_type: "customer_type", contact_name: "contact_name", email: "email", phone: "phone", tax_number: "tax_number", notes: "notes" };
        const detailChanges: Record<string, any> = {};
        for (const [field, column] of Object.entries(detailMap)) if (field in dirty) detailChanges[column] = dirty[field];
        if (Object.keys(detailChanges).length) {
          if (remote.details) {
            const changed = await source("customer_details?" + new URLSearchParams({ customer_id: eq(remote.id), updated_at: eq(remote.details.updated_at) }), "PATCH", detailChanges);
            if (changed.length !== 1) throw Error("Az elérhetőségek közben máshol is módosultak. A frissítést újra ellenőrizzük.");
          } else {
            await source("customer_details?on_conflict=customer_id", "POST", { customer_id: remote.id, ...detailChanges }, true);
          }
        }
        if ("project_address" in dirty) {
          const wanted = addresses(dirty.project_address);
          const oldLocations = remote.locations.filter((l: any) => l.active && l.review_status === "approved");
          for (const address of wanted) {
            if (oldLocations.some((l: any) => tidy(l.address) === address)) continue;
            if (remote.locations.some((l: any) => tidy(l.address).toLocaleLowerCase("hu") === address.toLocaleLowerCase("hu")))
              throw Error("Az egyik cím már szerepel a közös törzsben, de inaktív vagy jóváhagyásra vár. Ellenőrizd a Munkalapban.");
            await source("customer_locations?on_conflict=customer_id,normalized_address", "POST", { customer_id: remote.id, address, active: true, review_status: "approved" }, true);
          }
          for (const location of oldLocations) {
            if (wanted.includes(tidy(location.address))) continue;
            const changed = await source("customer_locations?" + new URLSearchParams({ id: eq(location.id), customer_id: eq(remote.id), updated_at: eq(location.updated_at) }), "PATCH", { active: false });
            if (changed.length !== 1) throw Error("A cím közben máshol is módosult. A frissítést újra ellenőrizzük.");
          }
        }
        await reconcile(await findById(remote.id));
        const remaining = await own("quote_customer_sync?" + new URLSearchParams({ client_id: eq(c.id), synced_at: "is.null", select: "client_id" }));
        if (remaining.length) throw Error("Az ügyfél újabb módosítása még frissítésre vár.");
        synced++;
      } catch (error) {
        failed++;
        await own("quote_customer_sync?client_id=eq." + c.id, "PATCH", {
          last_attempt_at: new Date().toISOString(), last_error: error instanceof Error ? error.message : "Az ügyféladatok frissítésre várnak.",
        });
      }
    }
    const outstanding = await own("quote_customer_sync?select=client_id,quote_clients!inner(id,sync_conflicts)&synced_at=is.null&quote_clients.company_id=eq." + company);
    conflicts = outstanding.filter((row: any) => Object.keys(row.quote_clients.sync_conflicts).length > 0).length;
    return reply(200, { imported, synced, failed, conflicts, pending: outstanding.length });
  } catch {
    return reply(502, { message: "A közös ügyféllista most nem frissíthető. Az itt mentett adatok megmaradnak." });
  } finally {
    if (leased && company) {
      try { await ownRpc("quote_customer_sync_lease", { p_company: company, p_owner: leaseOwner, p_release: true }); }
      catch { /* Lease expires automatically. Never log private data or credentials. */ }
    }
  }
});
