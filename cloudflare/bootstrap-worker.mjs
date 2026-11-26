// Migration bootstrap only. Replaced by the compiled EventCore app after backend validation.
// Never exposes backup rows or accepts operational writes.
export default {
 async fetch(request, env) {
  const headers={'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'};
  if(new URL(request.url).pathname==='/health' && request.method==='GET'){
   try { await env.EVENTCORE_DB.prepare('SELECT 1 AS ok').first(); return Response.json({service:'eventcore',status:'migration_pending',database:'connected',application_ready:false},{headers}); }
   catch { return Response.json({service:'eventcore',status:'unavailable',application_ready:false},{status:503,headers}); }
  }
  return new Response('EventCore: migração em preparação. A aplicação ainda não foi ativada neste endereço.',{status:503,headers:{...headers,'Content-Type':'text/plain; charset=utf-8','Retry-After':'3600'}});
 }
};
