import type { SupabaseClient } from '@supabase/supabase-js';

export type GoogleSyncDependencies = {
  verifyStaffToken: (token: string) => Promise<{ user: { id: string } }>;
  commercialActor: (request: Request) => Promise<{ id: string; db: SupabaseClient }>;
  serviceSupabase: () => SupabaseClient;
  getGoogleAccessToken: (userId: string) => Promise<string>;
  calendarFetch: typeof fetch;
};

/** Shared by the route and boundary tests; authorize before any privileged export dependency. */
export function createGoogleSyncHandler(deps: GoogleSyncDependencies) {
  return async function POST(req: Request) {
    try {
      const auth = req.headers.get('authorization') || '';
      if (!auth.startsWith('Bearer ') || !auth.slice(7).trim()) return Response.json({ error: 'unauthorized' }, { status: 401 });
      const { user } = await deps.verifyStaffToken(auth.slice(7));
      const body = await req.json() as { eventId?: string };
      if (typeof body.eventId !== 'string' || !body.eventId) throw new Error('eventId_required');

      const actor = await deps.commercialActor(req);
      if (actor.id !== user.id) return Response.json({ error: 'forbidden' }, { status: 403 });
      // A generic staff role/assigned-worker read is insufficient: this RPC checks event operations.
      const permission = await actor.db.rpc('get_event_operations', { p_event_id: body.eventId });
      if (permission.error || permission.data?.event?.id !== body.eventId) return Response.json({ error: 'forbidden' }, { status: 403 });

      const db = deps.serviceSupabase();
      const { data: event, error: eventError } = await db.from('events')
        .select('id,name,venue,notes,start_at,end_at,client_id,google_event_id').eq('id', body.eventId).single();
      if (eventError || !event) throw new Error('Event not found.');
      if (!event.end_at) throw new Error('Informe o horário de término antes de sincronizar.');

      const { data: client } = await db.from('clients').select('trade_name').eq('id', event.client_id).maybeSingle();
      const { data: services } = await db.from('event_services').select('id,quantity_needed').eq('event_id', event.id);
      const serviceIds = (services || []).map((service) => service.id);
      let confirmed = 0;
      if (serviceIds.length) {
        const { data: assignments } = await db.from('assignments').select('status').in('event_service_id', serviceIds);
        confirmed = (assignments || []).filter((assignment) => ['confirmed', 'checked_in', 'checked_out'].includes(assignment.status)).length;
      }
      const needed = (services || []).reduce((count, service) => count + Number(service.quantity_needed || 0), 0);
      const accessToken = await deps.getGoogleAccessToken(user.id);
      const payload = {
        summary: event.name,
        location: event.venue,
        description: [
          client?.trade_name ? `Cliente: ${client.trade_name}` : '',
          needed ? `Equipe: ${confirmed}/${needed} profissionais confirmados` : 'Equipe ainda não configurada',
          event.notes ? `Observações: ${event.notes}` : '',
          'Gerenciado pelo EventCore · Marujo Eventos',
        ].filter(Boolean).join('\n'),
        start: { dateTime: event.start_at, timeZone: 'America/Sao_Paulo' },
        end: { dateTime: event.end_at, timeZone: 'America/Sao_Paulo' },
      };
      const base = 'https://www.googleapis.com/calendar/v3/calendars/primary/events';
      const googleUrl = event.google_event_id ? `${base}/${encodeURIComponent(event.google_event_id)}` : base;
      const googleRes = await deps.calendarFetch(googleUrl, {
        method: event.google_event_id ? 'PUT' : 'POST',
        headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
      const googleData = await googleRes.json();
      if (!googleRes.ok || !googleData.id) throw new Error(googleData.error?.message || 'Google Calendar rejected the event.');

      await db.from('events').update({
        google_calendar_id: 'primary', google_event_id: googleData.id, calendar_sync_status: 'synced',
        calendar_last_synced_at: new Date().toISOString(), calendar_last_error: null, updated_at: new Date().toISOString(),
      }).eq('id', event.id);
      return Response.json({ ok: true, googleEventId: googleData.id, htmlLink: googleData.htmlLink });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'sync_failed';
      const status = message === 'unauthorized' ? 401 : message === 'forbidden' ? 403 :
        error instanceof Error && 'status' in error && typeof error.status === 'number' ? error.status : 400;
      return Response.json({ error: message }, { status });
    }
  };
}
