create or replace function quote_private.appointment_event_queue() returns trigger language plpgsql security definer set search_path='' as $$
declare s public.quote_appointment_slots%rowtype;
begin
 select * into s from public.quote_appointment_slots where id=new.slot_id;
 if tg_op='INSERT' and new.status='booked' then
  insert into public.quote_appointment_events(company_id,project_id,appointment_id,kind,due_at,expires_at)
   values(new.company_id,new.project_id,new.id,'booked',now(),s.starts_at);
  if s.starts_at>now()+interval '1 hour' then
   insert into public.quote_appointment_events(company_id,project_id,appointment_id,kind,due_at,expires_at)
    values(new.company_id,new.project_id,new.id,'reminder',s.starts_at-interval '1 hour',s.starts_at);
  end if;
 elsif tg_op='UPDATE' and old.status='booked' and new.status='cancelled' then
  update public.quote_appointment_events set cancelled=true where appointment_id=new.id and kind in ('booked','reminder');
  insert into public.quote_appointment_events(company_id,project_id,appointment_id,kind,due_at,expires_at)
   values(new.company_id,new.project_id,new.id,'cancelled',now(),now()+interval '1 day');
 end if;
 return new;
end $$;

-- Move any unsent future reminders without repeating delivered notifications.
update public.quote_appointment_events e set due_at=s.starts_at-interval '1 hour'
from public.quote_appointments a join public.quote_appointment_slots s on s.id=a.slot_id
where e.appointment_id=a.id and e.kind='reminder' and not e.cancelled
 and e.email_sent_at is null and e.push_done_at is null and a.status='booked' and s.starts_at>now();
