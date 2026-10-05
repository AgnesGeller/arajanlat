-- Preserve the selected Excel catalogue reference on future quote rows.
-- Existing amounts and accepted snapshots remain unchanged.
alter table public.quote_items
 add column if not exists catalog_id uuid references public.quote_price_catalog(id) on delete set null;
create index if not exists quote_items_catalog_idx on public.quote_items(catalog_id);
