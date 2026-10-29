// Images and attachment bytes never enter an RPC payload or a remote storage bucket.
let database;
const open=()=>database??=new Promise((resolve,reject)=>{const request=indexedDB.open('diszkertek-arajanlat-files',1);request.onupgradeneeded=()=>{const store=request.result.createObjectStore('attachments',{keyPath:'id'});store.createIndex('quote','quote_id');};request.onsuccess=()=>resolve(request.result);request.onerror=()=>{database=null;reject(Error('A helyi fájltár nem nyitható meg. Engedélyezd a böngésző tárhelyhasználatát.'));};});
async function transaction(mode,work){const db=await open();return new Promise((resolve,reject)=>{const tx=db.transaction('attachments',mode),request=work(tx.objectStore('attachments'));let result;request.onsuccess=()=>{result=request.result;};tx.oncomplete=()=>resolve(result);tx.onerror=tx.onabort=()=>reject(Error('A helyi fájl mentése nem sikerült. Ellenőrizd az eszköz szabad tárhelyét.'));});}
export const listLocalFiles=async quoteId=>(await transaction('readonly',s=>quoteId?s.index('quote').getAll(quoteId):s.getAll())).sort((a,b)=>String(a.created_at||'').localeCompare(String(b.created_at||''))||String(a.id).localeCompare(String(b.id)));
export const deleteLocalFile=id=>transaction('readwrite',s=>s.delete(id));
export const saveLocalFile=record=>transaction('readwrite',s=>s.put(record));
export async function addLocalFile(quoteId,groupId,file){
 if(file.size>25*1024*1024)throw Error('Egy fájl legfeljebb 25 MB lehet.');
 let blob=file,image=false;
 if(file.type.startsWith('image/')){
  const url=URL.createObjectURL(file),img=new Image();
  try{img.src=url;await img.decode();if(img.naturalWidth*img.naturalHeight>80000000)throw Error('A kép túl nagy. Válassz kisebb felbontást.');const scale=Math.min(1,1800/Math.max(img.naturalWidth,img.naturalHeight)),canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(img.naturalWidth*scale));canvas.height=Math.max(1,Math.round(img.naturalHeight*scale));const ctx=canvas.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(img,0,0,canvas.width,canvas.height);blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/jpeg',.82));if(!blob)throw Error('A kép feldolgozása nem sikerült.');image=true;}catch(error){throw Error(error.message==='A kép túl nagy. Válassz kisebb felbontást.'?error.message:'Ez a képformátum nem nyitható meg. Válassz JPG, PNG vagy WebP képet.');}finally{URL.revokeObjectURL(url);}
 }
 const record={id:crypto.randomUUID(),quote_id:quoteId,group_id:groupId,name:file.name.slice(0,200),type:blob.type,blob,image,phase:'Előtte',caption:'',include:image,created_at:new Date().toISOString()};
 await saveLocalFile(record);return record;
}
export async function pdfLocalImages(quoteId,groups=[]){
 const files=(await listLocalFiles(quoteId)).filter(f=>f.image&&f.include&&(!f.group_id||groups.some(g=>g.id===f.group_id)));
 return Promise.all(files.map(async f=>({...f,group_name:groups.find(g=>g.id===f.group_id)?.name||'Ajánlat',data:await new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(r.result);r.onerror=()=>reject(Error('Egy helyi kép nem olvasható.'));r.readAsDataURL(f.blob);})})));
}
