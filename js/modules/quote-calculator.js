const value = n => Number.isFinite(Number(n)) ? Number(n) : 0;
export function calculateItem(item) {
  const multiplier = value(item.quantity1) * (item.unit2 ? value(item.quantity2) : 1);
  const material = multiplier * value(item.material_unit);
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
