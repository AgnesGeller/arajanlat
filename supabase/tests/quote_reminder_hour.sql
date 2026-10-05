begin;
do $$
declare actor uuid;company uuid;customer uuid;project uuid;slot uuid;appointment uuid;
begin
 select s.user_id,s.company_id into actor,company from public.quote_staff s join auth.users u on u.id=s.user_id where u.email='agi@arajanlat.diszkertek.hu';
 perform set_config('request.jwt.claim.sub',actor::text,true);
 select id into customer from public.quote_clients where company_id=company and merged_into is null limit 1;
 insert into public.quote_projects(client_id,name,meeting_required) values(customer,'Rollback egyórás emlékeztető',true) returning id into project;
 slot:=public.quote_appointment_slot_save(null,now()+interval '90 minutes',now()+interval '120 minutes',false,null);
 appointment:=(public.quote_appointment_book(project,slot)->>'id')::uuid;
 if not exists(select 1 from public.quote_appointment_events where appointment_id=appointment and kind='reminder' and due_at=now()+interval '30 minutes') then raise exception '90-minute booking must have one-hour reminder';end if;
 insert into public.quote_projects(client_id,name,meeting_required) values(customer,'Rollback rövid határidejű foglalás',true) returning id into project;
 slot:=public.quote_appointment_slot_save(null,now()+interval '30 minutes',now()+interval '60 minutes',false,null);
 appointment:=(public.quote_appointment_book(project,slot)->>'id')::uuid;
 if exists(select 1 from public.quote_appointment_events where appointment_id=appointment and kind='reminder') then raise exception 'Retroactive reminder created';end if;
 if not exists(select 1 from public.quote_appointment_events where appointment_id=appointment and kind='booked') then raise exception 'Immediate booking notification missing';end if;
end $$;
select 'PASS: reminder exactly one hour before, 90-minute booking scheduled, late booking receives immediate notification only' result;
rollback;
