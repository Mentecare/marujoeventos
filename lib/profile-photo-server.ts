import { createClient } from "@supabase/supabase-js";
import { serviceSupabase } from "@/lib/supabase-server";
import { PhotoError } from "@/lib/profile-photo-input";
import type { ProfilePhotoCollection } from "@/lib/profile-photos";

export const PROFILE_PHOTO_BUCKET = "eventcore-profile-photos";
export const PHOTO_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function photoActor(request: Request) {
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ") || authorization.length < 10) throw new PhotoError("unauthorized", 401);
  const token = authorization.slice(7);
  const admin = serviceSupabase();
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) throw new PhotoError("unauthorized", 401);
  const profile = await admin.from("profiles").select("id,active").eq("id", data.user.id).single();
  if (profile.error || !profile.data?.active) throw new PhotoError("forbidden", 403);
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!key) throw new PhotoError("photo_storage_unavailable", 503);
  const db = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, key, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
  return { id: data.user.id, db, admin };
}

export function photoRpcError(error: { message: string }) {
  const codes: Record<string, number> = { forbidden: 403, portfolio_full: 409, real_photo_declaration_required: 400, photo_not_found: 404, invalid_photo_kind: 400, invalid_photo_caption: 400, invalid_photo_object: 400 };
  throw new PhotoError(error.message in codes ? error.message : "photo_storage_unavailable", codes[error.message] || 503);
}

export async function drainPhotoCleanup(actor: Awaited<ReturnType<typeof photoActor>>) {
  const pending = await actor.admin.from("profile_photo_cleanup").select("object_path").eq("profile_id", actor.id).lte("not_before", new Date().toISOString()).order("not_before").limit(20);
  if (pending.error) { console.warn("profile_photo_cleanup_deferred"); return; }
  if (!pending.data?.length) return;
  const paths = pending.data.map(row => row.object_path as string);
  const active = await actor.admin.from("profile_photos").select("object_path").eq("profile_id", actor.id).in("object_path", paths);
  if (active.error) { console.warn("profile_photo_cleanup_deferred"); return; }
  const references = new Set(active.data.map(row => row.object_path));
  const disposable = paths.filter(path => !references.has(path));
  if (disposable.length) {
    const removed = await actor.admin.storage.from(PROFILE_PHOTO_BUCKET).remove(disposable);
    if (removed.error) { console.warn("profile_photo_cleanup_deferred"); return; }
  }
  const finished = await actor.admin.from("profile_photo_cleanup").delete().eq("profile_id", actor.id).in("object_path", paths);
  if (finished.error) console.warn("profile_photo_cleanup_deferred");
}

export async function signedPhotoCollection(actor: Awaited<ReturnType<typeof photoActor>>, freelancerId: string | null, organizationId: string | null = null): Promise<ProfilePhotoCollection> {
  const result = organizationId
    ? await actor.db.rpc("get_provider_photo_collection", { p_organization_id: organizationId })
    : await actor.db.rpc("get_profile_photo_collection", { p_freelancer_id: freelancerId });
  if (result.error) photoRpcError(result.error);
  const rows = (result.data || []) as { id: string; kind: "avatar" | "portfolio"; caption: string | null; object_path: string; created_at: string }[];
  if (!rows.length) return { avatar: null, portfolio: [] };
  const signed = await actor.admin.storage.from(PROFILE_PHOTO_BUCKET).createSignedUrls(rows.map(row => row.object_path), 1200);
  if (signed.error || signed.data?.length !== rows.length) throw new PhotoError("photo_storage_unavailable", 503);
  // One missing object must remain removable without disabling the rest of the collection.
  const photos = rows.map((row, index) => ({ id: row.id, kind: row.kind, caption: row.caption, created_at: row.created_at, url: signed.data![index].signedUrl || "" }));
  return { avatar: photos.find(photo => photo.kind === "avatar") || null, portfolio: photos.filter(photo => photo.kind === "portfolio") };
}

export function photoFailure(error: unknown) {
  const messages: Record<string, string> = {
    unauthorized: "Entre na sua conta para acessar as fotos.", forbidden: "Seu perfil não tem acesso a estas fotos.",
    photo_too_large: "Cada foto pode ter até 3 MB.", invalid_photo_format: "Selecione uma foto válida em JPEG, PNG ou WebP, sem animação.",
    invalid_photo_kind: "Selecione foto de perfil ou portfólio.", invalid_photo_caption: "A legenda pode ter até 160 caracteres.",
    real_photo_declaration_required: "Confirme que a foto é real e não foi gerada com IA.", portfolio_full: "Seu portfólio já tem 10 fotos. Remova uma antes de enviar outra.",
    photo_not_found: "A foto não foi encontrada no seu perfil.", invalid_photo_object: "Não foi possível confirmar o envio da foto. Tente novamente.",
    photo_storage_unavailable: "Não foi possível acessar as fotos agora. Tente novamente.",
  };
  const known = error instanceof PhotoError ? error : new PhotoError("photo_storage_unavailable", 503);
  return Response.json({ error: messages[known.code] || messages.photo_storage_unavailable, code: known.code }, { status: known.status, headers: { "Cache-Control": "private, no-store" } });
}
