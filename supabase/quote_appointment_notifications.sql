create table public.quote_appointment_events (
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id),
 project_id uuid not null references public.quote_projects(id), appointment_id uuid references public.quote_appointments(id),
 kind text not null check(kind in ('booked','cancelled','reminder','phone')),
 due_at timestamptz not null, expires_at timestamptz not null,
 cancelled boolean not null default false, email_sent_at timestamptz, push_done_at timestamptz,
 lease_until timestamptz, next_attempt_at timestamptz not null default now(), last_error text,
 created_at timestamptz not null default now()
);
create index quote_appointment_events_due on public.quote_appointment_events(due_at,next_attempt_at) where not cancelled;
create index quote_appointment_events_company on public.quote_appointment_events(company_id);
create index quote_appointment_events_project on public.quote_appointment_events(project_id);
create index quote_appointment_events_appointment on public.quote_appointment_events(appointment_id);
create table public.quote_appointment_event_reads (
 event_id uuid not null references public.quote_appointment_events(id), user_id uuid not null references auth.users(id),
 primary key(event_id,user_id)
);
create table public.quote_push_subscriptions (
 id uuid primary key default gen_random_uuid(), company_id uuid not null references public.companies(id),
 user_id uuid not null references auth.users(id), endpoint text not null unique, keys jsonb not null,
 updated_at timestamptz not null default now(), disabled boolean not null default false
);
create index quote_push_subscriptions_company on public.quote_push_subscriptions(company_id);
create index quote_push_subscriptions_user on public.quote_push_subscriptions(user_id);
create table quote_private.quote_push_deliveries (
 event_id uuid not null references public.quote_appointment_events(id), subscription_id uuid not null references public.quote_push_subscriptions(id),
 sent_at timestamptz not null default now(), primary key(event_id,subscription_id)
);
alter table public.quote_appointment_events enable row level security;
alter table public.quote_appointment_event_reads enable row level security;
alter table public.quote_push_subscriptions enable row level security;
alter table quote_private.quote_push_deliveries enable row level security;
revoke all on public.quote_appointment_events,public.quote_appointment_event_reads,public.quote_push_subscriptions from public,anon,authenticated;
revoke all on quote_private.quote_push_deliveries from public,anon,authenticated;
grant all on public.quote_appointment_events,public.quote_appointment_event_reads,public.quote_push_subscriptions,quote_private.quote_push_deliveries to service_role;
grant select on public.quote_appointment_events,public.quote_appointment_event_reads to authenticated;
create policy quote_events_read on public.quote_appointment_events for select to authenticated using(company_id=(select quote_private.staff_company()));
create policy quote_event_reads_read on public.quote_appointment_event_reads for select to authenticated using(user_id=(select auth.uid()) and exists(select 1 from public.quote_appointment_events e where e.id=event_id));
create policy quote_push_service_only on public.quote_push_subscriptions for all to service_role using(true) with check(true);
create policy quote_push_delivery_service_only on quote_private.quote_push_deliveries for all to service_role using(true) with check(true);

create function quote_private.appointment_event_queue() returns trigger language plpgsql security definer set search_path='' as $$
declare s public.quote_appointment_slots%rowtype;
begin
 select * into s from public.quote_appointment_slots where id=new.slot_id;
 if tg_op='INSERT' and new.status='booked' then
  insert into public.quote_appointment_events(company_id,project_id,appointment_id,kind,due_at,expires_at)
   values(new.company_id,new.project_id,new.id,'booked',now(),s.starts_at);
  if s.starts_at>now()+interval '2 hours' then
   insert into public.quote_appointment_events(company_id,project_id,appointment_id,kind,due_at,expires_at)
    values(new.company_id,new.project_id,new.id,'reminder',s.starts_at-interval '2 hours',s.starts_at);
  end if;
 elsif tg_op='UPDATE' and old.status='booked' and new.status='cancelled' then
  update public.quote_appointment_events set cancelled=true where appointment_id=new.id and kind in ('booked','reminder');
  insert into public.quote_appointment_events(company_id,project_id,appointment_id,kind,due_at,expires_at)
   values(new.company_id,new.project_id,new.id,'cancelled',now(),now()+interval '1 day');
 end if;
 return new;
end $$;
create trigger quote_appointment_notifications after insert or update of status on public.quote_appointments for each row execute function quote_private.appointment_event_queue();
create function quote_private.appointment_phone_queue() returns trigger language plpgsql security definer set search_path='' as $$
declare company uuid;
begin
 if new.event='Telefonos időpont-egyeztetést kér az ügyfél' then
  select c.company_id into company from public.quote_projects p join public.quote_clients c on c.id=p.client_id where p.id=new.project_id;
  insert into public.quote_appointment_events(company_id,project_id,kind,due_at,expires_at) values(company,new.project_id,'phone',now(),now()+interval '1 day');
 end if;
 return new;
end $$;
create trigger quote_appointment_phone_notification after insert on public.quote_timeline for each row execute function quote_private.appointment_phone_queue();
revoke all on function quote_private.appointment_event_queue(),quote_private.appointment_phone_queue() from public,anon,authenticated;

create function quote_private.appointment_event_seen(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.quote_appointment_events where id=p_id and company_id=quote_private.staff_company() and due_at<=now()) then raise exception 'Nincs jogosultság.'; end if;
 insert into public.quote_appointment_event_reads(event_id,user_id) values(p_id,auth.uid()) on conflict do nothing;
end $$;
create function public.quote_appointment_event_seen(p_id uuid) returns void language sql security invoker set search_path='' as $$ select quote_private.appointment_event_seen(p_id) $$;
create function quote_private.notification_public_key() returns text language plpgsql security definer set search_path='' as $$
begin
 if quote_private.staff_company() is null then raise exception 'Nincs jogosultság.'; end if;
 return (select decrypted_secret from vault.decrypted_secrets where name='quote_push_public_key');
end $$;
create function public.quote_notification_public_key() returns text language sql security invoker set search_path='' as $$ select quote_private.notification_public_key() $$;
create function quote_private.push_subscribe(p_subscription jsonb) returns void language plpgsql security definer set search_path='' as $$
declare company uuid:=quote_private.staff_company(); endpoint text:=p_subscription->>'endpoint'; k jsonb:=p_subscription->'keys';
begin
 if company is null then raise exception 'Nincs jogosultság.'; end if;
 if endpoint is null or length(endpoint)>4096 or endpoint !~ '^https://(fcm[.]googleapis[.]com|updates[.]push[.]services[.]mozilla[.]com|[a-z0-9-]+[.]notify[.]windows[.]com|web[.]push[.]apple[.]com)/[^?#]+$'
  or coalesce(k->>'p256dh','') !~ '^[A-Za-z0-9_-]{87}$' or coalesce(k->>'auth','') !~ '^[A-Za-z0-9_-]{22}$' then raise exception 'Az eszköz értesítése nem állítható be.'; end if;
 insert into public.quote_push_subscriptions(company_id,user_id,endpoint,keys) values(company,auth.uid(),endpoint,k)
 on conflict(endpoint) do update set company_id=excluded.company_id,user_id=excluded.user_id,keys=excluded.keys,disabled=false,updated_at=clock_timestamp();
end $$;
create function public.quote_push_subscribe(p_subscription jsonb) returns void language sql security invoker set search_path='' as $$ select quote_private.push_subscribe(p_subscription) $$;
create function quote_private.push_unsubscribe(p_endpoint text) returns void language plpgsql security definer set search_path='' as $$
begin
 if quote_private.staff_company() is null then raise exception 'Nincs jogosultság.'; end if;
 update public.quote_push_subscriptions set disabled=true where endpoint=p_endpoint and user_id=auth.uid();
end $$;
create function public.quote_push_unsubscribe(p_endpoint text) returns void language sql security invoker set search_path='' as $$ select quote_private.push_unsubscribe(p_endpoint) $$;
revoke all on function quote_private.appointment_event_seen(uuid),quote_private.push_subscribe(jsonb),quote_private.push_unsubscribe(text),quote_private.notification_public_key(),public.quote_appointment_event_seen(uuid),public.quote_push_subscribe(jsonb),public.quote_push_unsubscribe(text),public.quote_notification_public_key() from public,anon,authenticated;
grant execute on function quote_private.appointment_event_seen(uuid),quote_private.push_subscribe(jsonb),quote_private.push_unsubscribe(text),quote_private.notification_public_key(),public.quote_appointment_event_seen(uuid),public.quote_push_subscribe(jsonb),public.quote_push_unsubscribe(text),public.quote_notification_public_key() to authenticated;

-- Service-only worker APIs, never exposed to staff or the public customer.
create function public.quote_notification_worker_auth(p_secret text) returns boolean language sql security definer set search_path='' as $$
 select length(coalesce(p_secret,''))=64 and p_secret=(select decrypted_secret from vault.decrypted_secrets where name='quote_notification_scheduler_key')
$$;
create function public.quote_notification_worker_keys(p_public text,p_private text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('quote-notification-keys',0));
 if not exists(select 1 from vault.secrets where name='quote_push_public_key') then
  perform vault.create_secret(p_public,'quote_push_public_key');
  perform vault.create_secret(p_private,'quote_push_private_key');
 end if;
 return jsonb_build_object('publicKey',(select decrypted_secret from vault.decrypted_secrets where name='quote_push_public_key'),
 'privateKey',(select decrypted_secret from vault.decrypted_secrets where name='quote_push_private_key'));
end $$;
create function public.quote_notification_claim() returns setof public.quote_appointment_events language sql security definer set search_path='' as $$
 update public.quote_appointment_events set lease_until=now()+interval '2 minutes'
 where id in (select id from public.quote_appointment_events where not cancelled and due_at<=now() and expires_at>now() and next_attempt_at<=now()
  and (lease_until is null or lease_until<now()) and ((kind='booked' and email_sent_at is null) or push_done_at is null) order by due_at limit 10 for update skip locked)
 returning *
$$;
create function public.quote_push_delivery_done(p_event uuid,p_subscription uuid) returns boolean language sql security definer set search_path='' as $$
 select exists(select 1 from quote_private.quote_push_deliveries where event_id=p_event and subscription_id=p_subscription)
$$;
create function public.quote_push_delivery_mark(p_event uuid,p_subscription uuid) returns void language sql security definer set search_path='' as $$
 insert into quote_private.quote_push_deliveries(event_id,subscription_id) values(p_event,p_subscription) on conflict do nothing
$$;
revoke all on function public.quote_notification_worker_auth(text),public.quote_notification_worker_keys(text,text),public.quote_notification_claim(),public.quote_push_delivery_done(uuid,uuid),public.quote_push_delivery_mark(uuid,uuid) from public,anon,authenticated;
grant execute on function public.quote_notification_worker_auth(text),public.quote_notification_worker_keys(text,text),public.quote_notification_claim(),public.quote_push_delivery_done(uuid,uuid),public.quote_push_delivery_mark(uuid,uuid) to service_role;
