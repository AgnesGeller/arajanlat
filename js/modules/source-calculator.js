export function irrigationTotals(payload,selected=payload.discounts.map((_,i)=>i)){
 const base=payload.lines.reduce((t,r)=>t+r.material+r.extra_material+r.shipping+r.labor,0);
 const discounts=payload.discounts.filter((_,i)=>selected.includes(i));
 const minimum=discounts.reduce((t,r)=>t+r.material_min+r.labor_min,0);
 const maximum=discounts.reduce((t,r)=>t+r.material_max+r.labor_max,0);
 return {base,minimum,maximum,high:base-minimum,low:base-maximum};
}
export function robotRounding(payload){return payload.quote_lines.reduce((sum,r)=>sum+((r.material_net||0)+(r.labor_net||0))*1.27,0)-payload.total_gross;}
