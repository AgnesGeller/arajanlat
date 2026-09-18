-- Árajánlat-only Auth accounts use quote_staff for their company boundary.
-- No profile is created for these accounts, so the existing non-quote RLS
-- policies (which require profiles.id = auth.uid()) continue to deny access.
-- Apply before adding the two new Auth user IDs to quote_staff.

alter table public.quote_staff
  add column if not exists company_id uuid references public.companies(id);

update public.quote_staff s
set company_id = p.company_id
from public.profiles p
where p.id = s.user_id and s.company_id is null;

alter table public.quote_staff
  alter column company_id set not null;

create or replace function quote_private.staff_company() returns uuid
language sql stable security definer set search_path = '' as $$
  select s.company_id
  from public.quote_staff s
  where s.user_id = (select auth.uid())
  limit 1
$$;

-- The shared clients table and its existing RLS policies remain unchanged.
-- These quote-only entry points check membership and company on the server.
create or replace function public.quote_clients_list()
returns setof public.clients
language plpgsql stable security definer set search_path = '' as $$
declare
  v_company uuid := quote_private.staff_company();
begin
  if v_company is null then
    raise exception 'Árajánlat-hozzáférés szükséges' using errcode = '42501';
  end if;
  return query select c.* from public.clients c
  where c.company_id = v_company order by c.created_at desc;
end $$;

create or replace function public.quote_clients_upsert(
  p_id uuid, p_name text, p_client_type text, p_contact_name text,
  p_phone text, p_email text, p_billing_address text,
  p_project_address text, p_notes text
)
returns public.clients
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_company uuid := quote_private.staff_company();
  v_client public.clients;
begin
  if v_company is null then
    raise exception 'Árajánlat-hozzáférés szükséges' using errcode = '42501';
  end if;
  if nullif(trim(p_name), '') is null then
    raise exception 'Az ügyfél neve kötelező' using errcode = '22023';
  end if;
  if p_id is null then
    insert into public.clients
      (company_id, name, client_type, contact_name, phone, email,
       billing_address, project_address, notes)
    values
      (v_company, trim(p_name), p_client_type, p_contact_name, p_phone, p_email,
       p_billing_address, p_project_address, p_notes)
    returning * into v_client;
  else
    update public.clients c
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
end $$;

revoke all on function public.quote_clients_list() from public, anon;
revoke all on function public.quote_clients_upsert(uuid,text,text,text,text,text,text,text,text) from public, anon;
grant execute on function public.quote_clients_list() to authenticated;
grant execute on function public.quote_clients_upsert(uuid,text,text,text,text,text,text,text,text) to authenticated;
