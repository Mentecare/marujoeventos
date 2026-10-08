export type DocumentType='cpf'|'cnpj';
export function normalizeDocument(type:DocumentType,value:string){return value.toUpperCase().replace(/[.\/\-\s]/g,'')}
export function validateDocument(type:DocumentType,value:string){
  const c=normalizeDocument(type,value);
  if(type==='cpf'){
    if(!/^\d{11}$/.test(c)||/^(\d)\1+$/.test(c))return false;
    const digit=(base:string,start:number)=>{let sum=0;for(const n of base)sum+=Number(n)*start--;const rest=(sum*10)%11;return rest===10?0:rest};
    return digit(c.slice(0,9),10)===Number(c[9])&&digit(c.slice(0,10),11)===Number(c[10]);
  }
  if(!/^[A-Z0-9]{12}\d{2}$/.test(c)||/^(\d)\1+$/.test(c))return false;
  const digit=(base:string,weights:number[])=>{const sum=[...base].reduce((a,n,i)=>a+(n.charCodeAt(0)-48)*weights[i],0);return sum%11<2?0:11-sum%11};
  const d1=digit(c.slice(0,12),[5,4,3,2,9,8,7,6,5,4,3,2]);
  return d1===Number(c[12])&&digit(c.slice(0,12)+d1,[6,5,4,3,2,9,8,7,6,5,4,3,2])===Number(c[13]);
}

/** Check-digit validity only: this is not a Receita identity verification. */
export function parseDocument(value: string): { type: DocumentType; number: string } | null {
  const number = normalizeDocument('cnpj', value);
  const type: DocumentType = number.length === 11 ? 'cpf' : 'cnpj';
  return validateDocument(type, number) ? { type, number } : null;
}
