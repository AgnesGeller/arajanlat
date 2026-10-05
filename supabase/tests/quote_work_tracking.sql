-- A migrációval együtt, ugyanabban a tranzakcióban futtatandó; a végén ROLLBACK.
do $$
declare p uuid; c uuid; g uuid;
begin
 select q.id,cl.company_id into p,c from public.quote_projects q join public.quote_clients cl on cl.id=q.client_id
 where cl.name='Teszt' order by q.created_at limit 1;
 if p is null then raise exception 'Hiányzik a Teszt projekt.'; end if;
 update public.quote_projects set started_on='2026-10-05' where id=p;
 perform set_config('quote.test_project',p::text,true);
 perform set_config('quote.test_company',c::text,true);
 select q.id into g from public.quote_projects q join public.quote_clients cl on cl.id=q.client_id
 where cl.name='Geller Ágnes' and cl.company_id=c order by q.created_at limit 1;
 if g is null then raise exception 'Hiányzik a Geller Ágnes projekt.'; end if;
 update public.quote_projects set started_on='2026-10-05' where id=g;
 perform set_config('quote.test_geller',g::text,true);
end $$;
set local role service_role;
select public.quote_work_records_sync(current_setting('quote.test_company')::uuid,
 jsonb_build_array(jsonb_build_object('source_id','00000000-0000-4000-8000-000000000123',
 'project_id',current_setting('quote.test_project'),'work_date','2026-10-05',
 'source_updated_at','2026-10-05T10:00:00Z','form_data','{"team_1_size":"2"}'::jsonb,
 'calculation','{"person_hours":14,"labor":119000}'::jsonb)),now()-interval '10 seconds');
select public.quote_work_records_sync(current_setting('quote.test_company')::uuid,
 jsonb_build_array(jsonb_build_object('source_id','00000000-0000-4000-8000-000000000123',
 'project_id',current_setting('quote.test_project'),'work_date','2026-10-05',
 'source_updated_at','2026-10-05T11:00:00Z','form_data','{"team_1_size":"3"}'::jsonb,
 'calculation','{"person_hours":21,"labor":178500}'::jsonb)),now()-interval '5 seconds');
do $$ begin
 if (select count(*) from public.quote_work_records where active and source_id='00000000-0000-4000-8000-000000000123')<>1 then raise exception 'Kettős elszámolás.'; end if;
 if (select calculation->>'labor' from public.quote_work_records where active and source_id='00000000-0000-4000-8000-000000000123')<>'178500' then raise exception 'Javítás nem cserélte az eredményt.'; end if;
end $$;
-- Egy régebbi párhuzamos lekérés nem tüntetheti el az új eredményt.
select public.quote_work_records_sync(current_setting('quote.test_company')::uuid,'[]'::jsonb,now()-interval '20 seconds');
do $$ begin
 if (select count(*) from public.quote_work_records where active and source_id='00000000-0000-4000-8000-000000000123')<>1 then raise exception 'Elavult lekérés felülírt.'; end if;
end $$;
reset role;
do $$ declare q uuid; v uuid; i uuid; begin
 insert into public.quote_quotes(project_id,number) values(current_setting('quote.test_project')::uuid,'ROLLBACK-WORK-'||gen_random_uuid()) returning id into q;
 insert into public.quote_versions(quote_id) values(q) returning id into v;
 insert into public.quote_items(version_id,name,quantity1,unit1,labor_unit) values(v,'Geotextília',20,'m2',800) returning id into i;
 update public.quote_versions set status='accepted' where id=v;
 perform set_config('quote.test_version',v::text,true);perform set_config('quote.test_item',i::text,true);
end $$;
select set_config('request.jwt.claim.sub',(select user_id::text from public.quote_staff where company_id=current_setting('quote.test_company')::uuid limit 1),true);
set local role authenticated;
do $$ begin
 if (select count(*) from public.quote_work_records where source_id='00000000-0000-4000-8000-000000000123')<>1 then raise exception 'Staff nem látja a saját elszámolást.'; end if;
 perform public.quote_project_work_summary(current_setting('quote.test_project')::uuid);
 perform public.quote_project_work_summary(current_setting('quote.test_geller')::uuid);
 insert into public.quote_work_progress(item_id,project_id,version_id,source_code,override_completed)
 values(current_setting('quote.test_item')::uuid,current_setting('quote.test_project')::uuid,current_setting('quote.test_version')::uuid,'maintenance_18',10);
 update public.quote_work_progress set override_completed=0 where item_id=current_setting('quote.test_item')::uuid;
 if (select override_completed from public.quote_work_progress where item_id=current_setting('quote.test_item')::uuid)<>0 then raise exception 'Nulla készültség nem menthető.'; end if;
 begin
  update public.quote_work_progress set source_code='construction_3' where item_id=current_setting('quote.test_item')::uuid;
  raise exception 'Eltérő mértékegység összerendelhető.';
 exception when insufficient_privilege then null; end;
 begin
  update public.quote_work_progress set project_id=current_setting('quote.test_geller')::uuid where item_id=current_setting('quote.test_item')::uuid;
  raise exception 'Tétel másik projekthez rendelhető.';
 exception when insufficient_privilege then null; end;
 update public.quote_work_progress set override_completed=null where item_id=current_setting('quote.test_item')::uuid;

 begin
  delete from public.quote_work_records where source_id='00000000-0000-4000-8000-000000000123';
  raise exception 'A frontend törölhetett munkalapot.';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000999',true);
set local role authenticated;
do $$ begin
 if (select count(*) from public.quote_work_progress where item_id=current_setting('quote.test_item')::uuid)<>0 then raise exception 'Idegen fiók készültséget lát.'; end if;
 if (select count(*) from public.quote_work_records where source_id='00000000-0000-4000-8000-000000000123')<>0 then raise exception 'Idegen fiók elszámolást lát.'; end if;
end $$;
reset role;
set local role anon;
do $$ begin
 begin
  perform 1 from public.quote_work_records;
  raise exception 'Anon olvashatott elszámolást.';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
