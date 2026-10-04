import { NextResponse } from "next/server";
import { createState, googleAuthorizeUrl } from "@/lib/google";
import { verifyStaffToken } from "@/lib/supabase-server";

export async function POST(req: Request) {
  try {
    const auth = req.headers.get("authorization") || "";
    if (!auth.startsWith("Bearer ")) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
    const { user } = await verifyStaffToken(auth.slice(7));
    const authorizeUrl = googleAuthorizeUrl(createState(user.id), new URL(req.url).origin);
    return NextResponse.json({ authorizeUrl });
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message : "connect_failed" }, { status: 400 });
  }
}
