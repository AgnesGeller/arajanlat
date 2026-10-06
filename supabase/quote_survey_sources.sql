-- Árajánlat-only: structured surveys and internal attachment packages.
create table public.quote_survey_entries (
 id uuid primary key default gen_random_uuid(), project_id uuid not null references public.quote_projects(id) on delete cascade,
 kind text not null check(kind in ('measurement','area','plant','work','note')),
 name text not null check(length(trim(name)) between 1 and 300),
 quantity numeric(14,3) check(quantity>=0), unit text,
 quantity2 numeric(14,3) check(quantity2>=0), unit2 text, note text,
 measured_at timestamptz not null default now(), archived boolean not null default false,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index quote_survey_project_idx on public.quote_survey_entries(project_id,measured_at);
create trigger quote_survey_touch before update on public.quote_survey_entries for each row execute function quote_private.touch_updated_at();
alter table public.quote_survey_entries enable row level security;
create policy quote_survey_staff on public.quote_survey_entries to authenticated
 using ((select quote_private.is_staff()) and exists(select 1 from public.quote_projects p join public.quote_clients c on c.id=p.client_id where p.id=quote_survey_entries.project_id and c.company_id=(select quote_private.staff_company())))
 with check ((select quote_private.is_staff()) and exists(select 1 from public.quote_projects p join public.quote_clients c on c.id=p.client_id where p.id=quote_survey_entries.project_id and c.company_id=(select quote_private.staff_company())));
revoke all on public.quote_survey_entries from anon;
grant select,insert,update on public.quote_survey_entries to authenticated;

create table public.quote_source_packages (
 id uuid primary key default gen_random_uuid(), source_key text not null unique, name text not null,
 source_file text not null, source_sha256 text not null, payload jsonb not null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.quote_source_packages enable row level security;
create policy quote_source_staff on public.quote_source_packages for select to authenticated using((select quote_private.is_staff()));
revoke all on public.quote_source_packages from anon,authenticated;
grant select on public.quote_source_packages to authenticated;

create function public.quote_source_package_apply(p_quote uuid,p_source uuid,p_name text)
returns uuid language plpgsql security invoker set search_path='' as $$
declare pack public.quote_source_packages%rowtype; version_id uuid; row jsonb; pos integer:=0; q numeric; material numeric; labor numeric; vat numeric;
begin
 if not quote_private.is_staff() then raise exception 'Árajánlat-hozzáférés szükséges' using errcode='42501'; end if;
 if not exists(select 1 from public.quote_quotes where id=p_quote) then raise exception 'Az ajánlat nem elérhető'; end if;
 select * into strict pack from public.quote_source_packages where id=p_source;
 if nullif(trim(p_name),'') is null or length(p_name)>200 then raise exception 'Adja meg a változat nevét'; end if;
 insert into public.quote_versions(quote_id,name) values(p_quote,trim(p_name)) returning id into version_id;
 for row in select value from jsonb_array_elements(pack.payload->'quote_lines') loop
  pos:=pos+1;
  q:=(row->>'quantity')::numeric;
  material:=case when pack.payload->>'type'='irrigation' then 1 else coalesce((row->>'material_net')::numeric,0) end;
  labor:=case when pack.payload->>'type'='irrigation' then 0 else coalesce((row->>'labor_net')::numeric,0) end;
  vat:=case when pack.payload->>'type'='irrigation' then 0 else 0.27 end;
  insert into public.quote_items(version_id,position,category,subcategory,name,description,quantity1,unit1,material_unit,labor_unit,vat_rate,pricing_required,internal_note)
  values(version_id,pos,pack.name,pack.source_key,row->>'name',row->>'note',q,row->>'unit',material,labor,vat,true,
   pack.source_file||' – '||pack.name||E'\n'||row::text||case when pack.payload->>'type'='irrigation' then E'\nBelső költségbontás; az eladási ár külön ellenőrizendő.' else E'\nA PDF eredeti nettó/bruttó összegei és a kerekítés ellenőrizendők.' end);
 end loop;
 return version_id;
end $$;
revoke all on function public.quote_source_package_apply(uuid,uuid,text) from public,anon;
grant execute on function public.quote_source_package_apply(uuid,uuid,text) to authenticated;
notify pgrst,'reload schema';
