export const WORK_FIELDS={
 'Kertépítés':['area_m2','length_fm','width_m','count'],
 'Füvesítés':['area_m2','length_fm','width_m'],
 'Öntözőrendszer':['area_m2','length_fm','count','existing_zones','existing_valves','existing_sprinklers'],
 'Növénytelepítés':['area_m2','count'],
 'Térkövezés':['area_m2','length_fm','width_m'],
 'Egyéb':['area_m2','length_fm','width_m','count']
};
const labels={area_m2:'Terület (m²)',length_fm:'Hosszúság (fm)',width_m:'Szélesség (m)',count:'Darabszám',existing_zones:'Meglévő öntözési körök száma',existing_valves:'Meglévő mágnesszelepek száma',existing_sprinklers:'Meglévő szórófejek száma'};
export const requestDimensionFields=()=>Object.entries(labels).map(([name,label])=>`<label data-work-field="${name}" hidden>${label}<input name="${name}" type="number" min="0" step="${name==='count'||name.startsWith('existing_')?'1':'any'}" disabled></label>`).join('');
export function mountRequestWorkFields(form){
 const select=form.elements.work_type;
 const update=()=>{const active=WORK_FIELDS[select.value]||[];form.querySelectorAll('[data-work-field]').forEach(label=>{const enabled=active.includes(label.dataset.workField);label.hidden=!enabled;label.querySelector('input').disabled=!enabled;});};
 select.addEventListener('change',update);update();
}
