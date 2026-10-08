import { createClient } from '@supabase/supabase-js';

export class ActorError extends Error {
  readonly status: number;
  constructor(code: string, status: number) { super(code); this.status = status; }
}

/** The verified caller's JWT is retained for every query and RPC. No service-role client. */
export async function commercialActor(request: Request) {
  const authorization = request.headers.get('authorization');
  if (!authorization?.startsWith('Bearer ') || !authorization.slice(7).trim()) throw new ActorError('unauthorized', 401);
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) throw new ActorError('commercial_unavailable', 503);
  const db = createClient(url, key, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const { data, error } = await db.auth.getUser(authorization.slice(7));
  if (error || !data.user) throw new ActorError('unauthorized', 401);
  const profile = await db.from('profiles').select('id,active').eq('id', data.user.id).single();
  if (profile.error || !profile.data?.active) throw new ActorError('forbidden', 403);
  return { id: data.user.id, user: data.user, db };
}
