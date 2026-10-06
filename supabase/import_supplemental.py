"""Read original attachments; emit repeatable quote-only SQL without changing sources."""
from pathlib import Path
from hashlib import sha256
import json
import re
import sys
import openpyxl
from pypdf import PdfReader

base = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / 'Downloads'
out = Path(__file__).with_name('quote_source_seed.sql')
records = []
filename = 'ontozorendszer_teljes_bontas.xlsx'
formula = openpyxl.load_workbook(base / filename, data_only=False)
cached = openpyxl.load_workbook(base / filename, data_only=True)
s = cached.active
cells = [{ 'cell': c.coordinate, 'value': c.value, 'cached': s[c.coordinate].value }
         for row in formula.active for c in row if c.value is not None]
lines = [dict(source_row=r, name=s[f'B{r}'].value, quantity=s[f'C{r}'].value,
              unit=s[f'D{r}'].value, note=s[f'E{r}'].value,
              material=s[f'F{r}'].value, extra_name=s[f'G{r}'].value,
              extra_material=s[f'H{r}'].value, shipping=s[f'I{r}'].value,
              labor=s[f'J{r}'].value, total=s[f'K{r}'].value)
         for r in range(7, 19)]
discounts = [dict(source_row=r, name=s[f'B{r}'].value, quantity=s[f'C{r}'].value,
                  unit=s[f'D{r}'].value, note=s[f'E{r}'].value,
                  material_min=s[f'F{r}'].value, material_max=s[f'G{r}'].value,
                  labor_min=s[f'H{r}'].value, labor_max=s[f'I{r}'].value)
             for r in range(27, 33)]
assert all(x['material']+x['extra_material']+x['shipping']+x['labor']==x['total'] for x in lines)
assert sum(x['total'] for x in lines)==s['F22'].value==1405000
assert 1405000-sum(x['material_min']+x['labor_min'] for x in discounts)==s['D40'].value==1111000
assert 1405000-sum(x['material_max']+x['labor_max'] for x in discounts)==s['D41'].value==1045000
payload = dict(type='irrigation', sheet=s.title, cells=cells, lines=lines, discounts=discounts,
               note=s['A43'].value, quote_lines=lines,
               total=s['F22'].value, expected_low=s['D41'].value, expected_high=s['D40'].value)
records.append(('irrigation-full', 'Öntözőrendszer és vízszerelés', filename, payload))

filename = 'Fűnyíró árajánlat 4 verzio.pdf'
titles = ['Vezetékes megoldás 2 robottal','Vezetékes megoldás 1 robottal','Wifi alapú robot','Gps alapú robot']
reader = PdfReader(base / filename)
amount = lambda text: int(text.replace(' ', '').replace('\xa0', ''))
index = 0
for page_no, page in enumerate(reader.pages, 1):
    text = page.extract_text()
    sections = re.split(r'megnevezés\s+ár/db\s+db\s+ár', text)[1:]
    assert len(sections)==2
    for section in sections:
        summaries = {m.group(1): {'net': amount(m.group(2)), 'gross': amount(m.group(3))}
                     for m in re.finditer(r'(Anyag költség|Telepítés|Tereprendezés|Összesen):?\s*([\d ]+)\s*Ft\s*([\d ]+)\s*Ft',section)}
        assert len(summaries)==4
        materials=[]
        for line in section.split('Nettó')[0].splitlines():
            m=re.fullmatch(r'(.+?)\s+([\d ]+)\s*Ft\s+(\d+)\s+([\d ]+)\s*Ft\s*',line)
            if m:
                row=dict(name=m.group(1).strip(), unit_price=amount(m.group(2)), quantity=int(m.group(3)), total=amount(m.group(4)))
                assert row['unit_price']*row['quantity']==row['total']
                materials.append(row)
        assert materials
        assert sum(x['total'] for x in materials)==summaries['Anyag költség']['gross']
        assert sum(summaries[k]['net'] for k in ['Anyag költség','Telepítés','Tereprendezés'])==summaries['Összesen']['net']
        assert sum(summaries[k]['gross'] for k in ['Anyag költség','Telepítés','Tereprendezés'])==summaries['Összesen']['gross']
        quote_lines=[dict(name=key,quantity=1,unit='kts',material_net=value['net'] if key=='Anyag költség' else 0,
                         labor_net=value['net'] if key!='Anyag költség' else 0, original_gross=value['gross'])
                     for key,value in summaries.items() if key!='Összesen']
        payload=dict(type='robot',page=page_no,source_text=section,materials=materials,summaries=summaries,
                     quote_lines=quote_lines,total_net=summaries['Összesen']['net'],total_gross=summaries['Összesen']['gross'])
        records.append((f'robot-{index+1}', titles[index], filename, payload))
        index+=1
assert index==4
def literal(value): return "'"+str(value).replace("'", "''")+"'"
sql=['-- Generated from original attachments; source cells, formulas and quoted prices preserved.']
for key,name,file,payload in records:
    values=[key,name,file,sha256((base/file).read_bytes()).hexdigest(),json.dumps(payload,ensure_ascii=False)]
    sql.append('insert into public.quote_source_packages(source_key,name,source_file,source_sha256,payload) values ('+
               ','.join(literal(v) for v in values)+"::jsonb) on conflict(source_key) do update set name=excluded.name, source_file=excluded.source_file,source_sha256=excluded.source_sha256,payload=excluded.payload,updated_at=now();")
out.write_text('\n'.join(sql)+'\n', encoding='utf-8')
print(json.dumps(dict(packages=len(records),irrigation_lines=len(lines),deductions=len(discounts),robot_variants=index,checks='passed'),ensure_ascii=True))

