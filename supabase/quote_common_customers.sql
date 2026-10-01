-- Only quote objects change. Kassza/Munkalap schema and access stay untouched.
alter table public.quote_clients
 add column shared_sync_enabled boolean not null default true,
 add column sync_base jsonb,
 add column sync_conflicts jsonb not null default '{}'::jsonb,
 add column sync_revision bigint not null default 0,
 add column legacy_payload jsonb,
 add column merged_into uuid references public.quote_clients(id);
update public.quote_clients c set shared_sync_enabled=(source_customer_id is not null),
 legacy_payload=to_jsonb(c);

create table public.quote_customer_history (
 id bigint generated always as identity primary key,
 client_id uuid not null references public.quote_clients(id),
 saved_at timestamptz not null default now(),
 actor uuid, previous_data jsonb not null
);
alter table public.quote_customer_history enable row level security;
revoke all on public.quote_customer_history from public,anon,authenticated;
grant select on public.quote_customer_history to authenticated;
grant all on public.quote_customer_history to service_role;
grant usage,select on sequence public.quote_customer_history_id_seq to service_role;
create policy quote_customer_history_staff on public.quote_customer_history for select to authenticated
 using(quote_private.can_client(client_id));

create or replace function quote_private.customer_fields(c public.quote_clients) returns jsonb
language sql immutable set search_path='' as $$
 select jsonb_build_object(
 'name',nullif(regexp_replace(btrim(c.name),'[[:space:]]+',' ','g'),''),
 'client_type',case c.client_type when 'person' then 'Magánszemély' when 'company' then 'Cég' else nullif(btrim(c.client_type),'') end,
 'contact_name',nullif(btrim(c.contact_name),''),'email',nullif(btrim(c.email),''),
 'phone',nullif(btrim(c.phone),''),'tax_number',nullif(btrim(c.tax_number),''),'notes',nullif(btrim(c.notes),''),
 'project_address',(select string_agg(a,E'\n' order by a collate "C") from
  (select distinct btrim(x) a from regexp_split_to_table(coalesce(c.project_address,''),E'\n') x where btrim(x)<>'') s))
$$;

create or replace function quote_private.customer_value_equal(k text,a jsonb,b jsonb) returns boolean
language sql immutable set search_path='' as $
 select case
 when a=b then true
 when a='null'::jsonb or b='null'::jsonb then false
 when k='phone' then length(quote_private.normalize_phone(a#>>'{}'))>=8
  and quote_private.normalize_phone(a#>>'{}')=quote_private.normalize_phone(b#>>'{}')
 when k in('name','email','contact_name','client_type') then
  lower(regexp_replace(btrim(a#>>'{}'),'[[:space:]]+',' ','g'))=lower(regexp_replace(btrim(b#>>'{}'),'[[:space:]]+',' ','g'))
 when k='project_address' then
  (select string_agg(x,E'\n' order by x collate "C") from
   (select distinct lower(regexp_replace(btrim(v),'[[:space:]]+',' ','g')) x from regexp_split_to_table(a#>>'{}',E'\n') v) s)
  = (select string_agg(x,E'\n' order by x collate "C") from
   (select distinct lower(regexp_replace(btrim(v),'[[:space:]]+',' ','g')) x from regexp_split_to_table(b#>>'{}',E'\n') v) s)
 else false end
$;
revoke all on function quote_private.customer_value_equal(text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function quote_private.customer_value_equal(text,jsonb,jsonb) to service_role;
grant execute on function quote_private.normalize_phone(text) to service_role;

-- Three-way, per-field merge. Conflicting edits wait for a human decision.
create or replace function quote_private.merge_customer_fields(local_fields jsonb, base_fields jsonb,
 remote_fields jsonb, previous_conflicts jsonb default '{}'::jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare k text; l jsonb; b jsonb; r jsonb; merged jsonb='{}'; conflicts jsonb='{}';
begin
 for k in select jsonb_object_keys(remote_fields) loop
  l=coalesce(local_fields->k,'null'::jsonb); b=coalesce(base_fields->k,'null'::jsonb); r=remote_fields->k;
  if quote_private.customer_value_equal(k,l,r) then merged=jsonb_set(merged,array[k],r);
  elsif coalesce(previous_conflicts,'{}'::jsonb) ? k then
   merged=jsonb_set(merged,array[k],l);
   conflicts=jsonb_set(conflicts,array[k],jsonb_build_object('local',l,'source',r,'base',b));
  elsif base_fields is null then
   if l='null'::jsonb then merged=jsonb_set(merged,array[k],r);
   elsif r='null'::jsonb then merged=jsonb_set(merged,array[k],l);
   else
    merged=jsonb_set(merged,array[k],l);
    conflicts=jsonb_set(conflicts,array[k],jsonb_build_object('local',l,'source',r,'base',b));
   end if;
  elsif l=b then merged=jsonb_set(merged,array[k],r);
  elsif r=b then merged=jsonb_set(merged,array[k],l);
  else
   merged=jsonb_set(merged,array[k],l);
   conflicts=jsonb_set(conflicts,array[k],jsonb_build_object('local',l,'source',r,'base',b));
  end if;
 end loop;
 return jsonb_build_object('fields',merged,'base',remote_fields,'conflicts',conflicts);
end $$;

drop trigger quote_clients_queue on public.quote_clients;
create or replace function quote_private.track_customer_changes() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and (quote_private.customer_fields(old) is distinct from quote_private.customer_fields(new)
  or old.billing_address is distinct from new.billing_address or old.shared_sync_enabled is distinct from new.shared_sync_enabled
  or old.merged_into is distinct from new.merged_into) then
  insert into public.quote_customer_history(client_id,actor,previous_data) values(old.id,auth.uid(),to_jsonb(old));
  new.sync_revision=old.sync_revision+1;
 end if;
 return new;
end $$;
create trigger quote_clients_history before update on public.quote_clients
for each row execute function quote_private.track_customer_changes();
create or replace function quote_private.queue_new_customer() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if current_setting('quote.skip_customer_queue',true)='on' then return new;end if;
 if new.shared_sync_enabled and new.merged_into is null and
  (tg_op='INSERT' or old.sync_revision<>new.sync_revision) then
  insert into public.quote_customer_sync(client_id) values(new.id)
  on conflict(client_id) do update set synced_at=null,last_error=null;
 end if;
 return new;
end $$;
create trigger quote_clients_queue after insert or update on public.quote_clients
for each row execute function quote_private.queue_new_customer();

-- Only the quote worker's service_role can accept source snapshots.
create function public.quote_customers_reconcile(p_company uuid,p_customers jsonb) returns integer
language plpgsql security invoker set search_path='' as $$
declare r jsonb; c public.quote_clients; fields jsonb; m jsonb; f jsonb; n integer=0;
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

create function public.quote_customers_pending(p_company uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('fields',quote_private.customer_fields(c::public.quote_clients))),'[]'::jsonb)
 from (select c.* from public.quote_customer_sync s join public.quote_clients c on c.id=s.client_id
  where s.synced_at is null and c.company_id=p_company and c.shared_sync_enabled and c.merged_into is null and c.sync_conflicts='{}'::jsonb
  order by s.last_attempt_at nulls first,s.created_at limit 10) c
$$;
revoke all on function public.quote_customers_pending(uuid) from public,anon,authenticated;
grant execute on function public.quote_customers_pending(uuid) to service_role;

-- Preserve the older nine-argument API via defaults, while current clients use revision checking.
drop function public.quote_clients_upsert(uuid,text,text,text,text,text,text,text,text);
create function public.quote_clients_upsert(p_id uuid,p_name text,p_client_type text,p_contact_name text,
 p_phone text,p_email text,p_billing_address text,p_project_address text,p_notes text,
 p_share boolean default null,p_expected_revision bigint default null) returns public.quote_clients
language plpgsql security definer set search_path='' as $$
declare company uuid=quote_private.staff_company();c public.quote_clients;
begin
 if company is null then raise exception 'Árajánlat-hozzáférés szükséges' using errcode='42501';end if;
 if nullif(btrim(p_name),'') is null then raise exception 'Az ügyfél neve kötelező';end if;
 if p_id is null then
  insert into public.quote_clients(company_id,name,client_type,contact_name,phone,email,billing_address,project_address,notes,shared_sync_enabled)
  values(company,btrim(p_name),p_client_type,p_contact_name,p_phone,p_email,p_billing_address,p_project_address,p_notes,coalesce(p_share,true)) returning * into c;
 else
  select * into c from public.quote_clients where id=p_id and company_id=company and merged_into is null for update;
  if not found then raise exception 'Az ügyfél nem található' using errcode='42501';end if;
  if p_expected_revision is not null and c.sync_revision<>p_expected_revision then
   raise exception 'Az ügyfél adatai közben megváltoztak. Frissítsd a listát, majd nyisd meg újra a szerkesztést.' using errcode='40001';end if;
  update public.quote_clients set name=btrim(p_name),client_type=p_client_type,contact_name=p_contact_name,phone=p_phone,email=p_email,
   billing_address=p_billing_address,project_address=p_project_address,notes=p_notes,
   shared_sync_enabled=coalesce(p_share,shared_sync_enabled) where id=c.id returning * into c;
 end if;
 return c;
end $$;
revoke all on function public.quote_clients_upsert(uuid,text,text,text,text,text,text,text,text,boolean,bigint) from public,anon;
grant execute on function public.quote_clients_upsert(uuid,text,text,text,text,text,text,text,text,boolean,bigint) to authenticated;

-- Preserve distinct work addresses when an operator combines customer entries.
create or replace function quote_private.merge_customer_addresses(a text,b text) returns text
language sql immutable set search_path='' as $$
 select coalesce(string_agg(address,E'\n' order by address collate "C"),'') from (
  select distinct on(lower(address)) address from (
   select regexp_replace(btrim(x),'[[:space:]]+',' ','g') address
   from regexp_split_to_table(coalesce(a,'')||E'\n'||coalesce(b,''),E'\n') x
   where btrim(x)<>''
  ) cleaned order by lower(address),address collate "C"
 ) combined
$$;
revoke all on function quote_private.merge_customer_addresses(text,text) from public,anon,authenticated;

create function public.quote_customer_resolve(p_id uuid,p_choices jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare c public.quote_clients;k text;f jsonb;v jsonb;
begin
 select * into c from public.quote_clients where id=p_id and company_id=quote_private.staff_company() for update;
 if not found then raise exception 'Árajánlat-hozzáférés szükséges' using errcode='42501';end if;
 f=quote_private.customer_fields(c);
 for k in select jsonb_object_keys(c.sync_conflicts) loop
  if (p_choices->>k not in('source','local') and not(k='project_address' and p_choices->>k='both')) or p_choices->>k is null then raise exception 'Minden eltérésnél válassz értéket.';end if;
  if p_choices->>k='source' then f=jsonb_set(f,array[k],c.sync_conflicts#>array[k,'source']);end if;
  if k='project_address' and p_choices->>k='both' then
   f=jsonb_set(f,array[k],to_jsonb(quote_private.merge_customer_addresses(c.sync_conflicts#>>array[k,'local'],c.sync_conflicts#>>array[k,'source'])));
  end if;
 end loop;
 update public.quote_clients set name=f->>'name',client_type=f->>'client_type',contact_name=f->>'contact_name',
  email=f->>'email',phone=f->>'phone',tax_number=f->>'tax_number',notes=f->>'notes',project_address=f->>'project_address',
  sync_conflicts='{}'::jsonb where id=c.id;
 insert into public.quote_customer_sync(client_id) values(c.id) on conflict(client_id) do update set synced_at=null,last_error=null;
end $$;
revoke all on function public.quote_customer_resolve(uuid,jsonb) from public,anon;
grant execute on function public.quote_customer_resolve(uuid,jsonb) to authenticated;

-- A worker lease prevents simultaneous devices from duplicating cross-project writes.
create table public.quote_customer_sync_leases(company_id uuid primary key,owner uuid,expires_at timestamptz);
alter table public.quote_customer_sync_leases enable row level security;
revoke all on public.quote_customer_sync_leases from public,anon,authenticated;
grant all on public.quote_customer_sync_leases to service_role;
create function public.quote_customer_sync_lease(p_company uuid,p_owner uuid,p_release boolean default false) returns boolean
language plpgsql security invoker set search_path='' as $$
begin
 if p_release then delete from public.quote_customer_sync_leases where company_id=p_company and owner=p_owner;return true;end if;
 insert into public.quote_customer_sync_leases(company_id,owner,expires_at) values(p_company,p_owner,now()+interval '120 seconds')
 on conflict(company_id) do update set owner=excluded.owner,expires_at=excluded.expires_at
 where public.quote_customer_sync_leases.expires_at<now() or public.quote_customer_sync_leases.owner=p_owner;
 return found;
end $$;
revoke all on function public.quote_customer_sync_lease(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.quote_customer_sync_lease(uuid,uuid,boolean) to service_role;

-- Explicitly attach a legacy entry to an existing common customer, preserving history.
create function public.quote_customer_link(p_id uuid,p_target uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare a public.quote_clients;b public.quote_clients;company uuid=quote_private.staff_company();
begin
 if company is null or p_id=p_target then raise exception 'Érvénytelen ügyfélkapcsolás' using errcode='42501';end if;
 perform 1 from public.quote_clients where id in(p_id,p_target) order by id for update;
 select * into a from public.quote_clients where id=p_id and company_id=company and merged_into is null;
 if not found or a.source_customer_id is not null then raise exception 'A régi ügyfél nem kapcsolható';end if;
 select * into b from public.quote_clients where id=p_target and company_id=company and source_customer_id is not null and merged_into is null;
 if not found then raise exception 'A közös ügyfél nem található' using errcode='42501';end if;
 update public.quote_clients set
  email=coalesce(nullif(email,''),nullif(a.email,'')),phone=coalesce(nullif(phone,''),nullif(a.phone,'')),
  contact_name=coalesce(nullif(contact_name,''),nullif(a.contact_name,'')),
  billing_address=coalesce(nullif(billing_address,''),nullif(a.billing_address,'')),
  tax_number=coalesce(nullif(tax_number,''),nullif(a.tax_number,'')),
  project_address=quote_private.merge_customer_addresses(project_address,a.project_address),
  notes=coalesce(nullif(notes,''),nullif(a.notes,'')) where id=b.id;
 update public.quote_projects set client_id=b.id where client_id=a.id;
 update public.quote_clients set merged_into=b.id,shared_sync_enabled=false where id=a.id;
 update public.quote_customer_sync set synced_at=now(),last_error=null where client_id=a.id;
 return b.id;
end $$;
revoke all on function public.quote_customer_link(uuid,uuid) from public,anon;
grant execute on function public.quote_customer_link(uuid,uuid) to authenticated;
create or replace function public.quote_clients_list() returns setof public.quote_clients
language plpgsql stable security definer set search_path='' as $$
declare company uuid=quote_private.staff_company();
begin
 if company is null then raise exception 'Árajánlat-hozzáférés szükséges' using errcode='42501';end if;
 return query select * from public.quote_clients where company_id=company and merged_into is null order by name;
end $$;

revoke all on function quote_private.customer_fields(public.quote_clients) from public,anon,authenticated;
revoke all on function quote_private.merge_customer_fields(jsonb,jsonb,jsonb,jsonb) from public,anon,authenticated;
revoke all on function quote_private.track_customer_changes() from public,anon,authenticated;
grant execute on function quote_private.customer_fields(public.quote_clients) to service_role;
grant execute on function quote_private.merge_customer_fields(jsonb,jsonb,jsonb,jsonb) to service_role;
notify pgrst,'reload schema';
