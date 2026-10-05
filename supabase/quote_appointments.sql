-- Independent quotation calendar. No changes to source customer or other app tables.
alter table public.quote_projects add column meeting_required boolean not null default false;

create table public.quote_appointment_slots (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id),
 starts_at timestamptz not null,
 ends_at timestamptz not null,
 withdrawn boolean not null default false,
 updated_at timestamptz not null default now(),
 check (ends_at > starts_at and ends_at <= starts_at + interval '8 hours')
);
create index quote_appointment_slots_company_time on public.quote_appointment_slots(company_id,starts_at);
create table public.quote_appointments (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id),
 project_id uuid not null references public.quote_projects(id),
 slot_id uuid not null references public.quote_appointment_slots(id),
 status text not null default 'booked' check(status in ('booked','cancelled')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index quote_appointments_one_slot on public.quote_appointments(slot_id) where status='booked';
create unique index quote_appointments_one_project on public.quote_appointments(project_id) where status='booked';
create index quote_appointments_company on public.quote_appointments(company_id);
create index quote_appointments_slot on public.quote_appointments(slot_id);
create index quote_appointments_project on public.quote_appointments(project_id);
alter table public.quote_appointment_slots enable row level security;
alter table public.quote_appointments enable row level security;
revoke all on public.quote_appointment_slots,public.quote_appointments from anon,authenticated;
grant select on public.quote_appointment_slots,public.quote_appointments to authenticated;
create policy quote_slots_read on public.quote_appointment_slots for select to authenticated
 using(company_id=(select quote_private.staff_company()));
create policy quote_appointments_read on public.quote_appointments for select to authenticated
 using(company_id=(select quote_private.staff_company()));

-- All calendar writes share one company transaction lock, including slot edits.
create function quote_private.appointment_slot_save(p_id uuid,p_start timestamptz,p_end timestamptz,p_withdrawn boolean,p_expected timestamptz)
returns uuid language plpgsql security definer set search_path='' as $$
declare company uuid:=quote_private.staff_company(); result uuid; old public.quote_appointment_slots%rowtype;
begin
 if company is null then raise exception 'Nincs jogosultság.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('quote-calendar:'||company::text,0));
 if p_start is null or p_end is null or p_end<=p_start or p_end>p_start+interval '8 hours' then raise exception 'Ellenőrizd a kezdő és befejező időpontot.'; end if;
 if p_id is null then
  if p_start<=now() then raise exception 'Csak jövőbeli időpont adható meg.'; end if;
  insert into public.quote_appointment_slots(company_id,starts_at,ends_at) values(company,p_start,p_end) returning id into result;
 else
  select * into old from public.quote_appointment_slots where id=p_id and company_id=company for update;
  if not found then raise exception 'Az időpont nem elérhető.'; end if;
  if p_expected is distinct from old.updated_at then raise exception 'Az időpont közben változott. Frissítsd a listát.'; end if;
  if exists(select 1 from public.quote_appointments where slot_id=p_id and status='booked') then raise exception 'Foglalt időpontnál a foglalást módosítsd vagy mondd le.'; end if;
  if (p_start<>old.starts_at or p_end<>old.ends_at) and exists(select 1 from public.quote_appointments where slot_id=p_id) then raise exception 'Ez az időpont már szerepel foglalási előzményben. Új időpontot vegyél fel.'; end if;
  if not p_withdrawn and p_start<=now() then raise exception 'Csak jövőbeli időpont kínálható fel.'; end if;
  update public.quote_appointment_slots set starts_at=p_start,ends_at=p_end,withdrawn=p_withdrawn,updated_at=clock_timestamp() where id=p_id returning id into result;
 end if;
 return result;
end $$;

-- Public reads reveal only available times, never the other projects/customers.
create function quote_private.available_appointment_slots(p_company uuid)
returns jsonb language sql stable set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'starts_at',s.starts_at,'ends_at',s.ends_at) order by s.starts_at),'[]'::jsonb)
 from public.quote_appointment_slots s where s.company_id=p_company and not s.withdrawn and s.starts_at>now()
 and not exists(select 1 from public.quote_appointments a join public.quote_appointment_slots b on b.id=a.slot_id
  where a.company_id=p_company and a.status='booked' and s.starts_at<b.ends_at and b.starts_at<s.ends_at)
$$;

-- Called only by validated request submission or staff change, in the company lock.
create function quote_private.appointment_book(p_project uuid,p_slot uuid)
returns jsonb language plpgsql set search_path='' as $$
declare s public.quote_appointment_slots%rowtype; company uuid; booking uuid;
begin
 select c.company_id into company from public.quote_projects p join public.quote_clients c on c.id=p.client_id where p.id=p_project;
 perform pg_advisory_xact_lock(hashtextextended('quote-calendar:'||company::text,0));
 select * into s from public.quote_appointment_slots where id=p_slot and company_id=company and not withdrawn and starts_at>now() for update;
 if not found then raise exception 'Ez az időpont már nem elérhető. Válasszon másikat, vagy kérjen telefonos egyeztetést.'; end if;
 if exists(select 1 from public.quote_appointments a join public.quote_appointment_slots b on b.id=a.slot_id
  where a.company_id=company and a.status='booked' and s.starts_at<b.ends_at and b.starts_at<s.ends_at) then
  raise exception 'Ez az időpont közben elkelt. Válasszon másikat, vagy kérjen telefonos egyeztetést.';
 end if;
 if exists(select 1 from public.quote_appointments where project_id=p_project and status='booked') then raise exception 'A projekthez már van foglalás. Kérjen telefonos egyeztetést.'; end if;
 insert into public.quote_appointments(company_id,project_id,slot_id) values(company,p_project,s.id) returning id into booking;
 insert into public.quote_timeline(project_id,event,note) values(p_project,'Találkozó lefoglalva',to_char(s.starts_at at time zone 'Europe/Budapest','YYYY.MM.DD. HH24:MI'));
 return jsonb_build_object('id',booking,'starts_at',s.starts_at,'ends_at',s.ends_at);
end $$;

create function quote_private.appointment_change(p_id uuid,p_slot uuid,p_expected timestamptz)
returns jsonb language plpgsql security definer set search_path='' as $$
declare company uuid:=quote_private.staff_company(); a public.quote_appointments%rowtype; result jsonb;
begin
 if company is null then raise exception 'Nincs jogosultság.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('quote-calendar:'||company::text,0));
 select * into a from public.quote_appointments where id=p_id and company_id=company and status='booked' for update;
 if not found or not quote_private.can_project(a.project_id) then raise exception 'A foglalás nem elérhető.'; end if;
 if p_expected is distinct from a.updated_at then raise exception 'A foglalás közben változott. Frissítsd a listát.'; end if;
 update public.quote_appointments set status='cancelled',updated_at=clock_timestamp() where id=a.id;
 insert into public.quote_timeline(project_id,event) values(a.project_id,case when p_slot is null then 'Találkozó lemondva' else 'Találkozó időpontja módosítva' end);
 if p_slot is not null then result:=quote_private.appointment_book(a.project_id,p_slot); end if;
 return result;
end $$;
create function public.quote_appointment_slot_save(p_id uuid,p_start timestamptz,p_end timestamptz,p_withdrawn boolean,p_expected timestamptz)
returns uuid language sql security invoker set search_path='' as $$ select quote_private.appointment_slot_save(p_id,p_start,p_end,p_withdrawn,p_expected) $$;
create function public.quote_appointment_change(p_id uuid,p_slot uuid,p_expected timestamptz)
returns jsonb language sql security invoker set search_path='' as $$ select quote_private.appointment_change(p_id,p_slot,p_expected) $$;
revoke all on function quote_private.appointment_slot_save(uuid,timestamptz,timestamptz,boolean,timestamptz),quote_private.appointment_change(uuid,uuid,timestamptz),quote_private.available_appointment_slots(uuid),quote_private.appointment_book(uuid,uuid) from public,anon,authenticated;
grant execute on function quote_private.appointment_slot_save(uuid,timestamptz,timestamptz,boolean,timestamptz),quote_private.appointment_change(uuid,uuid,timestamptz) to authenticated;
revoke all on function public.quote_appointment_slot_save(uuid,timestamptz,timestamptz,boolean,timestamptz),public.quote_appointment_change(uuid,uuid,timestamptz) from public,anon;
grant execute on function public.quote_appointment_slot_save(uuid,timestamptz,timestamptz,boolean,timestamptz),public.quote_appointment_change(uuid,uuid,timestamptz) to authenticated;

create function quote_private.appointment_staff_book(p_project uuid,p_slot uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if quote_private.staff_company() is null or not quote_private.can_project(p_project) then raise exception 'Nincs jogosultság.'; end if;
 if not exists(select 1 from public.quote_projects where id=p_project and meeting_required) then raise exception 'Előbb kapcsold be a találkozót a projektnél.'; end if;
 return quote_private.appointment_book(p_project,p_slot);
end $$;
create function public.quote_appointment_book(p_project uuid,p_slot uuid) returns jsonb language sql security invoker set search_path='' as $$ select quote_private.appointment_staff_book(p_project,p_slot) $$;
revoke all on function quote_private.appointment_staff_book(uuid,uuid),public.quote_appointment_book(uuid,uuid) from public,anon,authenticated;
grant execute on function quote_private.appointment_staff_book(uuid,uuid),public.quote_appointment_book(uuid,uuid) to authenticated;

create or replace function public.quote_public_read(p_token text,p_identity_type text,p_identity_value text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare tok public.quote_public_tokens%rowtype; result jsonb;
begin
 if length(coalesce(p_token,''))<>64 or p_token !~ '^[0-9a-f]{64}$' then return null; end if;
 select * into tok from public.quote_public_tokens where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and revoked_at is null and expires_at>now();
 if not found or not quote_private.public_identity_matches(tok.project_id,p_identity_type,p_identity_value) then return null; end if;
 if tok.purpose='request' then
  select jsonb_build_object('purpose','request','project',p.name,'work_address',p.work_address,'meeting_required',p.meeting_required,
   'appointment', (select jsonb_build_object('starts_at',s.starts_at,'ends_at',s.ends_at) from public.quote_appointments a join public.quote_appointment_slots s on s.id=a.slot_id where a.project_id=p.id and a.status='booked'),
   'slots',case when p.meeting_required then quote_private.available_appointment_slots(c.company_id) else '[]'::jsonb end)
  into result from public.quote_projects p join public.quote_clients c on c.id=p.client_id where p.id=tok.project_id;
 else
  select v.published_snapshot into result from public.quote_versions v where v.id=tok.version_id and v.status in ('published','accepted','rejected');
 end if;
 return result;
end $$;

create function public.quote_public_request_submit(p_token text,p_identity_type text,p_identity_value text,p_answers jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare tok public.quote_public_tokens%rowtype; p public.quote_projects%rowtype; appointment jsonb; choice text; clean jsonb; company uuid;
begin
 if length(coalesce(p_token,''))<>64 or p_token !~ '^[0-9a-f]{64}$' or p_answers is null or jsonb_typeof(p_answers)<>'object' or octet_length(p_answers::text)>20000 then return null; end if;
 select * into tok from public.quote_public_tokens where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and purpose='request' and revoked_at is null and expires_at>now() for update;
 if not found or not quote_private.public_identity_matches(tok.project_id,p_identity_type,p_identity_value) then return null; end if;
 select * into p from public.quote_projects where id=tok.project_id for no key update;
 select c.company_id into company from public.quote_clients c where c.id=p.client_id;
 perform pg_advisory_xact_lock(hashtextextended('quote-calendar:'||company::text,0));
 clean:=p_answers-'meeting_choice'-'appointment';
 if p.meeting_required then
  select jsonb_build_object('id',a.id,'starts_at',s.starts_at,'ends_at',s.ends_at) into appointment from public.quote_appointments a join public.quote_appointment_slots s on s.id=a.slot_id where a.project_id=p.id and a.status='booked';
  if appointment is null then
   choice:=p_answers->>'meeting_choice';
   if choice='phone' then
    insert into public.quote_timeline(project_id,event) values(p.id,'Telefonos időpont-egyeztetést kér az ügyfél');
    clean:=clean||jsonb_build_object('meeting_choice','phone');
   elsif choice ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    appointment:=quote_private.appointment_book(p.id,choice::uuid);
   else raise exception 'Válasszon időpontot vagy telefonos egyeztetést.';
   end if;
  end if;
  if appointment is not null then clean:=clean||jsonb_build_object('appointment',appointment); end if;
 end if;
 insert into public.quote_client_requests(project_id,answers) values(p.id,clean);
 insert into public.quote_timeline(project_id,event) values(p.id,'Ügyfél adatbekérő visszaérkezett');
 update public.quote_projects set status='Ügyfél kitöltötte' where id=p.id;
 update public.quote_public_tokens set revoked_at=now() where id=tok.id;
 return jsonb_build_object('saved',true,'appointment',appointment,'phone_requested',clean->>'meeting_choice'='phone');
end $$;
-- Retain the existing API for cached clients; the new client gets canonical booking times.
create or replace function public.quote_public_submit(p_token text,p_identity_type text,p_identity_value text,p_answers jsonb)
returns boolean language sql security definer set search_path='' as $$
 select public.quote_public_request_submit(p_token,p_identity_type,p_identity_value,p_answers) is not null
$$;
revoke all on function public.quote_public_request_submit(text,text,text,jsonb) from public;
grant execute on function public.quote_public_request_submit(text,text,text,jsonb) to anon,authenticated;
