import { randomUUID } from "node:crypto";
import { boundedPhotoForm, normalizeProfilePhoto, PhotoError, validatePhotoFields } from "@/lib/profile-photo-input";
import { PHOTO_MAX_BYTES } from "@/lib/profile-photos";
import { drainPhotoCleanup, photoActor, photoFailure, photoRpcError, PHOTO_UUID, PROFILE_PHOTO_BUCKET, signedPhotoCollection } from "@/lib/profile-photo-server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
const headers = { "Cache-Control": "private, no-store" };

export async function GET(request: Request) {
  try {
    const actor = await photoActor(request);
    await drainPhotoCleanup(actor);
    const id = new URL(request.url).searchParams.get("freelancer_id");
    if (id !== null && !PHOTO_UUID.test(id)) throw new PhotoError("photo_not_found", 404);
    return Response.json(await signedPhotoCollection(actor, id), { headers });
  } catch (error) { return photoFailure(error); }
}

export async function POST(request: Request) {
  try {
    const actor = await photoActor(request);
    const fields = await boundedPhotoForm(request);
    const { kind, caption } = validatePhotoFields(fields.get("kind"), fields.get("caption") || "", fields.get("real_declaration"));
    const file = fields.get("photo");
    if (!(file instanceof File)) throw new PhotoError("invalid_photo_format");
    if (file.size > PHOTO_MAX_BYTES) throw new PhotoError("photo_too_large", 413);
    const output = await normalizeProfilePhoto(Buffer.from(await file.arrayBuffer()), file.type);
    const id = randomUUID();
    const objectPath = `${actor.id}/${id}.webp`;
    const bucket = actor.admin.storage.from(PROFILE_PHOTO_BUCKET);
    // A grace period keeps other requests from cleaning an upload that is still in flight.
    const stage = await actor.admin.from("profile_photo_cleanup").insert({ object_path: objectPath, profile_id: actor.id, not_before: new Date(Date.now() + 15 * 60_000).toISOString() });
    if (stage.error) throw new PhotoError("photo_storage_unavailable", 503);
    const upload = await bucket.upload(objectPath, output, { contentType: "image/webp", upsert: false, cacheControl: "1200" });
    if (upload.error) {
      await actor.admin.from("profile_photo_cleanup").update({ not_before: new Date().toISOString() }).eq("object_path", objectPath).eq("profile_id", actor.id);
      await drainPhotoCleanup(actor);
      throw new PhotoError("photo_storage_unavailable", 503);
    }
    const saved = await actor.db.rpc("save_profile_photo", { p_photo_id: id, p_kind: kind, p_caption: caption, p_real_declared: true });
    if (saved.error) {
      // A lost RPC response may follow a committed transaction. Preserve that committed photo.
      const confirmed = await actor.admin.from("profile_photos").select("id").eq("profile_id", actor.id).eq("id", id).maybeSingle();
      if (!confirmed.data) {
        await actor.admin.from("profile_photo_cleanup").update({ not_before: new Date().toISOString() }).eq("object_path", objectPath).eq("profile_id", actor.id);
        await drainPhotoCleanup(actor);
        photoRpcError(saved.error);
      }
    }
    await drainPhotoCleanup(actor);
    return Response.json({ id, kind }, { status: 201, headers });
  } catch (error) { return photoFailure(error); }
}

export async function DELETE(request: Request) {
  try {
    const actor = await photoActor(request);
    const id = new URL(request.url).searchParams.get("photo_id");
    if (!id || !PHOTO_UUID.test(id)) throw new PhotoError("photo_not_found", 404);
    const row = await actor.db.from("profile_photos").select("id,object_path").eq("id", id).eq("profile_id", actor.id).maybeSingle();
    if (row.error) throw new PhotoError("photo_storage_unavailable", 503);
    // Deletion is idempotent. Never accept a client-provided storage path.
    if (row.data) {
      const removed = await actor.db.rpc("delete_profile_photo", { p_photo_id: id });
      if (removed.error) photoRpcError(removed.error);
    }
    await drainPhotoCleanup(actor);
    return Response.json({ removed: true }, { headers });
  } catch (error) { return photoFailure(error); }
}
