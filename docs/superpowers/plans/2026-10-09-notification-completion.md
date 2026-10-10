# EventCore Notification Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Completar avisos privados de pedidos e propostas e abrir o registro autorizado no comercial existente.

**Architecture:** Dois tipos adicionais de evento privado alimentam a fila existente. Predicados reutilizam a autorização financeira do comercial, com revalidação no envio. Aplicação e service worker aceitam apenas links internos exatos.

**Tech Stack:** PostgreSQL/Supabase, Next 15.5.27, TypeScript, testes Node 24 e engine PostgreSQL descartável.

**Spec:** `docs/superpowers/specs/2026-10-09-notification-completion.md`.

## Global Constraints

- Sem backfill histórico, alteração de dados originais ou novo serviço pago.
- Sem envio externo a destinatário não identificado pelo usuário; agendamento permanece desativado até prova controlada dos canais.
- Nenhuma mudança visual além do destino e foco dos links.
- Preservar PR10 e qualquer mudança posterior; publicar somente revisão verificada.

## Review Focus

- Coordenador operacional sem autorização financeira: não recebe nem abre dados comerciais.
- Proposta em rascunho ou cliente externo: sem divulgação.
- Autorização revogada/conta inativa durante lease: envio bloqueado na revalidação existente.
- Proposta expirada ou pedido encerrado: sem novo envio; deduplicação preservada.
- Link manipulado/redirecionamento: rejeitado pelo aplicativo e pelo service worker.

### Task 1: Avisos comerciais de ponta a ponta

**Files:** migration aditiva criada por `supabase migration new eventcore_commercial_notifications`; `lib/notifications.ts`; `public/sw.js`; `app/page.tsx`; `app/components/commercial-workspace.tsx`; `tests/notifications.test.mjs`; `tests/notification-sw.test.mjs`; `tests/commercial-notifications.sql`; evidências em `docs/superpowers/validation/2026-10-09-notification-completion.md`.

**Interfaces:** Consumir `create_contract_request`, `submit_sale_quote`, `get_commercial_workspace`, `eventcore_notification_allowed`, `eventcore_enqueue_notification` e dispatcher existentes. Produzir tipos privados `request`/`proposal` com links `/?request=<UUID>`/`/?proposal=<UUID>`, sem campos privados no DTO.

- [ ] Testes RED: novos links rejeitados antes da correção; novo pedido sem aviso antes da migração.
- [ ] Migração: referências nullable indexadas, tipos adicionais, destinatários e estados atuais, gatilhos sem backfill; nenhum grant público das funções privadas.
- [ ] Links: aceitar apenas os dois novos alvos exatos e resolver registro pela consulta autorizada; artigos com IDs/foco.
- [ ] GREEN: unidades, SQL de isolamento/deduplicação/expiração/revogação e regressões existentes; build/typecheck e navegação dos links em teste local, identificando transporte isolado.
- [ ] Uma revisão independente final, limitada ao diff desta correção; corrigir achados confirmados e testar suas consequências.
- [ ] Aplicar migração verificada, preservar histórico de versões, publicar SHA comprovado, repetir jornada real HTTPS e confirmar limpeza/preservação dos fixtures.
- [ ] Registrar produção pronta para push, dependência real de e-mail/dispositivo/contas de navegador e agendamento ainda condicionado; nenhum envio simulado declarado real.

Execução nativa autorizada pelo usuário; a preferência por execução imediata prevalece sobre nova confirmação de planejamento. Baseline remoto conferido em main `cea9a61`; PR10 permanece draft em `483a163` e sua árvore coincide com o checkout inicial `0520301`.
