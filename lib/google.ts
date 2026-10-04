import crypto from "crypto";
import { serviceSupabase } from "./supabase-server";

const CALENDAR_SCOPE = "https://www.googleapis.com/auth/calendar.events";

function stateSecret() {
  const secret = process.env.GOOGLE_OAUTH_STATE_SECRET;
  if (!secret) throw new Error("GOOGLE_OAUTH_STATE_SECRET is not configured.");
  return secret;
}

function encryptionKey() {
  const raw = process.env.GOOGLE_TOKEN_ENCRYPTION_KEY;
  if (!raw) throw new Error("GOOGLE_TOKEN_ENCRYPTION_KEY is not configured.");
  const key = /^[0-9a-f]{64}$/i.test(raw) ? Buffer.from(raw, "hex") : Buffer.from(raw, "base64");
  if (key.length !== 32) throw new Error("GOOGLE_TOKEN_ENCRYPTION_KEY must be 32 bytes.");
  return key;
}

export function createState(userId: string) {
  const payload = Buffer.from(JSON.stringify({ userId, exp: Date.now() + 10 * 60_000 })).toString("base64url");
  const sig = crypto.createHmac("sha256", stateSecret()).update(payload).digest("base64url");
  return `${payload}.${sig}`;
}

export function verifyState(state: string) {
  const [payload, sig] = state.split(".");
  if (!payload || !sig) throw new Error("invalid_state");
  const expected = crypto.createHmac("sha256", stateSecret()).update(payload).digest("base64url");
  if (!crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) throw new Error("invalid_state");
  const parsed = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as { userId: string; exp: number };
  if (!parsed.userId || parsed.exp < Date.now()) throw new Error("expired_state");
  return parsed;
}

export function googleAuthorizeUrl(state: string, requestOrigin?: string) {
  const clientId = process.env.GOOGLE_CLIENT_ID;
  const appUrl = process.env.NEXT_PUBLIC_APP_URL || requestOrigin;
  if (!clientId) throw new Error("GOOGLE_CLIENT_ID is not configured in Vercel Production.");
  if (!appUrl) throw new Error("NEXT_PUBLIC_APP_URL is not configured and request origin was unavailable.");
  const params = new URLSearchParams({
    client_id: clientId,
    redirect_uri: `${appUrl}/api/google/callback`,
    response_type: "code",
    scope: `openid email ${CALENDAR_SCOPE}`,
    access_type: "offline",
    prompt: "consent",
    include_granted_scopes: "true",
    state,
  });
  return `https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}`;
}

function encrypt(value: string) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", encryptionKey(), iv);
  const encrypted = Buffer.concat([cipher.update(value, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, encrypted]).toString("base64");
}

function decrypt(value: string) {
  const raw = Buffer.from(value, "base64");
  const iv = raw.subarray(0, 12);
  const tag = raw.subarray(12, 28);
  const encrypted = raw.subarray(28);
  const decipher = crypto.createDecipheriv("aes-256-gcm", encryptionKey(), iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(encrypted), decipher.final()]).toString("utf8");
}

export async function exchangeCode(code: string, requestOrigin?: string) {
  const clientId = process.env.GOOGLE_CLIENT_ID;
  const clientSecret = process.env.GOOGLE_CLIENT_SECRET;
  const appUrl = process.env.NEXT_PUBLIC_APP_URL || requestOrigin;
  if (!clientId) throw new Error("GOOGLE_CLIENT_ID is not configured in Vercel Production.");
  if (!clientSecret) throw new Error("GOOGLE_CLIENT_SECRET is not configured in Vercel Production.");
  if (!appUrl) throw new Error("NEXT_PUBLIC_APP_URL is not configured and request origin was unavailable.");

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: clientId,
      client_secret: clientSecret,
      redirect_uri: `${appUrl}/api/google/callback`,
      grant_type: "authorization_code",
    }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error_description || data.error || "Google token exchange failed.");
  return data as { access_token: string; expires_in: number; refresh_token?: string; scope?: string; token_type: string };
}

export async function fetchGoogleEmail(accessToken: string) {
  const res = await fetch("https://www.googleapis.com/oauth2/v2/userinfo", {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  const data = await res.json();
  if (!res.ok || !data.email) throw new Error("Could not read Google account email.");
  return data.email as string;
}

export async function saveGoogleConnection(userId: string, email: string, token: Awaited<ReturnType<typeof exchangeCode>>) {
  if (!token.refresh_token) throw new Error("Google did not return a refresh token. Revoke the old consent and reconnect.");
  const scopes = (token.scope || "").split(" ").filter(Boolean);
  if (!scopes.some((s) => s.includes("calendar"))) throw new Error("Google Calendar permission was not granted.");
  const db = serviceSupabase();
  const { error } = await db.from("google_oauth_connections").upsert({
    user_id: userId,
    email,
    refresh_token_enc: encrypt(token.refresh_token),
    access_token_enc: encrypt(token.access_token),
    access_expires_at: new Date(Date.now() + token.expires_in * 1000).toISOString(),
    scopes,
    updated_at: new Date().toISOString(),
  });
  if (error) throw error;

  await db.from("integrations").upsert({
    kind: "google_calendar",
    account_email: email,
    status: "connected",
    connected_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    updated_by: userId,
  }, { onConflict: "kind" });
}

async function refreshAccessToken(refreshToken: string) {
  const clientId = process.env.GOOGLE_CLIENT_ID;
  const clientSecret = process.env.GOOGLE_CLIENT_SECRET;
  if (!clientId || !clientSecret) throw new Error("Google OAuth is not configured.");
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      refresh_token: refreshToken,
      client_id: clientId,
      client_secret: clientSecret,
      grant_type: "refresh_token",
    }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error_description || data.error || "Google token refresh failed.");
  return data as { access_token: string; expires_in: number; scope?: string };
}

export async function getGoogleAccessToken(userId: string) {
  const db = serviceSupabase();
  const { data, error } = await db.from("google_oauth_connections").select("*").eq("user_id", userId).single();
  if (error || !data) throw new Error("Google Calendar is not connected.");
  const expiresAt = data.access_expires_at ? new Date(data.access_expires_at).getTime() : 0;
  if (data.access_token_enc && expiresAt > Date.now() + 60_000) return decrypt(data.access_token_enc);

  const refreshToken = decrypt(data.refresh_token_enc);
  const refreshed = await refreshAccessToken(refreshToken);
  await db.from("google_oauth_connections").update({
    access_token_enc: encrypt(refreshed.access_token),
    access_expires_at: new Date(Date.now() + refreshed.expires_in * 1000).toISOString(),
    updated_at: new Date().toISOString(),
  }).eq("user_id", userId);
  return refreshed.access_token;
}

export async function disconnectGoogle(userId: string) {
  const db = serviceSupabase();
  await db.from("google_oauth_connections").delete().eq("user_id", userId);
  await db.from("integrations").update({ status: "disconnected", updated_at: new Date().toISOString(), updated_by: userId }).eq("kind", "google_calendar");
}
