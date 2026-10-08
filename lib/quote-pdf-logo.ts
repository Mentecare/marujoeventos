import sharp from 'sharp';
import type { SupabaseClient } from '@supabase/supabase-js';
import { serviceSupabase } from './supabase-server.ts';
import { PHOTO_MAX_BYTES, PROFILE_PHOTO_BUCKET } from './profile-photos.ts';

const uuid = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const storedAvatar = new RegExp(`^${uuid}/(${uuid})\\.webp$`, 'i');

/** Caller SQL authorizes the owner's avatar before privileged fixed-bucket read.
 * Never follow an image URL from a DTO/request, or read raw profile/photo tables.
 */
export async function quoteIssuerLogo(db: SupabaseClient, organizationId: string | null, storageClient = serviceSupabase): Promise<Buffer | null> {
  if (!organizationId) return null;
  try {
    const { data, error } = await db.rpc('get_provider_photo_collection', { p_organization_id: organizationId });
    if (error || !Array.isArray(data)) return null;
    const avatar = data.find(row => row.kind === 'avatar');
    const path = typeof avatar?.object_path === 'string' ? avatar.object_path : '';
    const matched = storedAvatar.exec(path);
    if (!matched || matched[1].toLowerCase() !== String(avatar.id).toLowerCase()) return null;
    const downloaded = await storageClient().storage.from(PROFILE_PHOTO_BUCKET).download(path);
    if (downloaded.error || !downloaded.data || !downloaded.data.size || downloaded.data.size > PHOTO_MAX_BYTES) return null;
    const bytes = Buffer.from(await downloaded.data.arrayBuffer());
    const image = sharp(bytes, { limitInputPixels: 40_000_000, failOn: 'warning' });
    const metadata = await image.metadata();
    if (metadata.format !== 'webp' || !metadata.width || !metadata.height || (metadata.pages || 1) > 1) return null;
    return await image.rotate().resize({ width: 320, height: 320, fit: 'inside', withoutEnlargement: true }).png().toBuffer();
  } catch {
    // Missing/inaccessible/corrupt optional branding must not hide an otherwise
    // authorized quote. The renderer uses the issuer name and neutral EC mark.
    return null;
  }
}
