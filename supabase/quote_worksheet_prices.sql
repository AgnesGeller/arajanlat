-- Munkalap árlista import az Árajánlat saját táblájába.
-- A Munkalap/Kassza adatbázisát és alkalmazását ez a szkript nem módosítja.

alter table public.quote_price_catalog
 add column if not exists comparison_key text,
 add column if not exists price_variant smallint not null default 1,
 add column if not exists pricing_required boolean not null default false,
 add column if not exists calculation_rule jsonb not null default '{"type":"linear"}'::jsonb;

alter table public.quote_items
 add column if not exists calculation_rule jsonb not null default '{"type":"linear"}'::jsonb;

do $$ begin
 if not exists(select 1 from pg_constraint where conname='quote_price_catalog_variant_positive') then
  alter table public.quote_price_catalog add constraint quote_price_catalog_variant_positive check(price_variant>0);
 end if;
 if not exists(select 1 from pg_constraint where conname='quote_price_catalog_rule_object') then
  alter table public.quote_price_catalog add constraint quote_price_catalog_rule_object check(jsonb_typeof(calculation_rule)='object');
 end if;
 if not exists(select 1 from pg_constraint where conname='quote_items_rule_object') then
  alter table public.quote_items add constraint quote_items_rule_object check(jsonb_typeof(calculation_rule)='object');
 end if;
end $$;

update public.quote_price_catalog
set comparison_key=lower(regexp_replace(translate(btrim(subcategory),'ÁÉÍÓÖŐÚÜŰáéíóöőúüű','AEIOOOUUUaeiooouuu'),'[^a-zA-Z0-9]+','','g'))
where comparison_key is null or comparison_key='';

create index if not exists quote_price_catalog_comparison_idx on public.quote_price_catalog(comparison_key,price_variant);

with source_rows(source_row,category,subcategory,description,internal_notes,unit1,unit2,material_unit,labor_unit,pricing_required,rule) as (values
 (1,'Munkalap – munkaidő','Munkadíj','Létszám × tényleges munkaidő × 8 500 Ft/fő/óra','A Munkalap tényleges érkezési és távozási időből számol.','óra','fő',0::numeric,8500::numeric,false,'{"type":"linear"}'),
 (2,'Munkalap – kertfenntartás','Zöldhulladék ömlesztett',null,null,'m³',null,9000,0,false,'{"type":"linear"}'),
 (3,'Munkalap – kertfenntartás','Zöldhulladék zsákos',null,null,'zsák',null,1300,0,false,'{"type":"linear"}'),
 (4,'Munkalap – kertfenntartás','Zöldhulladék big bag','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','db',null,1,0,true,'{"type":"linear"}'),
 (5,'Munkalap – kertfenntartás','Növényvédelem','Sávos tartályár a Munkalap képlete szerint.','1. tartály: 25 000 Ft; 2–4. tartály: 17 000 Ft/db; 5. tartálytól: 12 000 Ft/db.','tartály (15L)',null,25000,0,false,'{"type":"tiered","first":25000,"middle":17000,"middle_count":3,"later":12000}'),
 (6,'Munkalap – kertfenntartás','Lemosó permetezés','Sávos tartályár a Munkalap képlete szerint.','1. tartály: 20 000 Ft; 2–4. tartály: 12 000 Ft/db; 5. tartálytól: 7 000 Ft/db.','tartály (15L)',null,20000,0,false,'{"type":"tiered","first":20000,"middle":12000,"middle_count":3,"later":7000}'),
 (7,'Munkalap – kertfenntartás','Bio permetezés',null,null,'tartály (15L)',null,15000,0,false,'{"type":"linear"}'),
 (8,'Munkalap – kertfenntartás','Gyomirtó',null,null,'liter',null,1400,0,false,'{"type":"linear"}'),
 (9,'Munkalap – kertfenntartás','Talajpermet','Sávos tartályár a Munkalap képlete szerint.','1. tartály: 25 000 Ft; 2–4. tartály: 17 000 Ft/db; 5. tartálytól: 12 000 Ft/db.','tartály (15L)',null,25000,0,false,'{"type":"tiered","first":25000,"middle":17000,"middle_count":3,"later":12000}'),
 (10,'Munkalap – kertfenntartás','Fűmag',null,null,'adagoló',null,6000,0,false,'{"type":"linear"}'),
 (11,'Munkalap – kertfenntartás','Műtrágya általános',null,null,'adagoló',null,6000,0,false,'{"type":"linear"}'),
 (12,'Munkalap – kertfenntartás','Műtrágya mohairtó',null,null,'adagoló',null,9000,0,false,'{"type":"linear"}'),
 (13,'Munkalap – kertfenntartás','Műtrágya gyomirtó',null,null,'adagoló',null,12000,0,false,'{"type":"linear"}'),
 (14,'Munkalap – kertfenntartás','Marhatrágya 20L',null,null,'zsák',null,1500,0,false,'{"type":"linear"}'),
 (15,'Munkalap – kertfenntartás','Marhatrágya 50L',null,null,'zsák',null,3000,0,false,'{"type":"linear"}'),
 (16,'Munkalap – kertfenntartás','Termőföld 20L',null,null,'zsák',null,1500,0,false,'{"type":"linear"}'),
 (17,'Munkalap – kertfenntartás','Termőföld 40/50L','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','zsák',null,1,0,true,'{"type":"linear"}'),
 (18,'Munkalap – kertfenntartás','Karó cserjének','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','db',null,1,0,true,'{"type":"linear"}'),
 (19,'Munkalap – kertfenntartás','Karó fának','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','db',null,1,0,true,'{"type":"linear"}'),
 (20,'Munkalap – kertfenntartás','Geotextília',null,null,'m²',null,700,0,false,'{"type":"linear"}'),
 (21,'Munkalap – kertfenntartás','Fatörzsvédő',null,null,'db',null,900,0,false,'{"type":"linear"}'),
 (22,'Munkalap – kertfenntartás','Öntözőrendszer anyagok','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','tétel',null,1,0,true,'{"type":"linear"}'),
 (23,'Munkalap – kertfenntartás','Egyéb1','Egyedi, árazandó tétel.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','tétel',null,1,0,true,'{"type":"linear"}'),
 (24,'Munkalap – kertfenntartás','Egyéb2','Egyedi, árazandó tétel.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','tétel',null,1,0,true,'{"type":"linear"}'),
 (25,'Munkalap – kertépítés / fuvar','Fuvarok száma','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','fuvar',null,1,0,true,'{"type":"linear"}'),
 (26,'Munkalap – kertépítés / fuvar','Fuvaronként megtett út','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','km',null,1,0,true,'{"type":"linear"}'),
 (27,'Munkalap – kertépítés / fuvar','Fuvarozás összes megtett út','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','km',null,1,0,true,'{"type":"linear"}'),
 (28,'Munkalap – kertépítés / fuvar','Földelszállítás','8 000 Ft/m³ és egyszeri 10 000 Ft szállítási díj.','A 10 000 Ft egyszeri díj csak pozitív mennyiségnél adódik hozzá.','m³',null,8000,0,false,'{"type":"fixed_plus_unit","unit_price":8000,"fixed":10000}'),
 (29,'Munkalap – kertépítés / fuvar','Szemét elszállítás','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','m³',null,1,0,true,'{"type":"linear"}'),
 (30,'Munkalap – kertépítés / fuvar','Termőföld','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','m³',null,1,0,true,'{"type":"linear"}'),
 (31,'Munkalap – kertépítés / fuvar','Murva/andezit teherhordó réteg','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','m³',null,1,0,true,'{"type":"linear"}'),
 (32,'Munkalap – kertépítés / fuvar','Murva/andezit ágyazó réteg','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','m³',null,1,0,true,'{"type":"linear"}'),
 (33,'Munkalap – kertépítés / fuvar','Kulé kavics','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','m³',null,1,0,true,'{"type":"linear"}'),
 (34,'Munkalap – kertépítés / fuvar','Homok','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','m³',null,1,0,true,'{"type":"linear"}'),
 (35,'Munkalap – kertépítés / fuvar','Beton C20 ömlesztett','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','m³',null,1,0,true,'{"type":"linear"}'),
 (36,'Munkalap – kertépítés / fuvar','Beton CKT ömlesztett','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','m³',null,1,0,true,'{"type":"linear"}'),
 (37,'Munkalap – kertépítés / fuvar','Sóder','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','m³',null,1,0,true,'{"type":"linear"}'),
 (38,'Munkalap – kertépítés / fuvar','Cement','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','25kg/db',null,1,0,true,'{"type":"linear"}'),
 (39,'Munkalap – kertépítés / fuvar','Beton kész zsákos','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','db',null,1,0,true,'{"type":"linear"}'),
 (40,'Munkalap – kertépítés / fuvar','Beton gyorsan kötő','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','db',null,1,0,true,'{"type":"linear"}'),
 (41,'Munkalap – kertépítés / fuvar','C20 beton ömlesztett','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','m³',null,1,0,true,'{"type":"linear"}'),
 (42,'Munkalap – kertépítés / fuvar','CKT beton ömlesztett','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','m³',null,1,0,true,'{"type":"linear"}'),
 (43,'Munkalap – kertépítés / fuvar','Raklap','Az eladási ár a forrásban nincs kitöltve.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','db',null,1,0,true,'{"type":"linear"}'),
 (44,'Munkalap – kertépítés / fuvar','Egyéb1','Egyedi, árazandó tétel.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','tétel',null,1,0,true,'{"type":"linear"}'),
 (45,'Munkalap – kertépítés / fuvar','Egyéb2','Egyedi, árazandó tétel.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','tétel',null,1,0,true,'{"type":"linear"}'),
 (46,'Munkalap – kertépítés / fuvar','Egyéb3','Egyedi, árazandó tétel.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','tétel',null,1,0,true,'{"type":"linear"}'),
 (47,'Munkalap – kertépítés / fuvar','Egyéb4','Egyedi, árazandó tétel.','1 Ft jelzőár; ajánlat előtt kötelező ellenőrizni.','tétel',null,1,0,true,'{"type":"linear"}')
), prepared as (
 select s.*,s.rule::jsonb as calculation_rule,
  lower(regexp_replace(translate(btrim(s.subcategory),'ÁÉÍÓÖŐÚÜŰáéíóöőúüű','AEIOOOUUUaeiooouuu'),'[^a-zA-Z0-9]+','','g')) as key,
  lower(regexp_replace(translate(coalesce(s.unit1,''),'ÁÉÍÓÖŐÚÜŰáéíóöőúüű³²','AEIOOOUUUaeiooouuu32'),'[^a-zA-Z0-9]+','','g')) as unit_key
 from source_rows s
), filtered as (
 select p.* from prepared p where not exists(
  select 1 from public.quote_price_catalog c
  where c.source<>'Munkalap árlista'
   and c.comparison_key=p.key
   and lower(regexp_replace(translate(coalesce(c.unit1,''),'ÁÉÍÓÖŐÚÜŰáéíóöőúüű³²','AEIOOOUUUaeiooouuu32'),'[^a-zA-Z0-9]+','','g'))=p.unit_key
   and c.material_unit=p.material_unit and c.labor_unit=p.labor_unit
   and c.calculation_rule=p.calculation_rule
 )
), ranked as (
 select f.*,coalesce(
  (select c.price_variant from public.quote_price_catalog c where c.source='Munkalap árlista' and c.source_row=f.source_row),
  coalesce((select max(c.price_variant) from public.quote_price_catalog c where c.comparison_key=f.key),0)
   +row_number() over(partition by f.key order by f.source_row)
 ) as variant
 from filtered f
)
insert into public.quote_price_catalog(source,source_row,category,subcategory,description,internal_notes,unit1,unit2,material_unit,labor_unit,comparison_key,price_variant,pricing_required,calculation_rule)
select 'Munkalap árlista',source_row,category,subcategory,description,internal_notes,unit1,unit2,material_unit,labor_unit,key,variant,pricing_required,calculation_rule
from ranked
on conflict(source,source_row) do update set
 category=excluded.category,subcategory=excluded.subcategory,description=excluded.description,internal_notes=excluded.internal_notes,
 unit1=excluded.unit1,unit2=excluded.unit2,material_unit=excluded.material_unit,labor_unit=excluded.labor_unit,
 comparison_key=excluded.comparison_key,price_variant=excluded.price_variant,pricing_required=excluded.pricing_required,
 calculation_rule=excluded.calculation_rule,active=true;

create or replace function quote_private.catalog_rule_to_item() returns trigger
language plpgsql set search_path='' as $$
begin
 if new.catalog_id is not null then
  select c.calculation_rule into new.calculation_rule from public.quote_price_catalog c where c.id=new.catalog_id;
 end if;
 return new;
end $$;

revoke all on function quote_private.catalog_rule_to_item() from public,anon;

drop trigger if exists quote_catalog_rule_to_item on public.quote_items;
create trigger quote_catalog_rule_to_item before insert or update of catalog_id on public.quote_items
for each row execute function quote_private.catalog_rule_to_item();
