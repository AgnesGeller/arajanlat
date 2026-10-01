create or replace function public.quote_customers_reconcile(p_company uuid,p_customers jsonb) returns integer
language plpgsql security invoker set search_path='' as $$
declare r jsonb; c public.quote_clients; fields jsonb; m jsonb; f jsonb; k text; n integer=0;
 previous_skip text=current_setting('quote.skip_customer_queue',true);
begin
 if not exists(select 1 from public.quote_staff where company_id=p_company) then raise exception 'Unknown quote company';end if;
 perform set_config('quote.skip_customer_queue','on',true);
 for r in select value from jsonb_array_elements(p_customers) loop
  if nullif(btrim(r->>'full_name'),'') is null then raise exception 'Invalid customer';end if;
  select * into c from public.quote_clients where company_id=p_company and source_customer_id=(r->>'id')::uuid for update;
  if not found then
   if not coalesce((r->>'active')::boolean,false) or r->>'review_status'<>'approved' then continue;end if;
   insert into public.quote_clients(company_id,name,source_customer_id,shared_sync_enabled)
    values(p_company,r->>'full_name',(r->>'id')::uuid,true) returning * into c;
  end if;
  fields=jsonb_build_object('name',nullif(regexp_replace(btrim(r->>'full_name'),'[[:space:]]+',' ','g'),''),
   'client_type',nullif(btrim(r#>>'{details,customer_type}'),''),'contact_name',nullif(btrim(r#>>'{details,contact_name}'),''),
   'email',nullif(btrim(r#>>'{details,email}'),''),'phone',nullif(btrim(r#>>'{details,phone}'),''),
   'tax_number',nullif(btrim(r#>>'{details,tax_number}'),''),'notes',nullif(btrim(r#>>'{details,notes}'),''),
   'project_address',(select string_agg(a,E'\n' order by a collate "C") from
    (select distinct btrim(x->>'address') a from jsonb_array_elements(coalesce(r->'locations','[]'::jsonb)) x
     where (x->>'active')::boolean and x->>'review_status'='approved' and btrim(x->>'address')<>'') s));
  m=quote_private.merge_customer_fields(quote_private.customer_fields(c),c.sync_base,fields,c.sync_conflicts);
  f=m->'fields';
  -- The current Munkalap customer master wins whenever the copies disagree.
  for k in select jsonb_object_keys(m->'conflicts') loop
   f=jsonb_set(f,array[k],fields->k);
  end loop;
  m=jsonb_set(m,'{conflicts}','{}'::jsonb);
  if quote_private.customer_fields(c) is distinct from f or c.sync_base is distinct from fields
   or c.source_payload is distinct from r or c.sync_conflicts is distinct from m->'conflicts'
   or c.is_active is distinct from ((r->>'active')::boolean and r->>'review_status'='approved') then
   update public.quote_clients set name=f->>'name',client_type=f->>'client_type',contact_name=f->>'contact_name',
    email=f->>'email',phone=f->>'phone',tax_number=f->>'tax_number',notes=f->>'notes',project_address=f->>'project_address',
    sync_base=fields,sync_conflicts=m->'conflicts',source_payload=r,
    is_active=((r->>'active')::boolean and r->>'review_status'='approved') where id=c.id returning * into c;
   n=n+1;
  end if;
  if c.shared_sync_enabled and (quote_private.customer_fields(c)<>c.sync_base or c.sync_conflicts<>'{}'::jsonb) then
   insert into public.quote_customer_sync(client_id,last_error) values(c.id,case when c.sync_conflicts<>'{}'::jsonb then 'Eltérő ügyféladatok: válaszd ki a megtartandó értékeket.' end)
   on conflict(client_id) do update set synced_at=null,last_error=excluded.last_error;
  else
   update public.quote_customer_sync set synced_at=now(),last_error=null where client_id=c.id and synced_at is null;
  end if;
 end loop;
 perform set_config('quote.skip_customer_queue',coalesce(previous_skip,''),true);
 return n;
end $$;
revoke all on function public.quote_customers_reconcile(uuid,jsonb) from public,anon,authenticated;
grant usage on schema quote_private to service_role;
grant execute on function public.quote_customers_reconcile(uuid,jsonb) to service_role;

notify pgrst,'reload schema';
-- One-time alignment to the freshly read master; quote history preserves previous values.
update public.quote_clients c set name=sync_base->>'name',client_type=sync_base->>'client_type',
 contact_name=sync_base->>'contact_name',email=sync_base->>'email',phone=sync_base->>'phone',
 tax_number=sync_base->>'tax_number',notes=sync_base->>'notes',project_address=sync_base->>'project_address'
where source_customer_id is not null and merged_into is null and sync_base is not null
 and quote_private.customer_fields(c) is distinct from sync_base;
update public.quote_customer_sync q set synced_at=now(),last_error=null
from public.quote_clients c where c.id=q.client_id and c.source_customer_id is not null
 and c.sync_conflicts='{}'::jsonb and quote_private.customer_fields(c)=c.sync_base;
