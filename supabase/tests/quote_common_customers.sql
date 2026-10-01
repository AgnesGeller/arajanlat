-- Transactional integration checks: no fixture survives, no source project writes.
begin;
do $test$
declare company uuid;actor uuid;c public.quote_clients;r jsonb;m jsonb;source_id uuid=gen_random_uuid();
 lease_a uuid=gen_random_uuid();lease_b uuid=gen_random_uuid();stale boolean=false;
begin
 select s.company_id,s.user_id into company,actor from public.quote_staff s
 join auth.users u on u.id=s.user_id where u.email='agi@arajanlat.diszkertek.hu';
 if company is null then raise exception 'Missing quote test account';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);

 m=quote_private.merge_customer_fields('{"email":"new@example.invalid","phone":"+36301234567"}',
  '{"email":"old@example.invalid","phone":"+36301234567"}',
  '{"email":"old@example.invalid","phone":"+36201234567"}');
 if m#>>'{fields,email}'<>'new@example.invalid' or m#>>'{fields,phone}'<>'+36201234567'
  or m->'conflicts'<>'{}'::jsonb then raise exception 'Disjoint edit lost';end if;
 m=quote_private.merge_customer_fields('{"phone":"local"}','{"phone":"base"}','{"phone":"remote"}');
 if not (m->'conflicts' ? 'phone') then raise exception 'Concurrent edit not flagged';end if;
 m=quote_private.merge_customer_fields(m->'fields',m->'base','{"phone":"remote"}',m->'conflicts');
 if not (m->'conflicts' ? 'phone') then raise exception 'Conflict silently cleared';end if;
 if not quote_private.customer_value_equal('phone','"06 30 123 4567"','"+36 30 123 4567"') then raise exception 'Phone format mismatch';end if;
 if not quote_private.customer_value_equal('email','"Test@example.invalid"','"test@example.invalid"') then raise exception 'Email case mismatch';end if;
 if not quote_private.customer_value_equal('project_address','"Budapest,   Fő utca 1."','"BUDAPEST, Fő utca 1."') then raise exception 'Address format mismatch';end if;

 r=jsonb_build_object('id',source_id,'full_name','Ellenőrzés – közös ügyfél','active',true,'review_status','approved',
  'details',jsonb_build_object('phone','+36301234567','email','old@example.invalid'),'locations','[]'::jsonb);
 perform public.quote_customers_reconcile(company,jsonb_build_array(r));
 select * into c from public.quote_clients where company_id=company and source_customer_id=source_id;
 if c.phone<>'+36301234567' or c.email<>'old@example.invalid' then raise exception 'Incoming data not copied';end if;
 if exists(select 1 from public.quote_customer_sync where client_id=c.id and synced_at is null) then raise exception 'Clean source queued';end if;
 c=public.quote_clients_upsert(c.id,c.name,c.client_type,c.contact_name,'+36201234567',c.email,c.billing_address,c.project_address,c.notes,true,c.sync_revision);
 if not exists(select 1 from public.quote_customer_sync where client_id=c.id and synced_at is null) then raise exception 'Local edit not queued';end if;
 begin
  perform public.quote_clients_upsert(c.id,c.name,c.client_type,c.contact_name,c.phone,c.email,c.billing_address,c.project_address,c.notes,true,c.sync_revision-1);
 exception when serialization_failure then stale=true;end;
 if not stale then raise exception 'Stale edit accepted';end if;
 r=jsonb_set(r,'{details,email}','"remote@example.invalid"');
 perform public.quote_customers_reconcile(company,jsonb_build_array(r));
 select * into c from public.quote_clients where id=c.id;
 if c.phone<>'+36201234567' or c.email<>'remote@example.invalid' or c.sync_conflicts<>'{}'::jsonb then raise exception 'Bidirectional disjoint edit failed';end if;
 r=jsonb_set(r,'{details,phone}','"+36701234567"');
 perform public.quote_customers_reconcile(company,jsonb_build_array(r));
 select * into c from public.quote_clients where id=c.id;
 if c.sync_conflicts<>'{}'::jsonb or c.phone<>'+36701234567' then raise exception 'Current source not authoritative';end if;
 if exists(select 1 from public.quote_customer_sync where client_id=c.id and synced_at is null) then raise exception 'Source priority queued stale edit';end if;
 if not exists(select 1 from public.quote_customer_history where client_id=c.id) then raise exception 'History missing';end if;
 if exists(select 1 from public.clients where id=c.id) then raise exception 'Legacy shared table modified';end if;
 if not public.quote_customer_sync_lease(company,lease_a) then raise exception 'Lease not acquired';end if;
 if public.quote_customer_sync_lease(company,lease_b) then raise exception 'Parallel worker admitted';end if;
 perform public.quote_customer_sync_lease(company,lease_a,true);
 if not public.quote_customer_sync_lease(company,lease_b) then raise exception 'Lease not released';end if;
end $test$;
select 'PASS: bidirectional merge, formatting, source priority, queue, history, stale writes and lease' result;
rollback;
