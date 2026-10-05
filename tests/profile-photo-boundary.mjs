import http from 'node:http';
import { randomUUID } from 'node:crypto';
import sharp from 'sharp';

// External Auth/PostgREST/Storage boundary only. API, image bytes and UI remain real.
export const PHOTO_OWNER='11111111-1111-4111-8111-111111111111';
export const PHOTO_OTHER='99999999-9999-4999-8999-999999999999';
export const PHOTO_FREELANCER='55555555-5555-4555-8555-555555555555';
export const PHOTO_SERVER_KEY='photo-test-server-only';
export function photoToken(id=PHOTO_OWNER) {
  return `${Buffer.from('{"alg":"HS256","typ":"JWT"}').toString('base64url')}.${Buffer.from(JSON.stringify({sub:id,aud:'authenticated',role:'authenticated',exp:Math.floor(Date.now()/1000)+3600})).toString('base64url')}.fixture`;
}
export async function startPhotoBoundary() {
  const objects=new Map(), photos=new Map(),cleanup=new Map();
  const state={objects,photos,cleanup,failSave:false,failRemove:false,failSign:false,loseSaveResponse:false,failDelete:false};
  const server=http.createServer(async(req,res)=>{
    try {
      const url=new URL(req.url,'http://127.0.0.1:18765');
      const chunks=[];for await(const chunk of req)chunks.push(chunk);const bytes=Buffer.concat(chunks);
      let body={};try{body=JSON.parse(bytes.toString())}catch{}
      const json=(value,status=200)=>{res.writeHead(status,{'content-type':'application/json','access-control-allow-origin':'*'});res.end(JSON.stringify(value))};
      const failure=(message,status=400)=>json({message,code:'P0001',error:message,statusCode:status},status);
      let actor=null;
      try{actor=JSON.parse(Buffer.from((req.headers.authorization||'').split('.')[1],'base64url').toString()).sub}catch{}
      if(url.pathname==='/auth/v1/user') {
        if(![PHOTO_OWNER,PHOTO_OTHER].includes(actor))return failure('Invalid JWT',401);
        return json({id:actor,aud:'authenticated',role:'authenticated',email:'photo-fixture@example.invalid'});
      }
      if(url.pathname==='/rest/v1/profiles')return json({id:url.searchParams.get('id')?.slice(3),active:true});
      if(url.pathname==='/rest/v1/profile_photos') {
        const target=url.searchParams.get('profile_id')?.slice(3);
        const rows=[...photos.values()].filter(row=>row.profile_id===target&&(req.headers.apikey===PHOTO_SERVER_KEY||row.profile_id===actor));
        if(url.searchParams.has('id'))return json(rows.find(row=>row.id===url.searchParams.get('id')?.slice(3))||null);
        return json(rows);
      }
      if(url.pathname==='/rest/v1/profile_photo_cleanup') {
        if(req.headers.apikey!==PHOTO_SERVER_KEY)return failure('service role required',403);
        const target=url.searchParams.get('profile_id')?.slice(3);
        if(req.method==='POST'){cleanup.set(body.object_path,body);return json(null,201);}
        if(req.method==='PATCH') {const row=cleanup.get(url.searchParams.get('object_path')?.slice(3));if(row?.profile_id===target)Object.assign(row,body);return json(null);}
        if(req.method==='DELETE') {for(const [path,row] of cleanup)if(row.profile_id===target&&url.searchParams.get('object_path')?.includes(path))cleanup.delete(path);return json(null);}
        return json([...cleanup.values()].filter(row=>row.profile_id===target&&new Date(row.not_before)<=new Date()));
      }
      if(url.pathname.startsWith('/rest/v1/rpc/')) {
        const rpc=url.pathname.split('/').at(-1);
        if(rpc==='get_profile_photo_collection') {
          if(body.p_freelancer_id&&body.p_freelancer_id!==PHOTO_FREELANCER)return failure('forbidden');
          const target=body.p_freelancer_id?PHOTO_OWNER:actor;
          return json([...photos.values()].filter(row=>row.profile_id===target).sort((a,b)=>a.slot-b.slot));
        }
        if(rpc==='save_profile_photo') {
          if(state.failSave)return failure('photo_storage_unavailable');
          const path=`${actor}/${body.p_photo_id}.webp`;
          if(!objects.has(path))return failure('invalid_photo_object');
          const own=[...photos.values()].filter(row=>row.profile_id===actor);
          if(body.p_kind==='portfolio'&&own.filter(row=>row.kind==='portfolio').length>=10)return failure('portfolio_full');
          const old=body.p_kind==='avatar'?own.find(row=>row.kind==='avatar'):null;
          if(old){photos.delete(old.id);cleanup.set(old.object_path,{object_path:old.object_path,profile_id:actor,not_before:new Date().toISOString()});}
          let slot=0;if(body.p_kind==='portfolio'){slot=1;while(own.some(row=>row.kind==='portfolio'&&row.slot===slot))slot++;}
          photos.set(body.p_photo_id,{id:body.p_photo_id,profile_id:actor,kind:body.p_kind,slot,object_path:path,caption:body.p_caption,created_at:new Date().toISOString()});
          cleanup.delete(path);
          if(state.loseSaveResponse)return failure('Lost RPC response',503);
          return json({id:body.p_photo_id,previous_object_path:old?.object_path||null});
        }
        if(rpc==='delete_profile_photo') {if(state.failDelete)return failure('Delete unavailable',503);const row=photos.get(body.p_photo_id);if(row?.profile_id===actor){photos.delete(row.id);cleanup.set(row.object_path,{object_path:row.object_path,profile_id:actor,not_before:new Date().toISOString()});}return json(null);}
      }
      const base='/storage/v1/object/';
      if(url.pathname.startsWith(base)) {
        if(req.method==='GET'&&url.pathname.startsWith(base+'sign/eventcore-profile-photos/')) {
          const path=decodeURIComponent(url.pathname.slice((base+'sign/eventcore-profile-photos/').length));
          const file=objects.get(path);if(!file)return failure('Not found',404);
          res.writeHead(200,{'content-type':'image/webp','access-control-allow-origin':'*'});res.end(file);return;
        }
        if(req.headers.apikey!==PHOTO_SERVER_KEY)return failure('server key required',403);
        if(req.method==='POST'&&url.pathname===base+'sign/eventcore-profile-photos') {
          if(state.failSign)return failure('sign unavailable',503);
          return json(body.paths.map(path=>({path,error:objects.has(path)?null:'not found',signedURL:objects.has(path)?`/object/sign/eventcore-profile-photos/${path}?token=fixture`:null})))
        }
        if(req.method==='POST'&&url.pathname.startsWith(base+'eventcore-profile-photos/')) {
          const path=decodeURIComponent(url.pathname.slice((base+'eventcore-profile-photos/').length));
          if(req.headers['content-type']!=='image/webp'||(await sharp(bytes).metadata()).format!=='webp')return failure('bad storage bytes');
          objects.set(path,bytes);return json({Id:randomUUID(),Key:`eventcore-profile-photos/${path}`});
        }
        if(req.method==='DELETE'&&url.pathname===base+'eventcore-profile-photos') {
          if(state.failRemove)return failure('remove unavailable',503);
          for(const path of body.prefixes)objects.delete(path);
          return json(body.prefixes.map(name=>({name})));
        }
      }
      return failure('Unexpected fixture request '+url.pathname,404);
    } catch(error) {res.writeHead(500,{'content-type':'application/json'});res.end(JSON.stringify({message:error.message}));}
  });
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(18765,'127.0.0.1',resolve)});
  return {...state,server,close:()=>new Promise(resolve=>server.close(resolve)),state};
}
