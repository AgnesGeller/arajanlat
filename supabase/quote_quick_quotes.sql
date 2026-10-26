-- Árajánlat-only quick drafts. No changes to Munkalap/Kassza or their access.
create table public.quote_quick_drafts (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null default quote_private.staff_company() references public.companies(id),
 number text not null unique,
 payload jsonb not null default '{"items":[]}'::jsonb,
 revision integer not null default 1,
 promoted_quote_id uuid references public.quote_quotes(id) on delete restrict,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 constraint quote_quick_items_present check(payload ? 'items'),
 check(jsonb_typeof(payload)='object' and jsonb_typeof(payload->'items')='array' and jsonb_array_length(payload->'items')<=200 and octet_length(payload::text)<=400000)
);
alter table public.quote_quick_drafts enable row level security;
revoke all on public.quote_quick_drafts from public,anon,authenticated;
grant select,insert,update on public.quote_quick_drafts to authenticated;
create policy quote_quick_read on public.quote_quick_drafts for select to authenticated
using(company_id=(select quote_private.staff_company()));
create policy quote_quick_insert on public.quote_quick_drafts for insert to authenticated
with check(company_id=(select quote_private.staff_company()) and promoted_quote_id is null);
create policy quote_quick_update on public.quote_quick_drafts for update to authenticated
using(company_id=(select quote_private.staff_company()))
with check(company_id=(select quote_private.staff_company()) and (promoted_quote_id is null or exists(select 1 from public.quote_quotes q where q.id=promoted_quote_id and quote_private.can_project(q.project_id))));
create index quote_quick_company_updated on public.quote_quick_drafts(company_id,updated_at desc);

create function quote_private.guard_quick_draft() returns trigger language plpgsql set search_path='' as $$
begin
 if old.id<>new.id or old.company_id<>new.company_id or old.number<>new.number then raise exception 'Az ajánlat azonosítója nem módosítható.'; end if;
 if old.promoted_quote_id is not null and (new.payload is distinct from old.payload or new.promoted_quote_id is distinct from old.promoted_quote_id) then raise exception 'Ez az ajánlat már a teljes ajánlatkezelésben szerkeszthető.'; end if;
 return new;
end $$;
revoke all on function quote_private.guard_quick_draft() from public,anon,authenticated;
create trigger quote_quick_guard before update on public.quote_quick_drafts for each row execute function quote_private.guard_quick_draft();

create function public.quote_quick_save(p_id uuid,p_payload jsonb,p_revision integer default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare d public.quote_quick_drafts; item record; client uuid;
begin
 if quote_private.staff_company() is null then raise exception 'Nincs árajánlatkészítői hozzáférés.'; end if;
 if p_id is null or jsonb_typeof(p_payload) is distinct from 'object' or jsonb_typeof(p_payload->'items') is distinct from 'array' or jsonb_array_length(p_payload->'items')>200 or octet_length(p_payload::text)>400000 then raise exception 'A gyors ajánlat adatai nem megfelelőek.'; end if;
 client:=nullif(p_payload->>'client_id','')::uuid;
 if client is not null and not quote_private.can_client(client) then raise exception 'Az ügyfél nem elérhető.'; end if;
 for item in select * from jsonb_to_recordset(p_payload->'items') as x(name text,quantity1 numeric,quantity2 numeric,unit2 text,material_unit numeric,labor_unit numeric,other_cost numeric,vat_rate numeric) loop
  if coalesce(length(btrim(item.name)),0)=0 or item.quantity1 is null or item.quantity1<0 or item.quantity1>1e8 or item.quantity1<>round(item.quantity1,3) or
   (nullif(item.unit2,'') is not null and (item.quantity2 is null or item.quantity2<0 or item.quantity2>1e8 or item.quantity2<>round(item.quantity2,3))) or
   item.material_unit is null or item.material_unit<0 or item.material_unit>1e9 or item.material_unit<>round(item.material_unit,2) or
   item.labor_unit is null or item.labor_unit<0 or item.labor_unit>1e9 or item.labor_unit<>round(item.labor_unit,2) or
   item.other_cost is null or item.other_cost<0 or item.other_cost>1e9 or item.other_cost<>round(item.other_cost,2) or
   item.vat_rate is null or item.vat_rate<0 or item.vat_rate>1 or item.vat_rate<>round(item.vat_rate,4) then raise exception 'Ellenőrizd a mennyiségeket és az árakat.'; end if;
 end loop;
 select * into d from public.quote_quick_drafts where id=p_id for update;
 if found then
  if d.payload=p_payload then return to_jsonb(d); end if;
  if d.promoted_quote_id is not null then raise exception 'Az ajánlatot a teljes ajánlatkezelésben módosítsd.'; end if;
  if p_revision is null or p_revision<>d.revision then raise exception 'Az ajánlat közben másik eszközön módosult. Nyisd meg újra a mentett változatot.'; end if;
  update public.quote_quick_drafts set payload=p_payload,revision=revision+1,updated_at=now() where id=p_id returning * into d;
 else
  if p_revision is not null then raise exception 'A mentett ajánlat nem elérhető.'; end if;
  insert into public.quote_quick_drafts(id,number,payload) values(p_id,'GY-'||to_char(now() at time zone 'Europe/Budapest','YYYY')||'-'||upper(left(replace(p_id::text,'-',''),12)),p_payload) returning * into d;
 end if;
 return to_jsonb(d);
end $$;
revoke all on function public.quote_quick_save(uuid,jsonb,integer) from public,anon;
grant execute on function public.quote_quick_save(uuid,jsonb,integer) to authenticated;

create function public.quote_quick_promote(p_id uuid,p_revision integer,p_project uuid default null)
returns uuid language plpgsql security invoker set search_path='' as $$
declare d public.quote_quick_drafts; client uuid; project uuid; quote uuid; version uuid; item jsonb; n integer:=0;
begin
 if quote_private.staff_company() is null then raise exception 'Nincs árajánlatkészítői hozzáférés.'; end if;
 select * into d from public.quote_quick_drafts where id=p_id for update;
 if not found then raise exception 'A gyors ajánlat nem elérhető.'; end if;
 if d.promoted_quote_id is not null then return d.promoted_quote_id; end if;
 if p_revision is distinct from d.revision then raise exception 'Az ajánlat közben módosult. Nyisd meg újra.'; end if;
 perform public.quote_quick_save(d.id,d.payload,d.revision);
 client:=nullif(d.payload->>'client_id','')::uuid;
 if client is null or not quote_private.can_client(client) then raise exception 'A teljes ajánlatkezeléshez válassz ügyfelet az első lépésben.'; end if;
 if exists(select 1 from jsonb_array_elements(d.payload->'items') i where coalesce((i->>'pricing_required')::boolean,false)) then raise exception 'Ellenőrizd a piros jelzéssel szereplő árakat.'; end if;
 if p_project is not null then
  select id into project from public.quote_projects where id=p_project and client_id=client and btrim(coalesce(work_address,''))=btrim(coalesce(d.payload->>'address',''));
  if project is null then raise exception 'A projekt ügyfele vagy címe nem egyezik. Válassz megfelelő projektet vagy készíts újat.'; end if;
 else
  insert into public.quote_projects(client_id,name,work_address,status) values(client,coalesce(nullif(btrim(d.payload->>'title'),''),'Árajánlat'),d.payload->>'address','Árajánlat készül') returning id into project;
 end if;
 insert into public.quote_quotes(project_id,number,title,valid_until,terms,detail_level) values(project,d.number,coalesce(nullif(btrim(d.payload->>'title'),''),'Árajánlat'),nullif(d.payload->>'valid_until','')::date,d.payload->>'terms','detailed') returning id into quote;
 insert into public.quote_versions(quote_id,name) values(quote,'Gyors ajánlat') returning id into version;
 for item in select * from jsonb_array_elements(d.payload->'items') loop
  n:=n+1;
  insert into public.quote_items(version_id,position,catalog_id,category,subcategory,name,description,quantity1,unit1,quantity2,unit2,material_unit,labor_unit,other_cost,vat_rate,pricing_required,public_note,internal_note)
  values(version,n,nullif(item->>'catalog_id','')::uuid,item->>'category',item->>'subcategory',concat_ws(' / ',nullif(item->>'main_item',''),item->>'name'),item->>'description',(item->>'quantity1')::numeric,item->>'unit1',nullif(item->>'quantity2','')::numeric,item->>'unit2',(item->>'material_unit')::numeric,(item->>'labor_unit')::numeric,(item->>'other_cost')::numeric,(item->>'vat_rate')::numeric,false,item->>'public_note',concat_ws(E'\n',item->>'internal_note','Felmérési adatok: '||coalesce((item->'measurement')::text,'{}')));
 end loop;
 insert into public.quote_timeline(project_id,event) values(project,'Gyors ajánlat átvéve a teljes ajánlatkezelésbe');
 update public.quote_quick_drafts set promoted_quote_id=quote,revision=revision+1,updated_at=now() where id=d.id;
 return quote;
end $$;
revoke all on function public.quote_quick_promote(uuid,integer,uuid) from public,anon;
grant execute on function public.quote_quick_promote(uuid,integer,uuid) to authenticated;
notify pgrst,'reload schema';
