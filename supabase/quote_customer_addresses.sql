-- Preserve distinct work addresses when an operator combines customer entries.
create or replace function quote_private.merge_customer_addresses(a text,b text) returns text
language sql immutable set search_path='' as $$
 select coalesce(string_agg(address,E'\n' order by address collate "C"),'') from (
  select distinct on(lower(address)) address from (
   select regexp_replace(btrim(x),'[[:space:]]+',' ','g') address
   from regexp_split_to_table(coalesce(a,'')||E'\n'||coalesce(b,''),E'\n') x
   where btrim(x)<>''
  ) cleaned order by lower(address),address collate "C"
 ) combined
$$;
revoke all on function quote_private.merge_customer_addresses(text,text) from public,anon,authenticated;

create or replace function public.quote_customer_resolve(p_id uuid,p_choices jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare c public.quote_clients;k text;f jsonb;v jsonb;
begin
 select * into c from public.quote_clients where id=p_id and company_id=quote_private.staff_company() for update;
 if not found then raise exception 'Árajánlat-hozzáférés szükséges' using errcode='42501';end if;
 f=quote_private.customer_fields(c);
 for k in select jsonb_object_keys(c.sync_conflicts) loop
  if (p_choices->>k not in('source','local') and not(k='project_address' and p_choices->>k='both')) or p_choices->>k is null then raise exception 'Minden eltérésnél válassz értéket.';end if;
  if p_choices->>k='source' then f=jsonb_set(f,array[k],c.sync_conflicts#>array[k,'source']);end if;
  if k='project_address' and p_choices->>k='both' then
   f=jsonb_set(f,array[k],to_jsonb(quote_private.merge_customer_addresses(c.sync_conflicts#>>array[k,'local'],c.sync_conflicts#>>array[k,'source'])));
  end if;
 end loop;
 update public.quote_clients set name=f->>'name',client_type=f->>'client_type',contact_name=f->>'contact_name',
  email=f->>'email',phone=f->>'phone',tax_number=f->>'tax_number',notes=f->>'notes',project_address=f->>'project_address',
  sync_conflicts='{}'::jsonb where id=c.id;
 insert into public.quote_customer_sync(client_id) values(c.id) on conflict(client_id) do update set synced_at=null,last_error=null;
end $$;
revoke all on function public.quote_customer_resolve(uuid,jsonb) from public,anon;
grant execute on function public.quote_customer_resolve(uuid,jsonb) to authenticated;

-- Explicitly attach a legacy entry to an existing common customer, preserving history.
create or replace function public.quote_customer_link(p_id uuid,p_target uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare a public.quote_clients;b public.quote_clients;company uuid=quote_private.staff_company();
begin
 if company is null or p_id=p_target then raise exception 'Érvénytelen ügyfélkapcsolás' using errcode='42501';end if;
 perform 1 from public.quote_clients where id in(p_id,p_target) order by id for update;
 select * into a from public.quote_clients where id=p_id and company_id=company and merged_into is null;
 if not found or a.source_customer_id is not null then raise exception 'A régi ügyfél nem kapcsolható';end if;
 select * into b from public.quote_clients where id=p_target and company_id=company and source_customer_id is not null and merged_into is null;
 if not found then raise exception 'A közös ügyfél nem található' using errcode='42501';end if;
 update public.quote_clients set
  email=coalesce(nullif(email,''),nullif(a.email,'')),phone=coalesce(nullif(phone,''),nullif(a.phone,'')),
  contact_name=coalesce(nullif(contact_name,''),nullif(a.contact_name,'')),
  billing_address=coalesce(nullif(billing_address,''),nullif(a.billing_address,'')),
  tax_number=coalesce(nullif(tax_number,''),nullif(a.tax_number,'')),
  project_address=quote_private.merge_customer_addresses(project_address,a.project_address),
  notes=coalesce(nullif(notes,''),nullif(a.notes,'')) where id=b.id;
 update public.quote_projects set client_id=b.id where client_id=a.id;
 update public.quote_clients set merged_into=b.id,shared_sync_enabled=false where id=a.id;
 update public.quote_customer_sync set synced_at=now(),last_error=null where client_id=a.id;
 return b.id;
end $$;
revoke all on function public.quote_customer_link(uuid,uuid) from public,anon;
grant execute on function public.quote_customer_link(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
