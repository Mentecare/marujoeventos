import { getGoogleAccessToken } from '@/lib/google';
import { serviceSupabase, verifyStaffToken } from '@/lib/supabase-server';
import { commercialActor } from '@/lib/actor-server';
import { createGoogleSyncHandler } from '@/lib/google-sync';

export const POST = createGoogleSyncHandler({
  verifyStaffToken, commercialActor, serviceSupabase, getGoogleAccessToken,
  calendarFetch: (input, init) => fetch(input, init),
});
