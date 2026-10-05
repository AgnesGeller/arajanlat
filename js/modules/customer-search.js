export function mountCustomerSearch({input,results,count,customers,onSelect,fail}){
 let matches=[],active=-1;
 const normalize=value=>String(value||'').trim().replace(/\s+/g,' ').toLocaleLowerCase('hu-HU');
 const escape=value=>String(value||'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 function close(){results.hidden=true;input.setAttribute('aria-expanded','false');input.removeAttribute('aria-activedescendant');active=-1}
 async function select(customer){close();input.value=customer.name;try{await onSelect(customer.id)}catch(error){fail(error)}}
 function render(){
  const term=normalize(input.value),all=customers();
  if(term.length<2){close();count.textContent=all.length+' ügyfél · Írj be legalább két betűt.';return}
  matches=all.filter(c=>[c.name,c.contact_name,c.phone,c.email,c.billing_address,c.project_address].some(value=>normalize(value).includes(term)));
  active=-1;input.removeAttribute('aria-activedescendant');
  results.innerHTML=matches.map((c,i)=>`<button type="button" role="option" aria-selected="false" tabindex="-1" id="customer-result-${i}" data-index="${i}"><strong>${escape(c.name)}</strong><small>${escape(c.project_address||c.billing_address||'')}</small></button>`).join('');
  const expanded=Boolean(matches.length&&document.activeElement===input);results.hidden=!expanded;input.setAttribute('aria-expanded',String(expanded));
  count.textContent=matches.length?matches.length+' találat':'Nincs találat.';
  results.querySelectorAll('[data-index]').forEach(button=>button.onclick=()=>select(matches[Number(button.dataset.index)]));
 }
 input.addEventListener('input',render);input.addEventListener('focus',render);
 input.addEventListener('keydown',event=>{
  if(event.key==='Escape'){close();return}
  if(results.hidden||!matches.length)return;
  if(event.key==='Enter'&&active>=0){event.preventDefault();select(matches[active]);return}
  if(!['ArrowDown','ArrowUp'].includes(event.key))return;
  event.preventDefault();active=(active+(event.key==='ArrowDown'?1:-1)+matches.length)%matches.length;
  results.querySelectorAll('[role="option"]').forEach((button,i)=>button.setAttribute('aria-selected',String(i===active)));
  const option=results.children[active];input.setAttribute('aria-activedescendant',option.id);option.scrollIntoView({block:'nearest'});
 });
 document.addEventListener('pointerdown',event=>{if(!input.parentElement.parentElement.contains(event.target))close()});
 input.parentElement.parentElement.addEventListener('focusout',event=>{if(!input.parentElement.parentElement.contains(event.relatedTarget))close()});
 return {render,close};
}
