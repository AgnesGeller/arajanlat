-- Own customer directory; legacy IDs and fields remain intact.
-- Apply after schema.sql and quote_auth_isolation.sql.
create table public.quote_clients (
 like public.clients including defaults including constraints,
 source_customer_id uuid,
 source_payload jsonb,
 primary key (id),
 foreign key (company_id) references public.companies(id),
 unique (company_id, source_customer_id)
);
insert into public.quote_clients
select c.*, null::uuid, null::jsonb from public.clients c
where c.company_id in (select company_id from public.quote_staff);

alter table public.quote_clients enable row level security;
revoke all on public.quote_clients from anon, authenticated;
grant select on public.quote_clients to authenticated;
create policy quote_clients_staff_read on public.quote_clients for select to authenticated
using (company_id = (select quote_private.staff_company()));
create index quote_clients_company_idx on public.quote_clients(company_id);
create trigger quote_clients_updated before update on public.quote_clients
for each row execute function quote_private.touch_updated_at();

alter table public.quote_projects drop constraint quote_projects_client_id_fkey;
alter table public.quote_projects add constraint quote_projects_client_id_fkey
foreign key (client_id) references public.quote_clients(id) on delete restrict;

CREATE OR REPLACE FUNCTION quote_private.can_client(p_client uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.quote_clients c where c.id=p_client and c.company_id=quote_private.staff_company())
$function$;

CREATE OR REPLACE FUNCTION quote_private.public_identity_matches(p_project_id uuid, p_identity_type text, p_identity_value text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare customer_name text; contact_name text; customer_email text; customer_phone text; normalized text;
begin
 if p_identity_type is null or p_identity_type not in ('name','email','phone') or length(coalesce(p_identity_value,''))>254 then return false; end if;
 select c.name,c.contact_name,c.email,c.phone into customer_name,contact_name,customer_email,customer_phone
 from public.quote_projects p join public.quote_clients c on c.id=p.client_id where p.id=p_project_id;
 if not found then return false; end if;
 if p_identity_type='name' then
  normalized=lower(regexp_replace(btrim(coalesce(p_identity_value,'')),'[[:space:]]+',' ','g'));
  return length(normalized)>=2 and (normalized=lower(regexp_replace(btrim(coalesce(customer_name,'')),'[[:space:]]+',' ','g'))
    or normalized=lower(regexp_replace(btrim(coalesce(contact_name,'')),'[[:space:]]+',' ','g')));
 elsif p_identity_type='email' then
  normalized=lower(btrim(coalesce(p_identity_value,'')));
  return length(normalized)>=3 and normalized=lower(btrim(coalesce(customer_email,'')));
 else
  normalized=quote_private.normalize_phone(p_identity_value);
  return length(normalized)>=8 and normalized=quote_private.normalize_phone(customer_phone);
 end if;
end $function$;

drop function public.quote_clients_list();
drop function public.quote_clients_upsert(uuid,text,text,text,text,text,text,text,text);
CREATE OR REPLACE FUNCTION public.quote_clients_list()
 RETURNS SETOF public.quote_clients
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_company uuid := quote_private.staff_company();
begin
  if v_company is null then
    raise exception 'Árajánlat-hozzáférés szükséges' using errcode = '42501';
  end if;
  return query select c.* from public.quote_clients c
  where c.company_id = v_company order by c.created_at desc;
end $function$;

CREATE OR REPLACE FUNCTION public.quote_clients_upsert(p_id uuid, p_name text, p_client_type text, p_contact_name text, p_phone text, p_email text, p_billing_address text, p_project_address text, p_notes text)
 RETURNS public.quote_clients
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_company uuid := quote_private.staff_company();
  v_client public.quote_clients;
begin
  if v_company is null then
    raise exception 'Árajánlat-hozzáférés szükséges' using errcode = '42501';
  end if;
  if nullif(trim(p_name), '') is null then
    raise exception 'Az ügyfél neve kötelező' using errcode = '22023';
  end if;
  if p_id is null then
    insert into public.quote_clients
      (company_id, name, client_type, contact_name, phone, email,
       billing_address, project_address, notes)
    values
      (v_company, trim(p_name), p_client_type, p_contact_name, p_phone, p_email,
       p_billing_address, p_project_address, p_notes)
    returning * into v_client;
  else
    update public.quote_clients c
    set name = trim(p_name), client_type = p_client_type,
        contact_name = p_contact_name, phone = p_phone, email = p_email,
        billing_address = p_billing_address,
        project_address = p_project_address, notes = p_notes
    where c.id = p_id and c.company_id = v_company
    returning * into v_client;
    if not found then
      raise exception 'Az ügyfél nem található' using errcode = '42501';
    end if;
  end if;
  return v_client;
end $function$;

revoke all on function public.quote_clients_list() from public, anon;
revoke all on function public.quote_clients_upsert(uuid,text,text,text,text,text,text,text,text) from public, anon;
grant execute on function public.quote_clients_list() to authenticated;
grant execute on function public.quote_clients_upsert(uuid,text,text,text,text,text,text,text,text) to authenticated;

-- Administrative import, never callable by app users. No customer data in Git.
-- p_customers: [{id, full_name, details, locations}], active/approved only.
create or replace function quote_private.import_customers(p_company uuid, p_customers jsonb)
returns integer language plpgsql security invoker set search_path = '' as $$
declare r jsonb; v_id uuid; v_name text; v_matches integer; v_count integer := 0;
begin
 if not exists(select 1 from public.quote_staff where company_id=p_company) then
  raise exception 'Unknown quote company';
 end if;
 for r in select value from jsonb_array_elements(p_customers) loop
  v_name := regexp_replace(btrim(r->>'full_name'),'[[:space:]]+',' ','g');
  if nullif(v_name,'') is null or nullif(r->>'id','') is null then
   raise exception 'Invalid customer import';
  end if;
  select id into v_id from public.quote_clients
   where company_id=p_company and source_customer_id=(r->>'id')::uuid;
  if v_id is null then
   select count(*), (array_agg(id))[1] into v_matches,v_id from public.quote_clients
   where company_id=p_company and source_customer_id is null
    and lower(regexp_replace(btrim(name),'[[:space:]]+',' ','g'))=lower(v_name);
   if v_matches <> 1 then v_id := null; end if;
  end if;
  if v_id is null then
   insert into public.quote_clients(company_id,name) values(p_company,v_name)
   returning id into v_id;
  end if;
  update public.quote_clients set
   source_customer_id=(r->>'id')::uuid, source_payload=r,
   email=coalesce(nullif(email,''),nullif(r#>>'{details,email}','')),
   phone=coalesce(nullif(phone,''),nullif(r#>>'{details,phone}','')),
   contact_name=coalesce(nullif(contact_name,''),nullif(r#>>'{details,contact_name}','')),
   client_type=coalesce(nullif(client_type,''),nullif(r#>>'{details,customer_type}','')),
   tax_number=coalesce(nullif(tax_number,''),nullif(r#>>'{details,tax_number}','')),
   notes=coalesce(nullif(notes,''),nullif(r#>>'{details,notes}','')),
   project_address=coalesce(nullif(project_address,''),
    (select string_agg(x->>'address', E'\n' order by x->>'address')
     from jsonb_array_elements(coalesce(r->'locations','[]'::jsonb)) x))
  where id=v_id and company_id=p_company;
  v_count := v_count+1;
 end loop;
 return v_count;
end $$;
revoke all on function quote_private.import_customers(uuid,jsonb) from public, anon, authenticated;
notify pgrst, 'reload schema';
