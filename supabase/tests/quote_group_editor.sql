-- Run after quote_group_editor.sql. Every fixture is rolled back.
begin;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select user_id from public.quote_staff limit 1),'role','authenticated')::text,true);
set local role authenticated;
do $$
declare t jsonb; d jsonb; q uuid; v uuid; project uuid; group_id uuid:=gen_random_uuid(); n text:='Ellenőrzés – '||gen_random_uuid()::text; payload jsonb;
begin
 t:=public.quote_template_save(null,n,jsonb_build_array(jsonb_build_object('catalog_id',(select id from public.quote_price_catalog where active limit 1))));
 if (select count(*) from public.quote_template_items where template_id=(t->>'id')::uuid)<>1 then raise exception 'Sablon mentési hiba';end if;
 begin
  perform public.quote_template_save((t->>'id')::uuid,n||' hibás','[{"catalog_id":"00000000-0000-0000-0000-000000000000"}]');
  raise exception 'Nem létező árlistatételt elfogadott';
 exception when others then if sqlerrm='Nem létező árlistatételt elfogadott' then raise;end if;end;
 if (select name from public.quote_templates where id=(t->>'id')::uuid)<>n or (select count(*) from public.quote_template_items where template_id=(t->>'id')::uuid)<>1 then raise exception 'A hibás sablonmentés nem atomikus';end if;
 select p.id into project from public.quote_projects p join public.quote_clients c on c.id=p.client_id where c.name ilike '%geller%' or c.name ilike '%teszt%' limit 1;
 if project is null then raise exception 'Hiányzik a jóváhagyott tesztprojekt';end if;
 insert into public.quote_quotes(project_id,number,title) values(project,'TESZT-GROUP-'||gen_random_uuid()::text,'Főtételek elkülönített ellenőrzése') returning id into q;
 insert into public.quote_versions(quote_id,name) values(q,'Ellenőrzés') returning id into v;
 insert into public.quote_items(version_id,position,name,quantity1,unit1,material_unit,labor_unit,vat_rate) values(v,1,'Geotextília',20,'m²',700,700,0);
 d:=public.quote_group_editor(q);
 if d->>'promoted_quote_id'<>q::text or (d->'payload'->'items'->0->>'quantity1')::numeric<>20 then raise exception 'Teljes ajánlat megnyitási hiba';end if;
 if public.quote_group_editor(q)->>'id'<>d->>'id' then raise exception 'A szerkesztő megnyitása megkettőzte az ajánlatot';end if;
 payload:=jsonb_set(d->'payload','{groups}',jsonb_build_array(jsonb_build_object('id',group_id,'name','Ágyás 3','length',12,'width',2)));
 payload:=jsonb_set(payload,'{items,0}',(payload->'items'->0)||jsonb_build_object('group_id',group_id,'main_item','Ágyás 3','quantity1',24,'measurement',jsonb_build_object('mode','area','length',12,'width',2,'use_group',true)));
 d:=public.quote_quick_save((d->>'id')::uuid,payload,(d->>'revision')::integer);
 if d->'payload'->'items'->0->>'group_id'<>group_id::text or d->'payload'->'items'->0->'measurement'->>'use_group'<>'true' then raise exception 'A főtételes mérési adatok elvesztek';end if;
 if (select quantity1 from public.quote_items where version_id=v)<>24 then raise exception 'A gyors/teljes ajánlat szinkronja hibás';end if;
end $$;
select set_config('request.jwt.claims','{}',true);
do $$ begin
 begin perform public.quote_template_save(null,'Tiltott','[]');raise exception 'Jogosulatlan sablonmentés engedélyezve';exception when others then if sqlerrm='Jogosulatlan sablonmentés engedélyezve' then raise;end if;end;
 begin perform public.quote_group_editor(gen_random_uuid());raise exception 'Jogosulatlan ajánlatnyitás engedélyezve';exception when others then if sqlerrm='Jogosulatlan ajánlatnyitás engedélyezve' then raise;end if;end;
end $$;
select 'Munkasablonok, főtételes mérési adatok, gyors/teljes szinkron és jogosultságok: sikeres. Minden próbaadat visszagörgetve.' as eredmeny;
rollback;
