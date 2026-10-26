-- Linked quick quotes remain editable. Only quote_ data is involved.
-- Reads automatically hydrate the latest full version; optimistic revision checks
-- prevent an older quick editor overwriting full-editor changes.
create or replace function quote_private.guard_quick_draft() returns trigger language plpgsql set search_path='' as $$
begin
 if old.id<>new.id or old.company_id<>new.company_id or old.number<>new.number then raise exception 'Az ajánlat azonosítója nem módosítható.'; end if;
 if old.promoted_quote_id is not null and new.promoted_quote_id is distinct from old.promoted_quote_id then raise exception 'A kapcsolódó ajánlat nem cserélhető le.'; end if;
 return new;
end $$;

create or replace function quote_private.refresh_quick(p_id uuid) returns public.quote_quick_drafts language plpgsql security invoker set search_path='' as $$
declare d public.quote_quick_drafts; q public.quote_quotes; v public.quote_versions; p public.quote_projects; c public.quote_clients; source public.quote_items; old_item jsonb; mapped jsonb; items jsonb:='[]'; next_payload jsonb; pos integer:=0;
begin
 select * into d from public.quote_quick_drafts where id=p_id for update;
 if not found then raise exception 'A gyors ajánlat nem elérhető.'; end if;
 if d.promoted_quote_id is null then return d; end if;
 select * into q from public.quote_quotes where id=d.promoted_quote_id;
 if not found then raise exception 'A kapcsolódó teljes ajánlat nem elérhető.'; end if;
 select * into v from public.quote_versions where quote_id=q.id order by created_at desc,id desc limit 1;
 if not found then raise exception 'Az ajánlatváltozat nem elérhető.'; end if;
 select * into p from public.quote_projects where id=q.project_id;
 select * into c from public.quote_clients where id=p.client_id;
 for source in select * from public.quote_items where version_id=v.id order by position,id loop
  select a into old_item from jsonb_array_elements(d.payload->'items') a where a->>'full_item_id'=source.id::text or a->>'id'=source.id::text limit 1;
  if old_item is null then
   old_item:=d.payload->'items'->pos;
   if concat_ws(' / ',nullif(old_item->>'main_item',''),old_item->>'name') is distinct from source.name then old_item:=null; end if;
  end if;
  mapped:=coalesce(old_item,'{}')||(to_jsonb(source)-'created_at'-'updated_at'-'version_id'-'position');
  mapped:=mapped||jsonb_build_object('id',source.id,'full_item_id',source.id,'main_item',case when concat_ws(' / ',nullif(old_item->>'main_item',''),old_item->>'name')=source.name then coalesce(old_item->>'main_item','') else '' end,'name',case when concat_ws(' / ',nullif(old_item->>'main_item',''),old_item->>'name')=source.name then old_item->>'name' else source.name end);
  if old_item is null or (old_item->>'quantity1')::numeric is distinct from source.quantity1 or old_item->>'unit1' is distinct from source.unit1 then
   mapped:=mapped||jsonb_build_object('measurement',jsonb_build_object('mode','quantity','quantity',source.quantity1));
  end if;
  items:=items||jsonb_build_array(mapped);pos:=pos+1;
 end loop;
 next_payload:=d.payload||jsonb_build_object('title',q.title,'terms',coalesce(q.terms,''),'valid_until',coalesce(q.valid_until::text,''),'client_id',p.client_id,'address',coalesce(p.work_address,''),'customer',jsonb_build_object('name',c.name,'email',coalesce(c.email,''),'phone',coalesce(c.phone,'')),'items',items,'linked_version_id',v.id,'linked_status',v.status);
 if next_payload is distinct from d.payload then
  update public.quote_quick_drafts set payload=next_payload,revision=revision+1,updated_at=now() where id=d.id returning * into d;
 end if;
 return d;
end $$;
revoke all on function quote_private.refresh_quick(uuid) from public,anon;
grant execute on function quote_private.refresh_quick(uuid) to authenticated;

create or replace function public.quote_quick_read(p_id uuid) returns jsonb language sql security invoker set search_path='' as $$
 select to_jsonb(quote_private.refresh_quick(p_id));
$$;
revoke all on function public.quote_quick_read(uuid) from public,anon;
grant execute on function public.quote_quick_read(uuid) to authenticated;

create or replace function public.quote_quick_list() returns setof jsonb language plpgsql security invoker set search_path='' as $$
declare entry record; d public.quote_quick_drafts;
begin
 for entry in select id from public.quote_quick_drafts order by updated_at desc limit 50 loop
  d:=quote_private.refresh_quick(entry.id);
  return next jsonb_build_object('id',d.id,'number',d.number,'revision',d.revision,'promoted_quote_id',d.promoted_quote_id,'updated_at',d.updated_at,'payload',jsonb_build_object('title',d.payload->>'title','customer',d.payload->'customer'));
 end loop;
end $$;
revoke all on function public.quote_quick_list() from public,anon;
grant execute on function public.quote_quick_list() to authenticated;

create or replace function quote_private.write_quick_to_full(p_id uuid) returns void language plpgsql security invoker set search_path='' as $$
declare d public.quote_quick_drafts; q public.quote_quotes; v public.quote_versions; p public.quote_projects; item jsonb; item_id uuid; keep uuid[]:='{}'; n integer:=0;
begin
 select * into d from public.quote_quick_drafts where id=p_id for update;
 if d.promoted_quote_id is null then return; end if;
 select * into q from public.quote_quotes where id=d.promoted_quote_id for update;
 select * into p from public.quote_projects where id=q.project_id;
 if nullif(d.payload->>'client_id','')::uuid is distinct from p.client_id or btrim(coalesce(d.payload->>'address','')) is distinct from btrim(coalesce(p.work_address,'')) then raise exception 'A kapcsolódó projekt ügyfelét és címét a Projekt és felmérés oldalon módosítsd. A tételek, az ajánlat neve és feltételei itt is szerkeszthetők.'; end if;
 select * into v from public.quote_versions where quote_id=q.id order by created_at desc,id desc limit 1 for update;
 if v.id is null or v.status<>'draft' then
  insert into public.quote_versions(quote_id,name) values(q.id,'Gyors ajánlat – módosítás') returning * into v;
 end if;
 update public.quote_quotes set title=coalesce(nullif(btrim(d.payload->>'title'),''),'Árajánlat'),terms=d.payload->>'terms',valid_until=nullif(d.payload->>'valid_until','')::date where id=q.id;
 for item in select * from jsonb_array_elements(d.payload->'items') loop
  n:=n+1;item_id:=null;
  select id into item_id from public.quote_items where version_id=v.id and id=nullif(item->>'full_item_id','')::uuid;
  if item_id is null then item_id:=gen_random_uuid(); end if;
  keep:=array_append(keep,item_id);
  insert into public.quote_items(id,version_id,position,catalog_id,category,subcategory,name,description,quantity1,unit1,quantity2,unit2,material_unit,labor_unit,other_cost,vat_rate,pricing_required,public_note,internal_note)
  values(item_id,v.id,n,nullif(item->>'catalog_id','')::uuid,item->>'category',item->>'subcategory',concat_ws(' / ',nullif(item->>'main_item',''),item->>'name'),item->>'description',(item->>'quantity1')::numeric,item->>'unit1',nullif(item->>'quantity2','')::numeric,item->>'unit2',(item->>'material_unit')::numeric,(item->>'labor_unit')::numeric,(item->>'other_cost')::numeric,(item->>'vat_rate')::numeric,coalesce((item->>'pricing_required')::boolean,false),item->>'public_note',item->>'internal_note')
  on conflict(id) do update set position=excluded.position,catalog_id=excluded.catalog_id,category=excluded.category,subcategory=excluded.subcategory,name=excluded.name,description=excluded.description,quantity1=excluded.quantity1,unit1=excluded.unit1,quantity2=excluded.quantity2,unit2=excluded.unit2,material_unit=excluded.material_unit,labor_unit=excluded.labor_unit,other_cost=excluded.other_cost,vat_rate=excluded.vat_rate,pricing_required=excluded.pricing_required,public_note=excluded.public_note,internal_note=excluded.internal_note;
 end loop;
 delete from public.quote_items where version_id=v.id and not(id=any(keep));
end $$;
revoke all on function quote_private.write_quick_to_full(uuid) from public,anon;
grant execute on function quote_private.write_quick_to_full(uuid) to authenticated;

create or replace function public.quote_quick_save(p_id uuid,p_payload jsonb,p_revision integer default null)
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
 if exists(select 1 from public.quote_quick_drafts where id=p_id) then d:=quote_private.refresh_quick(p_id); end if;
 select * into d from public.quote_quick_drafts where id=p_id for update;
 if found then
  if d.payload=p_payload then return to_jsonb(d); end if;
  if p_revision is null or p_revision<>d.revision then raise exception 'Az ajánlat közben másik eszközön módosult. Nyisd meg újra a mentett változatot.'; end if;
  update public.quote_quick_drafts set payload=p_payload,revision=revision+1,updated_at=now() where id=p_id returning * into d;
 else
  if p_revision is not null then raise exception 'A mentett ajánlat nem elérhető.'; end if;
  insert into public.quote_quick_drafts(id,number,payload) values(p_id,'GY-'||to_char(now() at time zone 'Europe/Budapest','YYYY')||'-'||upper(left(replace(p_id::text,'-',''),12)),p_payload) returning * into d;
 end if;
 if d.promoted_quote_id is not null then
  perform quote_private.write_quick_to_full(d.id);
  d:=quote_private.refresh_quick(d.id);
 end if;
 return to_jsonb(d);
end $$;
revoke all on function public.quote_quick_save(uuid,jsonb,integer) from public,anon;
grant execute on function public.quote_quick_save(uuid,jsonb,integer) to authenticated;


notify pgrst,'reload schema';
