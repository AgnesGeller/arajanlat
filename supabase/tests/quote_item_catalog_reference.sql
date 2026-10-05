begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','ce8338e5-b1d3-4010-aaca-c24215e08f00',true);
do $$
declare project_id uuid; quote_id uuid; version_id uuid; v_catalog_id uuid; item_id uuid;
begin
 select id into project_id from public.quote_projects limit 1;
 if project_id is null then raise exception 'A test needs an accessible project'; end if;
 select id into v_catalog_id from public.quote_price_catalog where source='Kalkulátor' and source_row=3;
 insert into public.quote_quotes(project_id,number) values(project_id,'TEST-CATALOG-'||gen_random_uuid()) returning id into quote_id;
 insert into public.quote_versions(quote_id) values(quote_id) returning id into version_id;
 insert into public.quote_items(version_id,catalog_id,name,quantity1,material_unit,labor_unit)
 values(version_id,v_catalog_id,'Rollback catalogue test',2,2200,2800) returning id into item_id;
 if not exists(select 1 from public.quote_items i where i.id=item_id and i.catalog_id=v_catalog_id) then
  raise exception 'Catalogue reference was not persisted';
 end if;
 begin
  update public.quote_items set catalog_id=gen_random_uuid() where id=item_id;
  raise exception 'Unknown catalogue reference was accepted';
 exception when foreign_key_violation then null;
 end;
end $$;
rollback;
