# EventCore — Marujo Eventos

## Atualização de perfis e oportunidades

Freelancer, responsável por equipe, empresa e agência têm navegação e indicadores próprios. Início e Dashboard são separados. Especialidades vêm do banco; CPF/CNPJ fica apenas na identificação privada. Usuários antigos completam o perfil na mesma conta.

As funções são configuradas somente na criação do evento. Cada função tem sua própria quantidade inteira de **dias de contratação**, começando em 1 para novos eventos. Os dias ficam visíveis nos detalhes, nas oportunidades e na escala do profissional. Funções antigas mantêm os dias como não informados. A quantidade de dias não multiplica os valores financeiros registrados.

Oportunidades usam uma projeção pública dos dados da vaga. Candidatura, contratação, presença, pagamento e avaliação passam por funções transacionais com verificação de perfil, organização, capacidade e status. Avaliações exigem evento concluído e presença validada; uma contratação recebe no máximo uma avaliação.

O código existente foi recuperado do snapshot de produção e agora fica diretamente versionado em `app`, `lib` e `public`. O build usa `next build` e não reconstrói arquivos binários. As rotas Google OAuth/Calendar e os nomes das variáveis existentes foram preservados.

### Desenvolvimento e validação

Use Node.js 24 e `npm ci`. Configure as variáveis de `.env.example` em `.env.local`, mantendo segredos fora do Git. Execute `npm test`, `npm run typecheck`, `npm run build` e `npm run dev`.

`tests/database-read.sql`, `tests/functions-creation-only.sql` e `tests/database-flow.sql` verificam permissões e o fluxo real usando transações com rollback. Execute apenas com a conexão administrativa do projeto correto. As migrações adaptativas anteriores estão espelhadas com suas versões já aplicadas; não as reaplique no projeto existente.

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
