-- Run after the two quote-only Supabase Auth users have been created with
-- the requested PINs as their passwords and email confirmation enabled.
-- Do not create public.profiles rows for these users.

do $$
declare
  agi_id uuid;
  tamas_id uuid;
  quote_company_id uuid;
begin
  select id into agi_id from auth.users
  where lower(email) = 'agi@arajanlat.diszkertek.hu';
  select id into tamas_id from auth.users
  where lower(email) = 'tamas@arajanlat.diszkertek.hu';
  if agi_id is null or tamas_id is null then
    raise exception 'Both quote-only Auth users must exist before provisioning';
  end if;
  if exists (select 1 from public.profiles where id in (agi_id, tamas_id)) then
    raise exception 'Quote-only Auth users must not have KAP profiles';
  end if;
  if (select count(distinct company_id) from public.quote_staff) <> 1 then
    raise exception 'Quote company cannot be determined unambiguously';
  end if;
  select company_id into quote_company_id from public.quote_staff limit 1;
  insert into public.quote_staff (user_id, company_id)
  values (agi_id, quote_company_id), (tamas_id, quote_company_id)
  on conflict (user_id) do update set company_id = excluded.company_id;
end $$;
