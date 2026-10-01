begin;
do $test$
declare actor uuid;client uuid;a public.quote_projects;b public.quote_projects;old_code text;blocked boolean=false;first_n bigint;second_n bigint;
begin
 select s.user_id,c.id into actor,client from public.quote_staff s join auth.users u on u.id=s.user_id
 join public.quote_clients c on c.company_id=s.company_id where u.email='agi@arajanlat.diszkertek.hu' and c.merged_into is null limit 1;
 if actor is null then raise exception 'Missing own quote account';end if;
 if has_function_privilege('authenticated','quote_private.next_project_code(integer)','EXECUTE')
 or has_table_privilege('authenticated','quote_private.project_number_counters','SELECT') then raise exception 'Counter exposed';end if;
 insert into quote_private.project_number_counters values(2099,9999);
 if quote_private.next_project_code(2099)<>'PR-2099-10000' then raise exception 'Number truncated';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 execute 'set local role authenticated';
 insert into public.quote_projects(client_id,name) values(client,'Projektazonosító ellenőrzés') returning * into a;
 insert into public.quote_projects(client_id,name,project_code) values(client,'Második ellenőrzés','PR-1900-0001') returning * into b;
 if a.project_code !~ '^PR-[0-9]{4}-[0-9]{4,}$' or b.project_code='PR-1900-0001' then raise exception 'Server numbering failed';end if;
 first_n=split_part(a.project_code,'-',3)::bigint;second_n=split_part(b.project_code,'-',3)::bigint;
 if second_n<>first_n+1 or a.id=b.id then raise exception 'Unique sequential identity failed';end if;
 old_code=a.project_code;
 insert into public.quote_projects(id,client_id,name) values(a.id,client,'Szerkesztett projektnév')
 on conflict(id) do update set name=excluded.name,project_code=excluded.project_code returning * into a;
 if a.project_code<>old_code or a.name<>'Szerkesztett projektnév' then raise exception 'Upsert changed project code';end if;
 begin update public.quote_projects set project_code='PR-1900-0002' where id=a.id;
 exception when check_violation then blocked=true;end;
 if not blocked then raise exception 'Code modification allowed';end if;
 blocked=false;
 begin update public.quote_projects set id=gen_random_uuid() where id=a.id;
 exception when check_violation then blocked=true;end;
 if not blocked then raise exception 'UUID modification allowed';end if;
end $test$;
select 'PASS: authenticated insert/upsert, sequential codes, immutable IDs, counter permissions and 10000 rollover' result;
rollback;
