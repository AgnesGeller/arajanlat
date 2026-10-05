import { calculateWorksheet } from './worksheet-calculator.js';
import { calculateProgress } from './work-progress.js';
const SOURCE='https://wojgdfojupnfldrmqaht.supabase.co';
const headers={'Access-Control-Allow-Origin':'https://agnesgeller.github.io','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS','Content-Type':'application/json'};
const reply=(status,body)=>new Response(JSON.stringify(body),{status,headers});
const normalize=value=>String(value??'').normalize('NFKC').trim().replace(/\s+/g,' ').toLocaleLowerCase('hu');
Deno.serve(async request=>{
  if(request.method==='OPTIONS')return new Response(null,{headers});
  if(request.method!=='POST')return reply(405,{message:'Nem támogatott kérés.'});
  const readStartedAt=new Date().toISOString();
  try{
    const ownUrl=Deno.env.get('SUPABASE_URL'),ownKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),sourceKey=Deno.env.get('KASSZA_SERVICE_ROLE_KEY');
    const authorization=request.headers.get('Authorization');
    if(!authorization?.startsWith('Bearer '))return reply(401,{message:'Belépés szükséges.'});
    const body=await request.json();
    const worker=body.action==='worker_state';
    if(worker&&!sourceKey)return reply(503,{message:'A projektkapcsolat nincs beállítva.'});
    const auth=await fetch((worker?SOURCE:ownUrl)+'/auth/v1/user',{headers:{apikey:worker?sourceKey:ownKey,Authorization:authorization},signal:AbortSignal.timeout(15000)});
    if(!auth.ok)return reply(401,{message:'Belépés szükséges.'});
    const user=await auth.json();
    async function own(path,body){
      const response=await fetch(ownUrl+'/rest/v1/'+path,{method:body===undefined?'GET':'POST',headers:{apikey:ownKey,Authorization:'Bearer '+ownKey,'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
      if(!response.ok)throw Error('Az Árajánlat munkalapadatai most nem frissíthetők.');
      return response.json();
    }
    let company;
    if(worker){
      if(!/^[0-9a-f-]{36}$/i.test(body.customer_id||'')||!normalize(body.address))return reply(400,{message:'Ügyfél és cím szükséges.'});
      const profileResponse=await fetch(SOURCE+'/rest/v1/profiles?'+new URLSearchParams({id:'eq.'+user.id,select:'id,role'}),{headers:{apikey:sourceKey,Authorization:'Bearer '+sourceKey,'Accept-Profile':'munkalap'},signal:AbortSignal.timeout(15000)});
      if(!profileResponse.ok)throw Error('A munkalap-hozzáférés nem ellenőrizhető.');
      const profiles=await profileResponse.json();
      if(profiles.length!==1||!['worker','manager'].includes(profiles[0].role))return reply(403,{message:'Munkalap-hozzáférés szükséges.'});
      // Verify the caller can read this customer under the SOURCE's existing RLS.
      const allowed=await fetch(SOURCE+'/rest/v1/customers?'+new URLSearchParams({id:'eq.'+body.customer_id,select:'id'}),{headers:{apikey:sourceKey,Authorization:authorization,'Accept-Profile':'munkalap'},signal:AbortSignal.timeout(15000)});
      if(!allowed.ok||(await allowed.json()).length!==1)return reply(403,{message:'Ez az ügyfél nem elérhető.'});
      const linked=await own('quote_clients?'+new URLSearchParams({source_customer_id:'eq.'+body.customer_id,select:'company_id',merged_into:'is.null'}));
      const companies=[...new Set(linked.map(c=>c.company_id))];
      if(!companies.length)return reply(200,{projects:[]});
      if(companies.length!==1)return reply(409,{message:'A projektkapcsolat pontosítása szükséges.'});
      company=companies[0];
    }else{
      const staff=await own('quote_staff?'+new URLSearchParams({user_id:'eq.'+user.id,select:'company_id'}));
      if(staff.length!==1)return reply(403,{message:'Árajánlat-hozzáférés szükséges.'});
      company=staff[0].company_id;
    }
    if(!sourceKey)return reply(503,{message:'A munkalapok kapcsolata nincs beállítva.'});
    const clients=await own('quote_clients?'+new URLSearchParams({company_id:'eq.'+company,select:'id,source_customer_id'}));
    const clientMap=new Map(clients.map(c=>[c.id,c.source_customer_id]));
    if(clients.length>=1000)throw Error('Az ügyfélkapcsolatok teljes lekérése szükséges; a korábbi elszámolások megmaradtak.');
    const projects=clients.length?await own('quote_projects?'+new URLSearchParams({select:'id,name,project_code,client_id,work_address,started_on',started_on:'not.is.null',client_id:'in.('+clients.map(c=>c.id).join(',')+')'})):[];
    if(projects.length>=1000)throw Error('A projektek teljes lekérése szükséges; a korábbi elszámolások megmaradtak.');
    const grouped=new Map(),records=[],issues=[];
    for(const project of projects){
      const sourceId=clientMap.get(project.client_id);
      if(!sourceId||!normalize(project.work_address)){issues.push('Egy elindított projektnél hiányzik a közös ügyfélkapcsolat vagy a munkavégzési cím.');continue;}
      if(!grouped.has(sourceId))grouped.set(sourceId,[]);grouped.get(sourceId).push(project);
    }
    const started=Date.now();
    for(const [sourceId,candidates] of grouped){
      const earliest=candidates.map(p=>p.started_on).sort()[0];
      for(let offset=0;;offset+=250){
        if(Date.now()-started>75000||records.length>10000)throw Error('A lekérés túl nagy. A korábbi elszámolások megmaradtak.');
        const params=new URLSearchParams({customer_id:'eq.'+sourceId,work_date:'gte.'+earliest,select:'id,address,work_date,updated_at,form_data',order:'id',offset:String(offset),limit:'250'});
        // Kizárólag GET: a forrás Munkalap/Kassza adatbázisát soha nem írjuk.
        const response=await fetch(SOURCE+'/rest/v1/worksheets?'+params,{headers:{apikey:sourceKey,Authorization:'Bearer '+sourceKey,'Accept-Profile':'munkalap'},signal:AbortSignal.timeout(15000)});
        if(!response.ok)throw Error('A Munkalap most nem olvasható. A korábbi elszámolások megmaradtak.');
        const page=await response.json();
        for(const row of page){
          const explicit=row.form_data?.quote_project_id;
          const matches=candidates.filter(p=>p.started_on<=row.work_date&&normalize(p.work_address)===normalize(row.address)&&(!explicit||p.id===explicit));
          if(matches.length!==1){if(matches.length>1)issues.push('Egy munkalaphoz több projekt tartozhat; pontos projektkapcsolat szükséges.');continue;}
          records.push({source_id:row.id,project_id:matches[0].id,work_date:row.work_date,source_updated_at:row.updated_at,form_data:row.form_data,calculation:calculateWorksheet(row)});
        }
        if(page.length<250)break;
      }
    }
    await own('rpc/quote_work_records_sync',{p_company:company,p_records:records,p_read_started_at:readStartedAt});
    if(worker){
      const result=[];
      for(const p of projects.filter(p=>clientMap.get(p.client_id)===body.customer_id&&normalize(p.work_address)===normalize(body.address)&&p.started_on<=(body.work_date||new Date().toISOString().slice(0,10)))){
        const summary=await own('rpc/quote_project_work_summary',{p_project:p.id});
        const progress=calculateProgress(summary.items,summary.settings,summary.records);
        const hours=summary.records.reduce((s,r)=>s+Number(r.calculation.person_hours||0),0);
        const invalid=summary.records.some(r=>r.calculation.issues?.some(i=>i.startsWith('Csapat ')||i==='Nincs megadott munkaidő.'));
        const budget=summary.labor_budget>0?summary.labor_budget/8500:null;
        // Only the two indicators and project identity leave the server. No prices, contacts or notes.
        result.push({id:p.id,name:p.name,project_code:p.project_code,started_on:p.started_on,completion:progress.percent,
          hours:invalid?null:hours,budget_hours:budget,time_percent:budget&&!invalid?hours/budget*100:null,remaining_hours:budget&&!invalid?budget-hours:null});
      }
      return reply(200,{projects:result,issues:[...new Set(issues)]});
    }
    return reply(200,{imported:records.length,issues:[...new Set(issues)]});
  }catch(error){return reply(503,{message:error.message||'A munkalapok most nem frissíthetők.'});}
});
