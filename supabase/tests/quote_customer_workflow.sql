begin;
select set_config('request.jwt.claim.sub','ce8338e5-b1d3-4010-aaca-c24215e08f00',true);
do $$
declare company uuid:=quote_private.staff_company();a public.quote_clients;b public.quote_clients;other public.quote_clients;project uuid;token text;test_status text;result jsonb;
begin
 insert into public.quote_clients(company_id,name,project_address,source_customer_id) values(company,'Rollback névazonosság','Budapest, Fő utca 1.',gen_random_uuid()) returning * into b;
 a:=public.quote_clients_upsert(null,'Rollback névazonosság',null,null,null,null,'Számlázási cím','Budapest,  Fő utca 1.',null,false,null);
 if not a.shared_sync_enabled then raise exception 'Automatic sharing missing';end if;
 insert into public.quote_projects(client_id,name,status) values(a.id,'Rollback átvitt projekt','Árajánlat készül') returning id into project;
 other:=public.quote_clients_upsert(null,'Rollback névazonosság',null,null,null,null,null,'Érd, Másik utca 2.',null,true,null);
 perform public.quote_customers_merge_duplicates();
 if not exists(select 1 from public.quote_clients where id=a.id and merged_into=b.id and billing_address='Számlázási cím') then raise exception 'Original was not preserved';end if;
 if not exists(select 1 from public.quote_projects where id=project and client_id=b.id) then raise exception 'Project lost';end if;
 if not exists(select 1 from public.quote_clients where id=other.id and merged_into is null) then raise exception 'Distinct address merged';end if;
 if not exists(select 1 from public.quote_customer_history where client_id=a.id) then raise exception 'History missing';end if;
 for test_status in select unnest(array['Új érdeklődés','Adatbekérő kiküldve','Ügyfél kitöltötte','Felmérés szükséges','Felmérve','Árajánlat készül','Árajánlat elküldve','Módosítás alatt','Elfogadva','Elutasítva','Lezárva']) loop
  update public.quote_projects set status=test_status where id=project;
  token:=public.quote_request_link_create(project);
  if public.quote_public_read(token,'name','R o l l b a c k') is not null then raise exception 'Wrong identity accepted';end if;
  if public.quote_public_read(token,'name',b.name) is null then raise exception 'Request unavailable in status %',test_status;end if;
  result:=public.quote_public_request_submit(token,'name',b.name,'{"description":"További adatok"}');
  if result->>'saved'<>'true' then raise exception 'Request not saved';end if;
  if test_status not in('Új érdeklődés','Adatbekérő kiküldve','Ügyfél kitöltötte') and not exists(select 1 from public.quote_projects p where p.id=project and p.status=test_status) then raise exception 'Project status regressed';end if;
  if public.quote_public_request_submit(token,'name',b.name,'{}') is not null then raise exception 'Token replay allowed';end if;
 end loop;
 if has_function_privilege('anon','public.quote_request_link_create(uuid)','execute') or has_function_privilege('anon','public.quote_customers_merge_duplicates()','execute') then raise exception 'Anonymous staff RPC access';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000000',true);
do $$ begin
 begin perform public.quote_customers_merge_duplicates();raise exception 'Unauthorized merge';exception when insufficient_privilege then null;end;
 begin perform public.quote_request_link_create(gen_random_uuid());raise exception 'Unauthorized request link';exception when insufficient_privilege then null;end;
end $$;
select 'PASS: automatic sharing, exact duplicate merge, retained projects/history, distinct addresses, requests at all stages, replay and access guards' result;
rollback;
