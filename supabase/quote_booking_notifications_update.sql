-- Kizárólag Árajánlat-értesítések; más alkalmazás és ütemezés változatlan.
begin;
create or replace function quote_private.appointment_event_queue() returns trigger language plpgsql security definer set search_path='' as $$
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
create or replace function public.quote_notification_claim() returns setof public.quote_appointment_events language sql security definer set search_path='' as $$
 update public.quote_appointment_events set lease_until=now()+interval '2 minutes'
 where id in (select id from public.quote_appointment_events where not cancelled and due_at<=now() and expires_at>now() and next_attempt_at<=now()
  and (lease_until is null or lease_until<now()) and ((kind='booked' and email_sent_at is null) or push_done_at is null) order by due_at limit 10 for update skip locked)
 returning *
$$;
-- A már sorban álló, még el nem küldött emlékeztetők is kétórásak lesznek.
update public.quote_appointment_events e
 set due_at=s.starts_at-interval '2 hours',next_attempt_at=least(e.next_attempt_at,now())
 from public.quote_appointments a join public.quote_appointment_slots s on s.id=a.slot_id
 where e.appointment_id=a.id and e.kind='reminder' and not e.cancelled
 and e.push_done_at is null and a.status='booked' and s.starts_at>now();
notify pgrst,'reload schema';
commit;
