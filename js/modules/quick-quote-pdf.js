import { calculateItem, calculateTotal, money } from './quote-calculator.js';
import { validateQuickQuote, measurementText } from './quick-quote-model.js';

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
export async function quickQuotePdf(record){
 const p=record.payload;validateQuickQuote(p);
 const {font,logo}=await loadResources(),doc=new window.jspdf.jsPDF({unit:'mm',format:'a4',compress:true,putOnlyUsedFonts:true});
 doc.addFileToVFS('Lato-Regular.ttf',font);doc.addFont('Lato-Regular.ttf','Lato','normal');doc.setFont('Lato');
 doc.setProperties({title:record.number+' – '+(p.title||'Árajánlat'),subject:'Díszkertek árajánlat',author:p.issuer?.name||'Díszkertek',creator:'Díszkertek Árajánlat'});
 let y=46;const ink=[34,45,65],muted=[88,97,111],red=[147,64,54],issuer=p.issuer||{};
 const text=(value,x,top,size=10,color=ink,options={})=>{doc.setFontSize(size);doc.setTextColor(...color);doc.text(String(value??''),x,top,options);};
 const header=()=>{
  const image=doc.getImageProperties(logo),w=Math.min(42,18*image.width/image.height),h=w*image.height/image.width;doc.addImage(logo,'PNG',16,12,w,h);
  doc.setFontSize(11);const names=doc.splitTextToSize(issuer.name||'Díszkertek',108);text(names,194,15,11,ink,{align:'right'});
  const contact=[issuer.address,issuer.tax_number?'Adószám: '+issuer.tax_number:'',[issuer.email,issuer.phone].filter(Boolean).join(' · ')].filter(Boolean);
  let top=15+names.length*4.5;for(const line of contact){const lines=doc.splitTextToSize(line,108);text(lines,194,top,8,muted,{align:'right'});top+=lines.length*3.5;}
  const rule=Math.max(36,top+3);doc.setDrawColor(...ink);doc.setLineWidth(.35);doc.line(16,rule,194,rule);text('ÁRAJÁNLAT',16,rule+7,11);text(record.number,194,rule+7,9,red,{align:'right'});y=rule+16;
 };
 const ensure=height=>{if(y+height>268){doc.addPage();header();}};
 const paragraph=(value,size=10,width=178,color=ink)=>{if(!value)return;doc.setFontSize(size);const lines=doc.splitTextToSize(String(value).replace(/\r/g,''),width);for(const line of lines){ensure(5);text(line,16,y,size,color);y+=5;}};
 header();paragraph(p.title,16);y+=2;
 paragraph([p.customer?.name,p.address].filter(Boolean).join('\n'),10);
 paragraph([p.customer?.email,p.customer?.phone].filter(Boolean).join(' · '),9,178,muted);
 paragraph([p.issued_on?'Kelt: '+p.issued_on:'',p.valid_until?'Érvényes: '+p.valid_until:''].filter(Boolean).join('     '),9,178,muted);y+=5;
 const tableHeader=()=>{ensure(14);doc.setFillColor(237,239,242);doc.rect(16,y-4,178,8,'F');text('Tétel',18,y,9);text('Mennyiség',126,y,8,ink,{align:'right'});text('Nettó egységár',158,y,8,ink,{align:'right'});text('Nettó összeg',192,y,8,ink,{align:'right'});y+=9;};
 tableHeader();let group='';
 for(const item of p.items){
  const amount=calculateItem(item);doc.setFontSize(10);const names=doc.splitTextToSize(item.name,78),details=doc.splitTextToSize([measurementText(item),item.public_note,item.other_cost?'Egyéb költség: '+money(item.other_cost):''].filter(Boolean).join('\n'),78),height=Math.max(12,names.length*4.6+details.length*4+4);
  if(y+height+(item.main_item!==group?10:0)>268){doc.addPage();header();tableHeader();group='';}
  if(item.main_item&&item.main_item!==group){paragraph(item.main_item,11);y+=2;}group=item.main_item||'';
  text(names,18,y,10);const quantity=`${item.quantity1} ${item.unit1||''}${item.unit2?' × '+item.quantity2+' '+item.unit2:''}`;text(doc.splitTextToSize(quantity,25),126,y,8,ink,{align:'right'});
  text(money(Number(item.material_unit)+Number(item.labor_unit)),158,y,8,ink,{align:'right'});text(money(amount.net),192,y,9,ink,{align:'right'});
  if(details.length&&details.some(Boolean))text(details,18,y+names.length*4.6,8,muted);
  y+=height;doc.setDrawColor(217,222,228);doc.setLineWidth(.15);doc.line(16,y-3,194,y-3);
 }
 const total=calculateTotal(p.items);ensure(34);y+=4;text('Nettó összesen',116,y,10);text(money(total.net),194,y,10,ink,{align:'right'});y+=6;text('ÁFA összesen',116,y,10);text(money(total.vat),194,y,10,ink,{align:'right'});y+=9;text('Fizetendő összesen',116,y,11);text(money(total.gross),194,y,13,red,{align:'right'});y+=12;
 if(p.terms){paragraph('Feltételek',11);paragraph(p.terms,9);}
 const pages=doc.getNumberOfPages();for(let page=1;page<=pages;page++){doc.setPage(page);doc.setDrawColor(180,186,195);doc.line(16,277,194,277);doc.setFontSize(7);const footer=doc.splitTextToSize([issuer.name||'Díszkertek',issuer.email,issuer.phone].filter(Boolean).join(' · '),178);text(footer,16,281,7,muted);const bottom=Math.max(287,282+footer.length*3);text(record.number,16,bottom,8,muted);text(`${page} / ${pages} oldal`,194,bottom,8,muted,{align:'right'});}
 return new File([doc.output('arraybuffer')],record.number+'.pdf',{type:'application/pdf'});
}
