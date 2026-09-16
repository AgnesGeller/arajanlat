-- Existing KAP Auth users. Does not change Auth, profiles, clients or Munkalap tables.
insert into public.quote_staff(user_id) values
  ('10ed3e98-feb4-43d0-aff6-dcefc1b2d54d'), -- Tamás
  ('28a64f52-25f6-4163-964d-80a2adbaaa02')  -- Ági
on conflict(user_id) do nothing;
