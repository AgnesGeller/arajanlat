-- Real database checks, all data and number-counter changes rolled back.
begin;
select set_config('request.jwt.claim.sub','ce8338e5-b1d3-4010-aaca-c24215e08f00',true);
do $$
declare company uuid:=quote_private.staff_company(); customer public.quote_clients%rowtype; p1 uuid; p2 uuid; p3 uuid; p4 uuid;
 s1 uuid; s2 uuid; s3 uuid; t1 text:=encode(extensions.gen_random_bytes(32),'hex'); t2 text:=encode(extensions.gen_random_bytes(32),'hex'); t3 text:=encode(extensions.gen_random_bytes(32),'hex'); t4 text:=encode(extensions.gen_random_bytes(32),'hex');
begin
 select * into customer from public.quote_clients where company_id=company and merged_into is null limit 1;
 insert into public.quote_projects(client_id,name,meeting_required) values(customer.id,'Rollback booking 1',true) returning id into p1;
 insert into public.quote_projects(client_id,name,meeting_required) values(customer.id,'Rollback booking 2',true) returning id into p2;
 insert into public.quote_projects(client_id,name,meeting_required) values(customer.id,'Rollback no meeting',false) returning id into p3;
 insert into public.quote_projects(client_id,name,meeting_required) values(customer.id,'Rollback phone',true) returning id into p4;
 s1:=public.quote_appointment_slot_save(null,now()+interval '14 days',now()+interval '14 days 1 hour',false,null);
 s2:=public.quote_appointment_slot_save(null,now()+interval '14 days 30 minutes',now()+interval '14 days 90 minutes',false,null);
 s3:=public.quote_appointment_slot_save(null,now()+interval '15 days',now()+interval '15 days 1 hour',false,null);
 insert into public.quote_public_tokens(project_id,purpose,token_hash,expires_at) values
 (p1,'request',encode(extensions.digest(t1,'sha256'),'hex'),now()+interval '1 day'),
 (p2,'request',encode(extensions.digest(t2,'sha256'),'hex'),now()+interval '1 day'),
 (p3,'request',encode(extensions.digest(t3,'sha256'),'hex'),now()+interval '1 day'),
 (p4,'request',encode(extensions.digest(t4,'sha256'),'hex'),now()+interval '1 day');
 perform set_config('quote.test',jsonb_build_object('p1',p1,'p2',p2,'p3',p3,'p4',p4,'s1',s1,'s2',s2,'s3',s3,'t1',t1,'t2',t2,'t3',t3,'t4',t4,'identity',customer.name)::text,true);
end $$;
set local role anon;
do $$
declare c jsonb:=current_setting('quote.test')::jsonb; result jsonb;
begin
 if public.quote_public_read(c->>'t1','name','unknown identity') is not null then raise exception 'Wrong identity passed'; end if;
 if public.quote_public_request_submit(c->>'t1','name','unknown identity','{}') is not null then raise exception 'Wrong identity submitted'; end if;
 if public.quote_public_read('bad token','name',c->>'identity') is not null then raise exception 'Bad token passed'; end if;
 result:=public.quote_public_read(c->>'t1','name',c->>'identity');
 if result->>'meeting_required'<>'true' or jsonb_array_length(result->'slots')<3 then raise exception 'Slots were not shown'; end if;
 begin
  perform public.quote_public_request_submit(c->>'t1','name',c->>'identity','{}');raise exception 'Missing choice accepted';
 exception when raise_exception then if sqlerrm='Missing choice accepted' then raise; end if;end;
 result:=public.quote_public_request_submit(c->>'t1','name',c->>'identity',jsonb_build_object('meeting_choice',c->>'s1','appointment',jsonb_build_object('starts_at','2000-01-01')));
 if result->>'saved'<>'true' or (result->'appointment'->>'starts_at')::timestamptz<now() then raise exception 'Canonical booking invalid'; end if;
 if public.quote_public_request_submit(c->>'t1','name',c->>'identity','{}') is not null then raise exception 'Token reused'; end if;
 if public.quote_public_read(c->>'t1','name',c->>'identity') is not null then raise exception 'Revoked token read'; end if;
 result:=public.quote_public_read(c->>'t2','name',c->>'identity');
 if exists(select 1 from jsonb_array_elements(result->'slots') slot where slot->>'id' in(c->>'s1',c->>'s2')) then raise exception 'Booked/overlapping slot exposed'; end if;
 begin
  perform public.quote_public_request_submit(c->>'t2','name',c->>'identity',jsonb_build_object('meeting_choice',c->>'s2'));raise exception 'Overlap accepted';
 exception when raise_exception then if sqlerrm='Overlap accepted' then raise; end if;end;
 if public.quote_public_read(c->>'t2','name',c->>'identity') is null then raise exception 'Failed booking consumed token'; end if;
 result:=public.quote_public_request_submit(c->>'t4','name',c->>'identity','{"meeting_choice":"phone"}');
 if result->>'phone_requested'<>'true' then raise exception 'Phone fallback failed'; end if;
 result:=public.quote_public_request_submit(c->>'t3','name',c->>'identity',jsonb_build_object('meeting_choice',c->>'s3'));
 if result->'appointment'<>'null'::jsonb then raise exception 'No-meeting project booked'; end if;
 if has_table_privilege('anon','public.quote_appointments','SELECT') or has_table_privilege('authenticated','public.quote_appointments','INSERT') or has_function_privilege('anon','public.quote_appointment_change(uuid,uuid,timestamptz)','EXECUTE') or has_function_privilege('authenticated','public.quote_notification_worker_keys(text,text)','EXECUTE') then raise exception 'Excess permissions'; end if;
end $$;
reset role;
do $$
declare c jsonb:=current_setting('quote.test')::jsonb; a public.quote_appointments%rowtype; s public.quote_appointment_slots%rowtype; result jsonb;
begin
 select * into a from public.quote_appointments where project_id=(c->>'p1')::uuid and status='booked';
 if (select count(*) from public.quote_appointment_events where appointment_id=a.id)<>2 then raise exception 'Booking/reminder not queued'; end if;
 if not exists(select 1 from public.quote_appointment_events e join public.quote_appointment_slots slot on slot.id=a.slot_id where e.appointment_id=a.id and kind='reminder' and e.due_at=slot.starts_at-interval '2 hours') then raise exception 'Reminder offset wrong'; end if;
 select * into s from public.quote_appointment_slots where id=a.slot_id;
 begin
  perform public.quote_appointment_slot_save(s.id,s.starts_at+interval '1 hour',s.ends_at+interval '1 hour',false,s.updated_at);raise exception 'Booked slot edited';
 exception when raise_exception then if sqlerrm='Booked slot edited' then raise; end if;end;
 begin
  perform public.quote_appointment_change(a.id,(c->>'s3')::uuid,a.updated_at-interval '1 second');raise exception 'Stale update accepted';
 exception when raise_exception then if sqlerrm='Stale update accepted' then raise; end if;end;
 result:=public.quote_appointment_change(a.id,(c->>'s3')::uuid,a.updated_at);
 if result->>'id' is null then raise exception 'Rescheduling failed'; end if;
 if exists(select 1 from public.quote_appointment_events where appointment_id=a.id and kind='reminder' and not cancelled) then raise exception 'Old reminder survives'; end if;
 select * into a from public.quote_appointments where id=(result->>'id')::uuid;
 perform public.quote_appointment_change(a.id,null,a.updated_at);
 if exists(select 1 from public.quote_appointments where project_id=(c->>'p1')::uuid and status='booked') then raise exception 'Cancellation failed'; end if;
 result:=public.quote_appointment_book((c->>'p2')::uuid,(c->>'s1')::uuid);
 if result->>'id' is null then raise exception 'Staff booking failed'; end if;
 select * into s from public.quote_appointment_slots where id=(c->>'s3')::uuid;
 begin
  perform public.quote_appointment_slot_save(s.id,s.starts_at+interval '1 hour',s.ends_at+interval '1 hour',false,s.updated_at);raise exception 'Booking history changed';
 exception when raise_exception then if sqlerrm='Booking history changed' then raise; end if;end;
end $$;
set local role authenticated;
-- Tamás has the same quotation-only calendar access.
select set_config('request.jwt.claim.sub','8206950c-02c7-4e8d-b4dd-cc0f19956f16',true);
do $$ begin
 if (select count(*) from public.quote_appointment_slots)<3 then raise exception 'Tamás cannot read calendar'; end if;
 if length(public.quote_notification_public_key())<>87 then raise exception 'Push public key missing'; end if;
end $$;
-- An authenticated account without quote_staff has no data or mutations.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000000',true);
do $$ begin
 if exists(select 1 from public.quote_appointments) or exists(select 1 from public.quote_appointment_slots) or exists(select 1 from public.quote_appointment_events) then raise exception 'Unrelated user can read'; end if;
 begin
  perform public.quote_appointment_slot_save(null,now()+interval '1 day',now()+interval '1 day 1 hour',false,null);raise exception 'Unrelated user can write';
 exception when raise_exception then if sqlerrm='Unrelated user can write' then raise; end if;end;
end $$;
rollback;
