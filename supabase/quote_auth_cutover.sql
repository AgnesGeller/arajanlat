-- Run only after successful sign-in and RLS tests for both new quote users.
-- Retires only the two named legacy grants from quote_staff. Their Auth users,
-- profiles, and all non-quote permissions remain untouched.

do $$
declare
  agi_id uuid;
  tamas_id uuid;
begin
  select id into agi_id from auth.users
  where lower(email) = 'agi@arajanlat.diszkertek.hu';
  select id into tamas_id from auth.users
  where lower(email) = 'tamas@arajanlat.diszkertek.hu';
  if agi_id is null or tamas_id is null
     or not exists (select 1 from public.quote_staff where user_id = agi_id)
     or not exists (select 1 from public.quote_staff where user_id = tamas_id) then
    raise exception 'Both quote-only Auth users must be provisioned first';
  end if;
  delete from public.quote_staff
  where user_id in (
    select id from auth.users
    where lower(email) in ('darlingagnes@gmail.com', 'info@diszkertek.hu')
  );
end $$;
