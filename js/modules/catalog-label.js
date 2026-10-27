const normalizedName=value=>String(value??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('hu').replace(/[^a-z0-9]+/g,'');

export function catalogHasVariants(item,catalog){
 const key=item.comparison_key||normalizedName(item.subcategory);
 return catalog.some(other=>other.id!==item.id&&(other.comparison_key||normalizedName(other.subcategory))===key);
}

export function catalogDisplayName(item,catalog){
 if(!catalogHasVariants(item,catalog))return item.subcategory;
 const number=Number(item.price_variant)||1;
 const source=String(item.source||'').toLocaleLowerCase('hu').includes('munkalap')?'Munkalap ár':'jelenlegi ár';
 return `${number}. ${item.subcategory} · ${source}`;
}
