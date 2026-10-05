-- Only quotation-owned objects. Exact name/address duplicates retain their originals.
create or replace function public.quote_customers_merge_duplicates() returns jsonb
language plpgsql security definer set search_path='' as $$
declare company uuid:=quote_private.staff_company();a public.quote_clients;target uuid;matches integer;result jsonb:='[]';
begin
 if company is null then raise exception 'Árajánlat-hozzáférés szükséges' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('quote-customer-merge:'||company::text,0));
 perform 1 from public.quote_clients where company_id=company and merged_into is null order by id for update;
 for a in select * from public.quote_clients where company_id=company and merged_into is null and source_customer_id is null order by id loop
  if nullif(btrim(a.project_address),'') is null then continue;end if;
  select count(*),(array_agg(b.id order by b.id))[1] into matches,target
   from public.quote_clients b where b.company_id=company and b.merged_into is null and b.source_customer_id is not null
   and quote_private.customer_value_equal('name',to_jsonb(a.name),to_jsonb(b.name))
   and quote_private.customer_value_equal('project_address',to_jsonb(a.project_address),to_jsonb(b.project_address));
  if matches=1 then
   perform public.quote_customer_link(a.id,target);
   result:=result||jsonb_build_array(jsonb_build_object('from',a.id,'to',target));
  end if;
 end loop;
 return result;
end $$;
revoke all on function public.quote_customers_merge_duplicates() from public,anon;
grant execute on function public.quote_customers_merge_duplicates() to authenticated;

-- Retain the existing API for cached clients, but sharing is automatic on save.
do $$
declare definition text;
begin
 definition:=pg_get_functiondef('public.quote_clients_upsert(uuid,text,text,text,text,text,text,text,text,boolean,bigint)'::regprocedure);
 definition:=replace(definition,'coalesce(p_share,true)','true');
 definition:=replace(definition,'shared_sync_enabled=coalesce(p_share,shared_sync_enabled)','shared_sync_enabled=true');
 execute definition;
 definition:=pg_get_functiondef('public.quote_public_request_submit(text,text,text,jsonb)'::regprocedure);
 definition:=replace(definition,'update public.quote_projects set status=''Ügyfél kitöltötte'' where id=p.id;',
  'update public.quote_projects set status=''Ügyfél kitöltötte'' where id=p.id and status in (''Új érdeklődés'',''Adatbekérő kiküldve'',''Ügyfél kitöltötte'');');
 execute definition;
end $$;

create or replace function public.quote_request_link_create(p_project uuid) returns text
language plpgsql security definer set search_path='' as $$
declare token text:=encode(extensions.gen_random_bytes(32),'hex');
begin
 if quote_private.staff_company() is null or not quote_private.can_project(p_project) then
  raise exception 'A projekt nem elérhető.' using errcode='42501';end if;
 insert into public.quote_public_tokens(project_id,purpose,token_hash,expires_at)
 values(p_project,'request',encode(extensions.digest(token,'sha256'),'hex'),now()+interval '30 days');
 insert into public.quote_timeline(project_id,event) values(p_project,'Adatbekérő link létrehozva');
 return token;
end $$;
revoke all on function public.quote_request_link_create(uuid) from public,anon;
grant execute on function public.quote_request_link_create(uuid) to authenticated;
notify pgrst,'reload schema';
