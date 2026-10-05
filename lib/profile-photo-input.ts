import sharp from "sharp";
import { PHOTO_MAX_BYTES } from "./profile-photos.ts";
export { PHOTO_MAX_BYTES } from "./profile-photos.ts";

export class PhotoError extends Error {
  code: string;
  status: number;
  constructor(code: string, status = 400) { super(code); this.code = code; this.status = status; }
}

export function validatePhotoFields(kind: unknown, caption: unknown, declaration: unknown) {
  if (kind !== "avatar" && kind !== "portfolio") throw new PhotoError("invalid_photo_kind");
  if (declaration !== "true") throw new PhotoError("real_photo_declaration_required");
  if (typeof caption !== "string" || caption.trim().length > 160) throw new PhotoError("invalid_photo_caption");
  return { kind, caption: caption.trim() || null } as { kind: "avatar" | "portfolio"; caption: string | null };
}

export async function normalizeProfilePhoto(bytes: Buffer, mime: string): Promise<Buffer> {
  if (!bytes.length || bytes.length > PHOTO_MAX_BYTES) throw new PhotoError("photo_too_large", 413);
  const formats: Record<string, string> = { "image/jpeg": "jpeg", "image/png": "png", "image/webp": "webp" };
  if (!formats[mime]) throw new PhotoError("invalid_photo_format");
  try {
    const input = sharp(bytes, { limitInputPixels: 40_000_000, failOn: "warning" });
    const metadata = await input.metadata();
    if (metadata.format !== formats[mime] || !metadata.width || !metadata.height || (metadata.pages || 1) > 1) throw new PhotoError("invalid_photo_format");
    if (metadata.format === "png") {
      for (let offset = 8; offset + 12 <= bytes.length;) {
        const size = bytes.readUInt32BE(offset);
        if (size > bytes.length - offset - 12) throw new PhotoError("invalid_photo_format");
        const chunk = bytes.toString("ascii", offset + 4, offset + 8);
        if (chunk === "acTL") throw new PhotoError("invalid_photo_format");
        if (chunk === "IEND") break;
        offset += size + 12;
      }
    }
    const output = await input.rotate().resize({ width: 1600, height: 1600, fit: "inside", withoutEnlargement: true }).webp({ quality: 85 }).toBuffer();
    if (output.length > PHOTO_MAX_BYTES) throw new PhotoError("photo_too_large", 413);
    return output;
  } catch (error) {
    if (error instanceof PhotoError) throw error;
    throw new PhotoError("invalid_photo_format");
  }
}

export async function boundedPhotoForm(request: Request): Promise<FormData> {
  const maximum = PHOTO_MAX_BYTES + 65_536;
  if (Number(request.headers.get("content-length")) > maximum) throw new PhotoError("photo_too_large", 413);
  const reader = request.body?.getReader();
  if (!reader) throw new PhotoError("invalid_photo_format");
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      size += part.value.length;
      // Stop buffering at the limit; Next owns the HTTP transport lifecycle.
      if (size > maximum) throw new PhotoError("photo_too_large", 413);
      chunks.push(part.value);
    }
    return await new Response(Buffer.concat(chunks), { headers: { "Content-Type": request.headers.get("content-type") || "" } }).formData();
  } catch (error) {
    if (error instanceof PhotoError) throw error;
    throw new PhotoError("invalid_photo_format");
  } finally { reader.releaseLock(); }
}
