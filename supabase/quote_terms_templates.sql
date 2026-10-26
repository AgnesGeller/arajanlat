-- Árajánlat-only reusable terms. No other app schema or permissions change.
create table public.quote_terms_templates (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null default quote_private.staff_company() references public.companies(id),
 name text not null check(length(btrim(name)) between 1 and 100),
 body text not null check(length(btrim(body)) between 1 and 5000),
 created_at timestamptz not null default now(),
 unique(company_id,name)
);
alter table public.quote_terms_templates enable row level security;
revoke all on public.quote_terms_templates from public,anon,authenticated;
grant select,insert on public.quote_terms_templates to authenticated;
create policy quote_terms_read on public.quote_terms_templates for select to authenticated
using(company_id=(select quote_private.staff_company()));
create policy quote_terms_insert on public.quote_terms_templates for insert to authenticated
with check(company_id=(select quote_private.staff_company()));
