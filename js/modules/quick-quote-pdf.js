import { groupDimensions } from './quote-groups.js?v=60';
import { calculateItem, money } from './quote-calculator.js?v=47';
import { validateQuickQuote, measurementText, itemIncomplete, quickTotals, quoteVatRate } from './quick-quote-model.js?v=58';

let resources;
const base64=buffer=>{let value='';const bytes=new Uint8Array(buffer);for(let i=0;i<bytes.length;i+=8192)value+=String.fromCharCode(...bytes.subarray(i,i+8192));return btoa(value);};
async function loadResources(){
 if(!resources)resources=(async()=>{
  if(!window.jspdf){await new Promise((resolve,reject)=>{const script=document.createElement('script');script.src=new URL('../../assets/vendor/jspdf-4.2.1.umd.min.js',import.meta.url).href;script.onload=resolve;script.onerror=()=>{script.remove();reject(Error('A PDF-készítő nem töltődött be. Próbáld újra.'));};document.head.append(script);});}
  const [font,logo]=await Promise.all(['Lato-Regular.ttf','../diszkertek-logo.png'].map(async file=>{const response=await fetch(new URL('../../assets/vendor/'+file,import.meta.url));if(!response.ok)throw Error('A PDF betűtípusa vagy logója nem töltődött be.');return response.arrayBuffer();}));
  return {font:base64(font),logo:'data:image/png;base64,'+base64(logo)};
 })().catch(error=>{resources=null;throw error;});
 return resources;
}
function priceDetails(item,amount){
 const unit=[item.unit1,item.unit2].filter(Boolean).join(' / ')||'egység';
 if(['transport','total'].includes(item.cost_kind))return `${item.cost_kind==='transport'?'Elszállítás / fuvar':'Díj bontás nélkül'}: ${itemIncomplete(item)?'pontosítandó':money(amount.other)}`;
 const materialPending=item.pending?.material||!item.pending&&item.pricing_required&&Number(item.material_unit)===1;
 const laborPending=item.pending?.labor||!item.pending&&item.pricing_required&&Number(item.labor_unit)===1;
 const rule=item.calculation_rule||{};
 const materialPrice=materialPending?'pontosítandó':rule.type==='tiered'?`első egység ${money(rule.first)}, következő ${rule.middle_count||3} egység ${money(rule.middle)} / egység, további ${money(rule.later)} / egység`:rule.type==='fixed_plus_unit'?`${money(rule.unit_price??item.material_unit)} / ${unit} + egyszeri ${money(rule.fixed)}`:money(item.material_unit)+' / '+unit;
 return ['Anyag egységár: '+materialPrice,'Munkadíj egységár: '+(laborPending?'pontosítandó':money(item.labor_unit)+' / '+unit),item.pending?.quantity?'Anyag- és munkadíjösszeg: mennyiségre vár':'Anyag összesen: '+(materialPending?'pontosítandó':money(amount.material))+' · Munkadíj összesen: '+(laborPending?'pontosítandó':money(amount.labor))].join('\n');
}
export async function quickQuotePdf(record,{draft=false,images=[]}={}){
 const p=record.payload;if(!draft)validateQuickQuote(p);
 const {font,logo}=await loadResources(),doc=new window.jspdf.jsPDF({unit:'mm',format:'a4',compress:true,putOnlyUsedFonts:true});
 doc.addFileToVFS('Lato-Regular.ttf',font);doc.addFont('Lato-Regular.ttf','Lato','normal');doc.setFont('Lato');
 doc.setProperties({title:record.number+' – '+(p.title||'Árajánlat'),subject:'Díszkertek árajánlat',author:p.issuer?.name||'Díszkertek',creator:'Díszkertek Árajánlat'});
 let y=46;const ink=[34,45,65],muted=[88,97,111],red=[147,64,54],issuer=p.issuer||{};
 const text=(value,x,top,size=10,color=ink,options={})=>{doc.setFontSize(size);doc.setTextColor(...color);doc.text(Array.isArray(value)?value.map(String):String(value??''),x,top,options);};
 const header=()=>{
  const image=doc.getImageProperties(logo),w=Math.min(42,18*image.width/image.height),h=w*image.height/image.width;doc.addImage(logo,'PNG',16,12,w,h);
  doc.setFontSize(11);const names=doc.splitTextToSize(issuer.name||'Díszkertek',108);text(names,194,15,11,ink,{align:'right'});
  const contact=[issuer.address,issuer.tax_number?'Adószám: '+issuer.tax_number:'',[issuer.email,issuer.phone].filter(Boolean).join(' · ')].filter(Boolean);
  let top=15+names.length*4.5;for(const line of contact){const lines=doc.splitTextToSize(line,108);text(lines,194,top,8,muted,{align:'right'});top+=lines.length*3.5;}
  const rule=Math.max(36,top+3);doc.setDrawColor(...ink);doc.setLineWidth(.35);doc.line(16,rule,194,rule);text(draft?'PISZKOZAT':'ÁRAJÁNLAT',16,rule+7,11);text(record.number,194,rule+7,9,red,{align:'right'});y=rule+16;
 };
 const ensure=height=>{if(y+height>268){doc.addPage();header();}};
 const paragraph=(value,size=10,width=178,color=ink)=>{if(!value)return;doc.setFontSize(size);const lines=doc.splitTextToSize(String(value).replace(/\r/g,''),width);for(const line of lines){ensure(5);text(line,16,y,size,color);y+=5;}};
 header();paragraph(p.title,16);y+=2;
 if(draft){paragraph('Előnézet – nem végleges, nem megrendelhető ajánlat.',10,178,red);y+=2;}
 if(p.project_code)paragraph('Projekt: '+p.project_code,9,178,muted);
 if(p.survey_date)paragraph('Felmérés: '+p.survey_date,9,178,muted);
 paragraph([p.customer?.name,p.address].filter(Boolean).join('\n'),10);
 paragraph([p.customer?.email,p.customer?.phone].filter(Boolean).join(' · '),9,178,muted);
 paragraph([p.issued_on?'Kelt: '+p.issued_on:'',p.valid_until?'Érvényes: '+p.valid_until:''].filter(Boolean).join('     '),9,178,muted);y+=5;
 const total=quickTotals(p.items),vatRate=quoteVatRate(p.items,p.quote_vat_rate??0),percent=new Intl.NumberFormat('hu-HU',{minimumFractionDigits:2,maximumFractionDigits:2});
 const totalBlock=()=>{
  ensure(total.pendingCount?37:30);y+=3;
  if(total.pendingCount){paragraph(`${total.pendingCount} tétel pontosítandó; az összesítő csak az ismert árú tételeket tartalmazza.`,8,178,red);y+=1;}
  text('ÁFA vetítési alap',16,y,9);text(money(total.net),194,y,10,ink,{align:'right'});y+=5;
  text(vatRate===null?'ÁFA (tételenként)':`ÁFA (${percent.format(vatRate*100)}%)`,16,y,9);text(money(total.vat),194,y,10,ink,{align:'right'});y+=6;
  text(total.pendingCount?'Ismert tételek részösszege':'Fizetendő összeg',16,y,11);text(money(total.gross),194,y,13,red,{align:'right'});y+=10;
 };
 const groups=new Map();
 for(const item of p.items){
  const key=item.main_item||item.category||'Tételek';if(!groups.has(key))groups.set(key,{name:key,material:0,labor:0,other:0,net:0,pending:false,known:0});
  const group=groups.get(key);if(itemIncomplete(item)){group.pending=true;continue;}const amount=calculateItem(item);for(const field of ['material','labor','other','net'])group[field]+=amount[field];group.known++;
 }
 const hasOther=p.items.some(i=>Number(i.other_cost)||['transport','total'].includes(i.cost_kind));
 const columns=hasOther?[['material','Anyagköltség',111],['labor','Munkadíj',139],['other','Egyéb díj',166],['net','Összesen',194]]:[['material','Anyagköltség',128],['labor','Munkadíj',161],['net','Összesen',194]];
 const summaryHeader=continuation=>{
  paragraph(continuation?'Költségvetés összesítő – folytatás':'Költségvetés összesítő',12);y+=2;
  doc.setFillColor(237,239,242);doc.rect(16,y-4,178,8,'F');text('Megnevezés',18,y,8);for(const [,label,x] of columns)text(label,x,y,7.5,ink,{align:'right'});y+=8;
 };
 ensure(25);summaryHeader(false);const grouped=[...groups.values()];
 for(const [index,group] of grouped.entries()){
  doc.setFontSize(8.5);const names=doc.splitTextToSize(group.name+(group.pending?' *':''),hasOther?65:80),height=Math.max(4,names.length*3.8)+3;
  if(y+height+(index===grouped.length-1?42:0)>268){doc.addPage();header();summaryHeader(true);}
  text(names,18,y,8.5);
  for(const [field,,x] of columns)text(group.pending&&!group.known?(field==='net'?'Pontosítandó':'—'):money(group[field])+(group.pending&&field==='net'?' *':''),x,y,7.5,group.pending&&!group.known?red:ink,{align:'right'});
  y+=height;doc.setDrawColor(217,222,228);doc.setLineWidth(.15);doc.line(16,y-3,194,y-3);
 }
 ensure(8);text('Összesen',18,y,8.5);for(const [field,,x] of columns)text(money(total[field]),x,y,8,ink,{align:'right'});y+=6;
 totalBlock();
 ensure(54);
 for(let copy=0;copy<2;copy++){
  text('Készpénz átvételi elismervény',105,y,10,ink,{align:'center'});y+=6;
  text('Összeg:',16,y,9);text('Dátum:',116,y,9);doc.setDrawColor(100,108,115);doc.setLineWidth(.15);doc.line(32,y+1,103,y+1);doc.line(132,y+1,194,y+1);y+=9;
  doc.line(16,y,80,y);doc.line(130,y,194,y);text('Vállalkozó aláírása',48,y+4,7,ink,{align:'center'});text('Megrendelő aláírása',162,y+4,7,ink,{align:'center'});y+=11;
 }
 if(p.terms){doc.addPage();header();paragraph('Az ajánlatra vonatkozó fontos információk',13);y+=3;if(p.execution_period)paragraph('A kivitelezés tervezett ideje: '+p.execution_period,10);paragraph(p.terms,9);ensure(24);y+=8;doc.setDrawColor(100,108,115);doc.line(16,y,80,y);doc.line(130,y,194,y);text('Vállalkozó aláírása',48,y+4,8,ink,{align:'center'});text('Megrendelő aláírása',162,y+4,8,ink,{align:'center'});}
 doc.addPage();header();paragraph('Részletes tételezés',13);y+=3;
 const tableHeader=()=>{ensure(14);doc.setFillColor(237,239,242);doc.rect(16,y-4,178,8,'F');text('Tétel',18,y,9);text('Mennyiség',126,y,8,ink,{align:'right'});text('Egységár',158,y,8,ink,{align:'right'});text('Összeg',192,y,8,ink,{align:'right'});y+=9;};
 tableHeader();let group='';
 for(const [index,item] of p.items.entries()){
  const amount=calculateItem(item),pending=itemIncomplete(item);doc.setFontSize(10);const names=doc.splitTextToSize(`${index+1}. ${item.name}`,78),details=doc.splitTextToSize([item.pending?.quantity?'':measurementText(item),priceDetails(item,amount),item.description,item.public_note,!['transport','total'].includes(item.cost_kind)&&item.other_cost?'Egyéb költség összesen: '+money(item.other_cost):''].filter(Boolean).join('\n'),78),height=Math.max(15,names.length*4.6+details.length*4+8);
  const groupMeta=(p.groups||[]).find(g=>g.id===item.group_id||g.name===item.main_item),dimensions=groupMeta?groupDimensions(groupMeta):'';
  if(y+height+(item.main_item!==group?(dimensions?20:10):0)>268){doc.addPage();header();tableHeader();group='';}
  if(item.main_item&&item.main_item!==group){paragraph(item.main_item,11);if(dimensions)paragraph(dimensions,8,178,muted);y+=2;}group=item.main_item||'';
  text(names,18,y,10);const quantity=item.pending?.quantity?'Pontosítandó':`${item.quantity1} ${item.unit1||''}${item.unit2?' × '+item.quantity2+' '+item.unit2:''}`;text(doc.splitTextToSize(quantity,25),126,y,8,ink,{align:'right'});
  const unitPrice=['transport','total'].includes(item.cost_kind)?amount.other/(Number(item.quantity1)*(item.unit2?Number(item.quantity2):1)||1):Number(item.material_unit)+Number(item.labor_unit);
  text(pending?'—':['tiered','fixed_plus_unit'].includes(item.calculation_rule?.type)?'Részletezve':money(unitPrice),158,y,8,ink,{align:'right'});text(pending?'Pontosítandó':money(amount.net),192,y,8,pending?red:ink,{align:'right'});
  if(details.length&&details.some(Boolean))text(details,18,y+names.length*4.6,8,muted);
  y+=height;doc.setDrawColor(217,222,228);doc.setLineWidth(.15);doc.line(16,y-4,194,y-4);
 }
 ensure(14);y+=3;text('Tételes alapösszeg',16,y,10);text(money(total.net),194,y,11,ink,{align:'right'});y+=10;
 if(images.length){
  doc.addPage();header();paragraph('Képes melléklet – munkafázisok',14);y+=3;
  for(const image of images){
   let properties;try{properties=doc.getImageProperties(image.data);}catch{throw Error('Egy csatolt kép nem építhető a PDF-be. Nyisd meg a képet, vagy vedd ki a PDF-jelölését.');}
   const width=Math.min(178,properties.width/properties.height*100),height=width*properties.height/properties.width;
   doc.setFontSize(9);const caption=doc.splitTextToSize(image.caption||'',178);doc.setFontSize(11);const label=`${image.group_name||'Ajánlat'} · ${image.phase||'Munkafázis'}`,labelLines=doc.splitTextToSize(label,178),space=height+13+caption.length*5+labelLines.length*5;
   ensure(space);paragraph(label,11);
   doc.addImage(image.data,'JPEG',16,y,width,height,undefined,'FAST');y+=height+5;
   if(image.caption)paragraph(image.caption,9);y+=8;
  }
 }
 const pages=doc.getNumberOfPages();for(let page=1;page<=pages;page++){doc.setPage(page);doc.setDrawColor(180,186,195);doc.line(16,277,194,277);doc.setFontSize(7);const footer=doc.splitTextToSize([issuer.name||'Díszkertek',issuer.email,issuer.phone].filter(Boolean).join(' · '),178);text(footer,16,281,7,muted);const bottom=Math.max(287,282+footer.length*3);text(record.number+(draft?' · PISZKOZAT':''),16,bottom,8,muted);text(`${page} / ${pages} oldal`,194,bottom,8,muted,{align:'right'});}
 return new File([doc.output('arraybuffer')],record.number+(draft?'-piszkozat':'')+'.pdf',{type:'application/pdf'});
}

export function publishedQuotePdf(snapshot,options={}){return quickQuotePdf({number:snapshot.number,payload:{title:snapshot.title,project_code:snapshot.project_code,customer:{name:snapshot.customer,email:snapshot.customer_email||'',phone:snapshot.customer_phone||''},address:snapshot.work_address,terms:snapshot.terms,valid_until:snapshot.valid_until,issued_on:snapshot.date?.slice(0,10),survey_date:snapshot.survey_date,execution_period:snapshot.execution_period,issuer:snapshot.issuer,groups:snapshot.pdf_groups||[],items:snapshot.pdf_items}},options);}
