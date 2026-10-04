import { createClient } from "@supabase/supabase-js";

export function serviceSupabase() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("Supabase server credentials are not configured.");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

export async function verifyStaffToken(token: string) {
  const db = serviceSupabase();
  const { data: userData, error: userError } = await db.auth.getUser(token);
  if (userError || !userData.user) throw new Error("unauthorized");

  const { data: profile, error: profileError } = await db
    .from("profiles")
    .select("id,role,active")
    .eq("id", userData.user.id)
    .single();

  if (profileError || !profile?.active || !["admin", "coordinator"].includes(profile.role)) {
    throw new Error("forbidden");
  }
  return { user: userData.user, profile };
}
