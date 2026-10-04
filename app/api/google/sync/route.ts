import { NextResponse } from "next/server";
import { getGoogleAccessToken } from "@/lib/google";
import { serviceSupabase, verifyStaffToken } from "@/lib/supabase-server";

export async function POST(req: Request) {
  try {
    const auth = req.headers.get("authorization") || "";
    if (!auth.startsWith("Bearer ")) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
    const { user } = await verifyStaffToken(auth.slice(7));
    const body = await req.json() as { eventId: string };
    if (!body.eventId) throw new Error("eventId_required");

    const db = serviceSupabase();
    const { data: event, error: eventError } = await db.from("events").select("*").eq("id", body.eventId).single();
    if (eventError || !event) throw new Error("Event not found.");
    if (!event.end_at) throw new Error("Informe o horário de término antes de sincronizar.");

    const { data: client } = await db.from("clients").select("trade_name").eq("id", event.client_id).maybeSingle();
    const { data: services } = await db.from("event_services").select("id,quantity_needed").eq("event_id", event.id);
    const serviceIds = (services || []).map((s) => s.id);
    let confirmed = 0;
    if (serviceIds.length) {
      const { data: assignments } = await db.from("assignments").select("status").in("event_service_id", serviceIds);
      confirmed = (assignments || []).filter((a) => ["confirmed", "checked_in", "checked_out"].includes(a.status)).length;
    }
    const needed = (services || []).reduce((n, s) => n + Number(s.quantity_needed || 0), 0);
    const accessToken = await getGoogleAccessToken(user.id);
    const payload = {
      summary: event.name,
      location: event.venue,
      description: [
        client?.trade_name ? `Cliente: ${client.trade_name}` : "",
        needed ? `Equipe: ${confirmed}/${needed} profissionais confirmados` : "Equipe ainda não configurada",
        event.notes ? `Observações: ${event.notes}` : "",
        "Gerenciado pelo EventCore · Marujo Eventos",
      ].filter(Boolean).join("\n"),
      start: { dateTime: event.start_at, timeZone: "America/Sao_Paulo" },
      end: { dateTime: event.end_at, timeZone: "America/Sao_Paulo" },
    };

    const base = "https://www.googleapis.com/calendar/v3/calendars/primary/events";
    const googleUrl = event.google_event_id ? `${base}/${encodeURIComponent(event.google_event_id)}` : base;
    const googleRes = await fetch(googleUrl, {
      method: event.google_event_id ? "PUT" : "POST",
      headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const googleData = await googleRes.json();
    if (!googleRes.ok || !googleData.id) throw new Error(googleData.error?.message || "Google Calendar rejected the event.");

    await db.from("events").update({
      google_calendar_id: "primary",
      google_event_id: googleData.id,
      calendar_sync_status: "synced",
      calendar_last_synced_at: new Date().toISOString(),
      calendar_last_error: null,
      updated_at: new Date().toISOString(),
    }).eq("id", event.id);

    return NextResponse.json({ ok: true, googleEventId: googleData.id, htmlLink: googleData.htmlLink });
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message : "sync_failed" }, { status: 400 });
  }
}
