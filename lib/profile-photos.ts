export const PROFILE_PHOTO_BUCKET = "eventcore-profile-photos";
export const PHOTO_MAX_BYTES = 3_000_000;
export const PORTFOLIO_LIMIT = 10;
export const PHOTO_ACCEPT = "image/jpeg,image/png,image/webp";
export type ProfilePhoto = { id: string; kind: "avatar" | "portfolio"; caption: string | null; url: string; created_at: string };
export type ProfilePhotoCollection = { avatar: ProfilePhoto | null; portfolio: ProfilePhoto[] };
export const EMPTY_PHOTOS: ProfilePhotoCollection = { avatar: null, portfolio: [] };
