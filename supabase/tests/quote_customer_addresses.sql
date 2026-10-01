begin;
do $test$
declare company uuid;actor uuid;a public.quote_clients;b public.quote_clients;result text;
begin
select s.company_id,s.user_id into company,actor from public.quote_staff s join auth.users u on u.id=s.user_id where u.email='agi@arajanlat.diszkertek.hu';
perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
result=quote_private.merge_customer_addresses(E'Budapest, Fő utca 1.\nBudaörs, Kert utca 2.',E'BUDAPEST,  Fő utca 1.\nÉrd, Park utca 3.');
if cardinality(string_to_array(result,E'\n'))<>3 then raise exception 'Address union lost or duplicated address';end if;
insert into public.quote_clients(company_id,name,project_address,shared_sync_enabled) values(company,'Címteszt saját',E'Budapest, Fő utca 1.\nÉrd, Park utca 3.',false) returning * into a;
insert into public.quote_clients(company_id,name,project_address,source_customer_id) values(company,'Címteszt közös',E'Budapest, Fő utca 1.\nBudaörs, Kert utca 2.',gen_random_uuid()) returning * into b;
perform public.quote_customer_link(a.id,b.id);
select * into b from public.quote_clients where id=b.id;
if cardinality(string_to_array(b.project_address,E'\n'))<>3 then raise exception 'Link discarded address';end if;
if not exists(select 1 from public.quote_clients where id=a.id and merged_into=b.id and project_address=a.project_address) then raise exception 'Original entry lost';end if;
update public.quote_clients set sync_conflicts=jsonb_build_object('project_address',jsonb_build_object('local',b.project_address,'source','Szentendre, Duna utca 4.')) where id=b.id;
perform public.quote_customer_resolve(b.id,'{"project_address":"both"}');
select * into b from public.quote_clients where id=b.id;
if cardinality(string_to_array(b.project_address,E'\n'))<>4 or b.sync_conflicts<>'{}'::jsonb then raise exception 'Resolve discarded address';end if;
end $test$;
select 'PASS: multi-address union, linking, original preservation and conflict resolution' result;
rollback;
