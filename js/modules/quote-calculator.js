const value = n => Number.isFinite(Number(n)) ? Number(n) : 0;
const ruleOf=item=>item?.calculation_rule&&typeof item.calculation_rule==='object'?item.calculation_rule:{type:'linear'};
export function ruleMaterial(quantity,unitPrice,rule){
 const q=value(quantity),r=rule&&typeof rule==='object'?rule:{type:'linear'};
 if(r.type==='tiered'){
  if(!Number.isInteger(q)||q<0)throw Error('A sávos árú tétel mennyisége csak egész szám lehet.');
  if(q===0)return 0;
  return value(r.first)+Math.min(q-1,value(r.middle_count||3))*value(r.middle)+Math.max(q-1-value(r.middle_count||3),0)*value(r.later);
 }
 if(r.type==='fixed_plus_unit')return q*value(r.unit_price??unitPrice)+(q>0?value(r.fixed):0);
 return q*value(unitPrice);
}
export function calculateItem(item) {
  const secondary=item.unit2 ? value(item.quantity2) : 1;
  const multiplier = value(item.quantity1) * secondary;
  const ruled=ruleMaterial(item.quantity1,item.material_unit,ruleOf(item));
  const material = ruled*secondary;
  const labor = multiplier * value(item.labor_unit);
  const other = value(item.other_cost);
  const net = material + labor + other;
  const vat = net * value(item.vat_rate);
  return { material, labor, other, net, vat, gross: net + vat };
}
export function calculateTotal(items) {
  return items.reduce((total, item) => {
    const row = calculateItem(item);
    for (const key of ['material','labor','other','net','vat','gross']) total[key] += row[key];
    return total;
  }, { material:0, labor:0, other:0, net:0, vat:0, gross:0 });
}
export const money = n => new Intl.NumberFormat('hu-HU', { maximumFractionDigits: 0 }).format(n || 0) + ' Ft';
export const dateTime = iso => iso ? new Intl.DateTimeFormat('hu-HU', {dateStyle:'short',timeStyle:'short',timeZone:'Europe/Budapest'}).format(new Date(iso)) : '—';
