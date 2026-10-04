import { NextResponse } from "next/server";
import { exchangeCode, fetchGoogleEmail, saveGoogleConnection, verifyState } from "@/lib/google";

export async function GET(req: Request) {
  const url = new URL(req.url);
  const appUrl = process.env.NEXT_PUBLIC_APP_URL || url.origin;
  try {
    const code = url.searchParams.get("code");
    const state = url.searchParams.get("state");
    const error = url.searchParams.get("error");
    if (error) throw new Error(error);
    if (!code || !state) throw new Error("missing_oauth_data");
    const { userId } = verifyState(state);
    const token = await exchangeCode(code, url.origin);
    const email = await fetchGoogleEmail(token.access_token);
    await saveGoogleConnection(userId, email, token);
    return NextResponse.redirect(`${appUrl}/?google=connected`);
  } catch (e) {
    const msg = encodeURIComponent(e instanceof Error ? e.message : "google_oauth_failed");
    return NextResponse.redirect(`${appUrl}/?google=error&message=${msg}`);
  }
}
