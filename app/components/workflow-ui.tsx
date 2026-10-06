"use client";
import {useRef,useState} from 'react';
export const money=(value:number|null|undefined)=>value==null?'Valor não informado':Number(value).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
export const calendarDate=(value:string)=>value.slice(0,10).split('-').reverse().join('/');
export const workDate=(value:string)=>new Date(value).toLocaleString('pt-BR',{dateStyle:'short',timeStyle:'short'});
export function useMutation(refresh:()=>Promise<void>){
 const lock=useRef(false);const [busy,setBusy]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState('');
 async function run(work:()=>Promise<unknown>,message='Salvo.'){if(lock.current)return false;lock.current=true;setBusy(true);setError('');setNotice('');let committed=false;try{await work();committed=true;setNotice(message);await refresh();return true}catch(e){setError(e instanceof Error?e.message:String(e));return committed}finally{lock.current=false;setBusy(false)}}
 return {busy,run,feedback:<>{error&&<p className="error" role="alert">{error}</p>}{notice&&<p className="notice" role="status">{notice}</p>}</>};
}
