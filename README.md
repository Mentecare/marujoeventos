# EventCore — Marujo Eventos

Versão de produção permanente em **Vercel + Supabase**, sem dependência do Floot.

## Arquitetura

- **Vercel / Next.js**: frontend, PWA e rotas de servidor.
- **Supabase EventCore**: Auth, banco, RLS e dados operacionais.
- **Google Calendar API**: OAuth próprio do EventCore, com tokens criptografados no Supabase e nunca expostos no navegador.

Supabase existente:
- Project ref: `mzwlchgxkuqptiqyznqd`
- URL: `https://mzwlchgxkuqptiqyznqd.supabase.co`

A migration de credenciais Google já foi aplicada no Supabase real e está versionada em `supabase/migrations`.

## Variáveis da Vercel

Configure sem commitar segredos:

```text
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
SUPABASE_SERVICE_ROLE_KEY
GOOGLE_CLIENT_ID
GOOGLE_CLIENT_SECRET
GOOGLE_OAUTH_STATE_SECRET
GOOGLE_TOKEN_ENCRYPTION_KEY
NEXT_PUBLIC_APP_URL
```

O navegador recebe somente as variáveis `NEXT_PUBLIC_*`. Service role e credenciais Google ficam exclusivamente no servidor.

## Google Cloud

Ative Google Calendar API, configure OAuth Web e use como redirect:

```text
https://SEU-DOMINIO/api/google/callback
```

Escopos pedidos: `openid`, `email` e `https://www.googleapis.com/auth/calendar.events`.

## Fluxos

Login, Admin/Coordenador, clientes, profissionais, eventos, necessidades por função, escala, portal do freelancer, check-in/out com geolocalização pontual, financeiro, pagamentos, PWA e Google Calendar idempotente por `google_event_id`.

## Deploy

Importe este repositório na Vercel, configure as variáveis de ambiente e faça o deploy. Depois ajuste `NEXT_PUBLIC_APP_URL` para o domínio final e use o mesmo domínio na Redirect URI do Google OAuth.
