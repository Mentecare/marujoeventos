import { NextResponse } from "next/server";
import { disconnectGoogle } from "@/lib/google";
import { verifyStaffToken } from "@/lib/supabase-server";

export async function POST(req: Request) {
  try {
    const auth = req.headers.get("authorization") || "";
    if (!auth.startsWith("Bearer ")) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
    const { user } = await verifyStaffToken(auth.slice(7));
    await disconnectGoogle(user.id);
    return NextResponse.json({ disconnected: true });
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message : "disconnect_failed" }, { status: 400 });
  }
}
