import fs from "node:fs";

function replaceOrThrow(path, from, to) {
  const input = fs.readFileSync(path, "utf8");
  if (!input.includes(from)) throw new Error("Expected source not found in " + path);
  fs.writeFileSync(path, input.replace(from, to));
}

replaceOrThrow(
  "app/page.tsx",
  '<button className="btn secondary" onClick={refresh} disabled={busy}>Atualizar</button></div></header>',
  '<button className="btn secondary" onClick={refresh} disabled={busy}>Atualizar</button><button className="btn secondary" onClick={logout}>Sair da conta</button></div></header>'
);

replaceOrThrow(
  "lib/google.ts",
  'export function googleAuthorizeUrl(state: string) {\n  const clientId = process.env.GOOGLE_CLIENT_ID;\n  const appUrl = process.env.NEXT_PUBLIC_APP_URL;\n  if (!clientId || !appUrl) throw new Error("Google OAuth is not configured.");',
  'export function googleAuthorizeUrl(state: string, requestOrigin?: string) {\n  const clientId = process.env.GOOGLE_CLIENT_ID;\n  const appUrl = process.env.NEXT_PUBLIC_APP_URL || requestOrigin;\n  if (!clientId) throw new Error("GOOGLE_CLIENT_ID is not configured in Vercel Production.");\n  if (!appUrl) throw new Error("NEXT_PUBLIC_APP_URL is not configured and request origin was unavailable.");'
);

replaceOrThrow(
  "lib/google.ts",
  'export async function exchangeCode(code: string) {\n  const clientId = process.env.GOOGLE_CLIENT_ID;\n  const clientSecret = process.env.GOOGLE_CLIENT_SECRET;\n  const appUrl = process.env.NEXT_PUBLIC_APP_URL;\n  if (!clientId || !clientSecret || !appUrl) throw new Error("Google OAuth is not configured.");',
  'export async function exchangeCode(code: string, requestOrigin?: string) {\n  const clientId = process.env.GOOGLE_CLIENT_ID;\n  const clientSecret = process.env.GOOGLE_CLIENT_SECRET;\n  const appUrl = process.env.NEXT_PUBLIC_APP_URL || requestOrigin;\n  if (!clientId) throw new Error("GOOGLE_CLIENT_ID is not configured in Vercel Production.");\n  if (!clientSecret) throw new Error("GOOGLE_CLIENT_SECRET is not configured in Vercel Production.");\n  if (!appUrl) throw new Error("NEXT_PUBLIC_APP_URL is not configured and request origin was unavailable.");'
);

replaceOrThrow(
  "app/api/google/connect/route.ts",
  'const authorizeUrl = googleAuthorizeUrl(createState(user.id));',
  'const authorizeUrl = googleAuthorizeUrl(createState(user.id), new URL(req.url).origin);'
);

replaceOrThrow(
  "app/api/google/callback/route.ts",
  'const token = await exchangeCode(code);',
  'const token = await exchangeCode(code, url.origin);'
);

fs.mkdirSync("app/api/google/config-status", { recursive: true });
fs.writeFileSync("app/api/google/config-status/route.ts", `import { NextResponse } from "next/server";

export async function GET() {
  return NextResponse.json({
    googleClientId: Boolean(process.env.GOOGLE_CLIENT_ID),
    googleClientSecret: Boolean(process.env.GOOGLE_CLIENT_SECRET),
    appUrl: Boolean(process.env.NEXT_PUBLIC_APP_URL),
    oauthStateSecret: Boolean(process.env.GOOGLE_OAUTH_STATE_SECRET),
    tokenEncryptionKey: Boolean(process.env.GOOGLE_TOKEN_ENCRYPTION_KEY),
    supabaseServiceRole: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY),
  });
}
`);

console.log("EventCore production patch applied.");
