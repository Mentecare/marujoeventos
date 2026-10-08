# EventCore — validação dos fluxos alinhados

Registro consolidado em 2026-10-08, incluindo a única rodada final de correções da revisão completa. Esta documentação preserva a evidência relevante das tarefas 1–6 sem depender da pasta temporária SDD. A aplicação usa o Supabase existente `mzwlchgxkuqptiqyznqd`, o projeto Vercel existente `prj_9eJO2JYCeB0458inwbIW0NhaXzsZ` e o domínio `eventcore.space`. Nenhum projeto foi substituído.

## Implementação e limites da evidência

| Fluxo / acesso | Evidência local já executada | Limite externo |
|---|---|---|
| Comprador solicita → fornecedor emite/revisa/envia → aceite cria contrato imutável → recibo | SQL autenticado/RLS e UI real com boundary de Auth/PostgREST | Novos RPCs ainda não estão no Supabase hospedado |
| Trabalho privado externo → equipe selecionada → convite → aceite de condições | SQL de remuneração/evidência e browser do fornecedor/profissional | Nenhuma convocação real foi enviada |
| Vaga pública → candidatura → contratação → pagamento registrado | SQL de autorização/publicação/pagamento e browser | Nenhuma vaga real publicada para gerar alertas gerais |
| Financeiro do fornecedor, salários próprios, comprador somente venda, coordenador sem/com autorização financeira | Projeções SQL com allowlists exatas, RLS/raw write/read negativo; browser para membro financeiro independente | Homologação HTTPS/JWT desses novos contratos ainda pendente |
| Documento CPF/CNPJ privado, histórico legado, equipes habituais versus alocações, avaliações por evidência | SQL e UI; regressão antes/depois para avaliações legadas com evento sem fim | Histórico hospedado não foi reclassificado nem recalculado |
| Google/galeria/navegação/layout aprovado | Testes anteriores reais de handlers/Next/browser com serviços externos isolados | Não prova OAuth/Calendar ou Storage hospedado reais |
| PDF autorizado e imagem do emitente | Tarefa 6: rota Next real, Auth/RPC/Storage HTTP isolados, PDFKit/Sharp/Poppler reais, browser 390/1280 | Vercel protegido e RPC ausente impedem prova de geração hospedada autenticada |
| Central/push/e-mail | SQL de outbox/RLS, SW; Tarefa 6: dispatcher Next real, adapters reais, criptografia Web Push real e provedores HTTP isolados | Sem envio externo, dispositivo físico, credenciais de entrega ou scheduler ativado |

SQL descartável usa PostgreSQL 17.5 com shims mínimos de Auth/Storage, papéis autenticados e transações com rollback. Isso verifica a execução PL/pgSQL, grants, RLS e invariantes; não equivale ao GoTrue/PostgREST/Storage hospedados. Browser testa a aplicação Next real e transporte, enquanto os serviços externos respondem com fixtures. Nenhum mock entra no produto.

## Verificações herdadas, sem repetição das suítes inalteradas

Os relatórios das tarefas anteriores foram lidos; os números abaixo são resultados herdados, não execuções novas da tarefa 6.

| Verificação | Resultado registrado |
|---|---|
| Tarefa 1, fundação comercial e isolamento | Cadeia inicial de 30 migrações; fixture comercial inicial 129 instruções, ampliado nas correções; fixtures de leitura/fotos 8 cada |
| Tarefa 2, fluxos e projeções | 31 migrações; `workflows-security.sql` 212 instruções, final 220 após preservação de avaliações sem fim; `commercial-security.sql` 176; leitura/fotos 8 cada |
| Tarefa 2, preservação antes/depois | 30 migrações prévias; fixture anterior 25, migração corrigida 108, fixture posterior 21; rollback. O predicate anterior falha a regressão |
| Tarefa 3, financeiro independente | 32 migrações; `interface-finance-security.sql` 58 instruções com rollback |
| Tarefa 3, browser | 15 jornadas buyer/provider/worker/coordinator/legacy em 360/390/1280; 102 combinações de rota/viewport. Correções finais rerodaram worker e finance nas três larguras, provider/coordinator/legacy em 390 |
| Tarefa 3, Google | Handler autoriza operações com JWT, falha fechado para ator/tenant incorreto; Next HTTP negado sem leitura privilegiada/exportação. Calendar/OAuth reais não chamados |
| Tarefa 4, notificações | 33 migrações; `notifications-security.sql` 139 instruções com rollback; 13 testes adapter/SW; browser worker/provider/coordinator/legacy em 390 |
| Tarefa 5, PDF anterior | 6 testes focados e 71 testes completos; typecheck/build/Poppler. Tarefa 6 corrige o logotipo, medidas/paginação e rastreamento de deploy dessa implementação |

Os fixtures cobrem comprador sem permissão de contratar freelancers, salário próprio versus colega/empresa, coordenador finance deny/grant, criador legado preservado, totais independentes, origem privada, avaliações sem métricas fabricadas, acesso anônimo negado, snapshots/recibos imutáveis, stale revision, aceite repetido e despesas desconhecidas. O exemplo financeiro testado tem venda 5.600, recebimento 1.000, recebível 4.600, mão de obra 4.400, pagamento 440, saldo 3.960; cada trabalhador vê somente seus 440. As despesas e impostos não são inventados.

Comandos reproduzíveis das suítes herdadas (dependem do validador descartável disponibilizado na sessão):

```text
node /workspace/scratch/0d27d86074e8/eventcore-sql-validator/validate.mjs "$PWD" tests/commercial-security.sql tests/workflows-security.sql
node /workspace/scratch/0d27d86074e8/eventcore-sql-validator/validate.mjs "$PWD" tests/interface-finance-security.sql
node /workspace/scratch/0d27d86074e8/eventcore-sql-validator/validate.mjs "$PWD" tests/notifications-security.sql
node tests/aligned-flows.browser.mjs
EVENTCORE_CHECK_ROLE=worker EVENTCORE_CHECK_WIDTH=390 node --experimental-strip-types tests/notifications.integration.mjs
node tests/google-sync.integration.mjs
```

Não se afirma que todos esses comandos foram repetidos contra a cadeia final na tarefa 6. Os testes standalone exigem Poppler, Chromium local e Playwright do runtime; o teste completo usual permanece `npm test`.

## Tarefa 6 — correções e evidência nova

`pdfkit@0.20.2` e `@types/pdfkit@0.17.5` foram instalados normalmente e fixados no lockfile. A instalação anterior bloqueada não foi tratada como justificativa para ignorar dependências. Documentação primária consultada: [texto/medidas](https://pdfkit.org/docs/text.html), [imagens](https://pdfkit.org/docs/images.html) e [páginas em buffer](https://pdfkit.org/docs/getting_started.html).

A imagem do emitente vem de `get_provider_photo_collection` com o JWT do leitor do orçamento. Só o avatar retornado pelo RPC, com caminho `UUID/UUID.webp` e ID correspondente, chega ao download privilegiado do bucket fixo `eventcore-profile-photos`. Não há leitura comercial com service role nem URL fornecida por usuário. Sharp decodifica WebP estático limitado a 3 MB/40 milhões de pixels, reduz para 320 e converte para PNG. Imagem ausente, inacessível ou inválida usa o nome completo do emitente e marca neutra EC; o orçamento continua autorizado. Não é um logotipo fictício da empresa.

O PDF mede fontes reais, quebra nomes/locais/condições e identificadores longos, mantém itens curtos juntos e divide uma descrição maior que a página sem perder seu fim. Reservas de largura suportam `R$ 9.999.999.999,99`. As opções somente totais/unitários conservam os totais do DTO de venda; campos internos adicionais são ignorados. Marca d'água e rodapé/número aparecem em cada página. Poppler confirmou A4, PDFs curtos de 1 página, 64 itens em 5 páginas e descrição de 180 repetições em 4 páginas. Inspeção visual incluiu todas as páginas extensas, total final, imagem e controles mobile; bbox verifica limites horizontais/verticais, e extração verifica texto final e privacidade.

A prévia é vinculada ao ID/revisão/permissão de unitários/opção atual. Mudanças invalidam o iframe e abortam solicitações antigas; uma resposta atrasada não reaparece nem baixa um PDF de opção anterior. Dashboard agora explica conclusão ou presença validada. A preferência push explica que a autorização deste aparelho ocorre no botão explícito; boot não pede permissão e recusa mantém central/e-mail disponíveis.

O teste de integração roda Auth/PostgREST/Storage em servidor HTTP local e Next real. Apenas transports dos provedores são substituídos por preload de teste. O Web Push SDK real criptografa e assina com VAPID sintético gerado somente em memória; o receiver de teste decripta o payload interceptado. E-mail exige ID de acknowledgment; sem ID retorna retry. Push 410 desativa dispositivo e suprime o batch. Nenhum teste contata destinatário real.

O primeiro build revelou que PDFKit era empacotado com `createRequire` apontando para caminho absoluto de scratch e nenhum arquivo PDFKit no trace. Uma asserção de deploy falhou. `serverExternalPackages:['pdfkit']` e inclusão estreita dos dados de fonte corrigem o pacote. A versão 0.20.2 usa módulos de métricas compiladas `standard-fonts/Helvetica*.cjs`; o trace também inclui os AFMs e os binários Sharp/libvips. Não há configuração Vercel/infrastrutura nova.

Resultados novos observados em RED antes da correção: texto final de descrição ausente, imagem ausente, prévia antiga visível após alternar opções, redação de conclusão incorreta, linha curta quebrada entre páginas e PDFKit ausente do trace. A primeira suíte completa falhou em `profile-portfolio.test.mjs`: seu loader CommonJS não resolvia o novo import compartilhado do bucket; a fixture agora carrega o módulo real. Nenhuma falha foi ocultada. Reexecuções finais ocorreram somente após esses problemas concretos.

Comandos finais e resultados:

```text
node --experimental-strip-types --test tests/quote-pdf.test.mjs tests/quote-pdf-logo.test.mjs tests/profile-portfolio.test.mjs
14/14 pass

node tests/quote-pdf.integration.mjs
PASS: actual Next route Auth 401 / tenant 404 / unit policy 400 / sale PDF 200
PASS: dispatcher ack / no-email-ack / expired through isolated provider transports
PASS: browser 390 and 1280 preview/download, options, revision and stale-request invalidation
PASS: worker dashboard/device authorization; no automatic prompt; push decline

env -u npm_config_http_proxy -u NPM_CONFIG_HTTP_PROXY npm test
76/76 pass; 0 fail/skip

env -u npm_config_http_proxy -u NPM_CONFIG_HTTP_PROXY \
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:18765 \
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=fixture-public \
NEXT_TELEMETRY_DISABLED=1 npm run build
Next 15.5.27 optimized build passed; PDF/internal dispatcher routes present

env -u npm_config_http_proxy -u NPM_CONFIG_HTTP_PROXY npm run typecheck
pass

node tests/pdf-deployment-trace.mjs
PASS: PDFKit package, compiled font modules, Helvetica/Helvetica-Bold AFMs,
native Sharp/libvips; every traced file exists; no absolute PDFKit build path

EVENTCORE_PDF_SERVER_MODE=production \
EVENTCORE_PDF_OUTPUT=/workspace/scratch/0d27d86074e8/eventcore-task6-evidence/production \
node tests/quote-pdf.integration.mjs
All 7 PASS lines above repeated against optimized next start (exit 0)

git diff --check
pass
```

Evidência local de execução/render: `/workspace/scratch/0d27d86074e8/eventcore-task6-evidence/`. Drivers e asserções permanecem versionados; PNGs/logs temporários não são prova hospedada nem arquivos de clientes reais.

## Supabase hospedado e publicação — leitura do controlador

Em 2026-10-07 02:18:04 UTC o controlador verificou **29 migrações aplicadas**, terminando em `20261005151147_eventcore_function_contract_days`. Os novos RPCs de quote/finance/central não existem. O controlador confirmou novamente em 2026-10-08 as mesmas **29 migrações aplicadas**. Cinco arquivos novos continuam pendentes, nesta ordem:

1. `20261005194714_eventcore_commercial_foundation.sql`
2. `20261006082244_eventcore_workflows_history.sql`
3. `20261006203715_eventcore_work_finance_index.sql`
4. `20261006204723_eventcore_notifications_public_sharing.sql`
5. `20261008022315_eventcore_final_flow_corrections.sql`

Contagens observadas: 3 eventos, 4 funções, 3 convocações, 3 pagamentos, 2 perfis; 0 organizações, propostas, itens de proposta e avaliações. Hashes das colunas originais observados nesse checkpoint:

| Tabela | Hash |
|---|---|
| events | `3886fd61be7f0a101f854ff62ac03c8e` |
| event_services | `d35d404f6db8d988adeffd5ec5bf0329` |
| assignments | `b1e762e605571ec24b471e3431ba1479` |
| payments | `61ec797ef141d716fac5ef1067eef9fb` |
| profiles | `910bb6a4a7ac734283bd9816f442b5dd` |

O controlador informou igualdade com seu checkpoint anterior; isso é preservação durante verificações de leitura, **não** comparação antes/depois de migração aplicada. Dados mudaram legitimamente em checkpoints antigos de 2026-10-06; não devem ser restaurados. Antes da aplicação real, tirar baseline atual imediatamente, comparar IDs/valores/contagens pelas colunas originais excluindo somente adições, e preservar mudanças concorrentes. Fixtures extensos devem usar BEGIN/ROLLBACK. Testes HTTPS com auth/org/rascunho isolados precisam cleanup por IDs estritos; evidência aceita/contrato/pagamento pode ser imutável e não deletável, inclusive pelo administrador.

O checkpoint remoto do controlador é [PR 9](https://github.com/Mentecare/marujoeventos/pull/9), draft/open/mergeable, head `bc8ad01ce20c5e3a3344a95238d19cf310ed5dc3`, base/main `f37f6b303269d739c84c947cf301d267b753560b`. Preview original `dpl_CrNNmus4TS7CkmwtiWbus98oqq7M` READY, target null, mesmo SHA: [preview](https://marujoeventos-jf2yvkv69-douglas-factory-project.vercel.app). Esse checkpoint precede as correções locais da tarefa 6. HTTP observado pelo controlador: raiz 200/shell EventCore, SW 200, vaga desconhecida 404. Fetch de PDF foi bloqueado por proteção Vercel (`401 deployment_authentication_required` após redirect), sem evidência de 401 da aplicação ou geração autorizada. Não há promoção de produção nem envio externo.

## Configuração pendente, ativação e recuperação

O controlador leu somente metadados, sem decriptar valores: 17 entradas originais Google/Supabase; em 02:22:16 UTC confirmou 18 entradas após adicionar apenas `NOTIFICATION_VAPID_SUBJECT=https://eventcore.space`, tipo plain, preview da branch `feature/eventcore-aligned-flows-20261005`. Chaves pública/privada VAPID, `NOTIFICATION_DISPATCH_SECRET`, `RESEND_API_KEY` e `NOTIFICATION_EMAIL_FROM` permanecem ausentes. É necessário remetente/domínio Resend verificado e dispositivo físico com consentimento, além da aplicação das migrações e prova HTTPS dos endpoints compatíveis. Não extrair credenciais existentes nem substituir por caixa pessoal.

A revisão automática rejeitou armazenar a nova chave privada VAPID no projeto Vercel: “persists a newly generated private VAPID credential in an external Vercel project; user has not explicitly authorized this exact secret and destination”. Nenhuma chave privada/dispatch foi salva nem foi usado bypass dessa rejeição. A autorização exata de armazenamento de novos segredos no preview original permanece uma dependência externa; ela não bloqueia os testes isolados.

A ativação do schema deve ser coordenada com UI/servidor compatíveis. O UI antigo de produção não fornece identificação/organização de fornecedor exigida por `create_event_with_services` e `valid_event_tenant`; aplicar o schema sozinho interromperia novas criações. Organizações antigas permanecem `unclassified`; histórico legítimo sem documento continua acessível e novas operações exigem complemento explícito CPF/CNPJ/classificação. Nunca atribuir eventos antigos a uma organização automaticamente ou multiplicar acordos históricos por dias desconhecidos.

Baseline de advisors anterior: cleanup RLS sem policies, 20 avisos de RPC definer autenticado, leaked-password protection desligada, 21 índices sem uso e 9 avisos de policies permissivas múltiplas. São achados anteriores a comparar após ativação, não autorização para reescrever infraestrutura/ACLs ou apagar índices. Tabelas de cleanup com acesso privilegiado e RPCs protegidos têm limites intencionais; nenhuma declaração de “advisors limpos” é feita.

Recuperação não destrutiva: parar novos callers, revogar EXECUTE somente dos novos RPCs mutantes/worker conforme revisão e manter snapshots, recibos, termos, pagamentos, confirmações, avaliações, colunas e RLS mais estrita. Salvar definições/ACLs/policies imediatamente antes de aplicar; uma migração aditiva de recuperação pode restaurar definições compatíveis individualmente revisadas. Não apagar dados/evidências, reabrir staff financeiro global ou freelancer ownership genérico, remover guards isoladamente nem reexecutar migrações antigas em massa. Finance index pode ser desativado nos callers e ter EXECUTE revogado sem mudar registros. Ver detalhes em [API comercial](2026-10-05-commercial-api.md).

Scheduler ainda não ativado. Após configuração e endpoint compatível verificado, o controlador pode usar `scripts/setup-notification-scheduler.sql` com ambiente seguro e Vault existente. `scripts/recover-notification-scheduler.sql` apenas remove a agenda nomeada e preserva preferências/outbox/receipts. Não zerar acknowledgments, repetir batches suprimidos em massa ou afirmar exactly-once: push é at least once e idempotência Resend tem retenção limitada. Ver [notificações e recovery](2026-10-06-notifications.md).

Revisão do branch inteiro, publicação do commit/tree final, novo preview homologável e verificação autenticada hospedada continuam sob responsabilidade do controlador. Esse registro não afirma merge/release de produção, migração aplicada, entrega real ou aprovação independente da tarefa 6.

## Correções da revisão da tarefa 6 — rodada 1

Sobre BASE `0833ae91584a486609e4770fc173d650a300385b`, o rodapé agora contém uma anotação URI explícita e fixa `https://eventcore.space` em cada página. Os testes PyMuPDF verificam uma anotação por página, seu retângulo no rodapé, PDF curto de totais/unitários e PDF de 64 itens. Antes da implementação: 6 testes passavam e 2 falhavam pela ausência do link. Depois: 8/8 passaram. A rota Next otimizada também verifica as anotações dos PDFs realmente retornados, mantendo totais e privacidade.

Reprodução atual: os drivers usam `tests/runtime-tools.mjs`. Sem override, Poppler (`pdfinfo`, `pdftotext`, `pdfimages`) e `python3` vêm do PATH, Playwright vem do módulo instalado `playwright`, e Chromium vem da instalação Playwright. Overrides opcionais explícitos: `EVENTCORE_PDFINFO`, `EVENTCORE_PDFTOTEXT`, `EVENTCORE_PDFIMAGES`, `EVENTCORE_PYTHON`, `EVENTCORE_PLAYWRIGHT_MODULE`, `EVENTCORE_CHROMIUM_EXECUTABLE`. Não há dependência de caminhos Codex no código versionado. Python precisa PyMuPDF 1.26.6; CI provisiona Node 24/Python 3.12, Poppler, PyMuPDF fixado e Playwright 1.62.1/Chromium. `EVENTCORE_PDF_OUTPUT`/`EVENTCORE_BROWSER_OUTPUT` selecionam evidência; defaults são temporários. Isso reproduz validação local, sem provisionar provedores/segredos. O relato anterior da rodada1 abaixo continua sendo evidência histórica do ambiente usado então.

O aviso `DEP0169` da execução otimizada vem de **web-push 3.6.7**, `generateRequestDetails` (`web-push-lib.js:274`, `url.parse`), seguido por `sendNotification` (também usa `url.parse` na linha 348). O stack real passa pelo chunk Next `598.js` e pelo adapter push. Em Node 24.19, a chamada direta dentro de `node_modules` é isenta desse aviso; `tests/web-push-deprecation-trace.mjs` avalia o mesmo código instalado, sem alteração, sob um nome de módulo de teste fora de `node_modules`, reproduzindo o empacotamento. O probe gera uma requisição criptografada com chaves sintéticas em memória e exige zero chamadas de rede. O warning permanece visível, sem supressão global ou patch upstream. A depreciação é uma dependência conhecida para avaliação de atualização do SDK; não causou erro nos cenários de acknowledgment/retry/410. O log também registra três `profile_photo_cleanup_deferred`: a fixture HTTP focada não implementa a tabela de cleanup acessada pelo shell; não é evidência de falha de cleanup hospedado.

Comandos cobrindo a rodada (todos os finais com exit 0):

```text
node --experimental-strip-types --test tests/quote-pdf.test.mjs
8/8 pass, incluindo link curto/multipágina, totais e layout

node --trace-deprecation tests/web-push-deprecation-trace.mjs
DEP0169 em WebPushLib.generateRequestDetails (...web-push-bundled-trace.cjs:274:29)
PASS: encrypted request produced; zero network calls

env -u npm_config_http_proxy -u NPM_CONFIG_HTTP_PROXY npm test
76 tests; 76 pass; 0 fail/cancelled/skip

env -u npm_config_http_proxy -u NPM_CONFIG_HTTP_PROXY \
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:18765 \
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=fixture-public \
NEXT_TELEMETRY_DISABLED=1 npm run build
Next 15.5.27: Compiled successfully; Generating static pages (8/8)

env -u npm_config_http_proxy -u NPM_CONFIG_HTTP_PROXY npm run typecheck
tsc --noEmit: pass

node tests/pdf-deployment-trace.mjs
PASS: PDFKit/Helvetica AFMs/compiled metrics/Sharp/libvips; every traced file exists

NODE_OPTIONS=--trace-deprecation EVENTCORE_PDF_SERVER_MODE=production \
EVENTCORE_CHROMIUM_EXECUTABLE=/workspace/scratch/0d27d86074e8/eventcore-browser-runtime/chromium \
EVENTCORE_PDF_OUTPUT=/workspace/scratch/0d27d86074e8/eventcore-task6-evidence/production-fix1 \
node tests/quote-pdf.integration.mjs
7 PASS: actual PDF route; dispatcher ack/no-email-ack/expired;
browser 390/1280; worker wording/device consent/decline

git diff --check
pass
```

A primeira integração da rodada passou rota e três cenários de dispatcher, mas Chromium sofreu SIGSEGV inclusive em `--version`. O binário fora do repo estava truncado (147032576 bytes; ELF exigia 209022176). Foi restaurado atomicamente do arquivo Brotli já fornecido em `eventcore-browser-tools/node_modules/@sparticuz/chromium/bin/chromium.br`, sem download/instalação/mudança de infraestrutura. O binário restaurado tem 209022176 bytes e responde `Chromium 153.0.8010.0`. Somente a integração afetada foi repetida; passou os sete cenários. A falha permanece em `integration-production-fix1-browser-failure.log` e `production-fix1/next-pdf-server-browser-failure.log`.

Evidência da rodada em `/workspace/scratch/0d27d86074e8/eventcore-task6-evidence/`: `unit-fix1.log`, `build-fix1.log`, `typecheck-fix1.log`, `sdk-deprecation-trace.log`, `integration-production-fix1.log`; PDFs, screenshots 390/1280 e log do servidor em `production-fix1/`. Mantêm as mesmas fronteiras isoladas de Auth/DB/Storage/provedores descritas acima, sem mensagens reais. Suites SQL/browser amplas inalteradas não foram repetidas. Em leitura do controlador de 2026-10-07 09:22:24 UTC, migrations/contagens/hashes continuam iguais, novo quote RPC ausente e PR 9 ainda draft/open/unmerged/mergeable no head antigo `bc8ad01`. O checkpoint é continuidade de leitura, não ativação ou deploy deste fix.

## Rodada final única — correções I1–I8 e menores

Implementação aditiva sobre `43f2faf`: lease exata de notificações; financeiro independente por trabalhador; histórico autorizado de criador classificado comprador; ferramentas PDF reproduzíveis/CI de PR; resolução imutável de despesas desconhecidas; fonte Unicode licenciada/NFC/HTTP422 explícito; venda/recibo/vínculo posterior para trabalho existente; indicação discreta de novas notificações sem Push. Duplicidade inicial, elegibilidade/revisões, leitura dos formulários, diagnósticos esperados, navegação repetida e tipo existente foram corrigidos. DEP0169 do SDK permanece acompanhamento upstream explícito. Ver [API](2026-10-05-commercial-api.md) e [notificações](2026-10-06-notifications.md) para contratos e recuperação.

A cadeia local tem 34 migrações. Fixtures da mesma rodada já passaram no PostgreSQL 17.5 descartável: notificações 156, workflows 246 e interface financeiro 70 instruções. A revisão própria encontrou reutilização de contrato vinculado posteriormente pelo INSERT original de evento; uma regressão RED comprovou a falha, e o guard compartilha agora o lock do contrato com o vínculo posterior. Somente o fixture workflows afetado foi repetido: 260 instruções passam, com rollback e sem Supabase hospedado. Este encerramento não repetiu suítes SQL inalteradas para renovar evidência.

Os logs preliminares chamados `finance-browser-green.log` e `buyer-history-green.log` falharam: pagamento verificado antes do refresh e fixture legado com recebimento 0 em vez de desconhecido/null. Permanecem preservados. A continuação também preserva `finance-browser-final-failure.log` (asserção de custo pago antes do refresh) e `arrival-final-failure1.log` (contexto browser destruído pelo reload de logout). Asserções agora aguardam evidência renderizada/navegação; não alteraram os valores financeiros para passar.

Pré-requisitos e comandos para checkout padrão:

```sh
npm ci
# Poppler no PATH; Python com PyMuPDF 1.26.6
python3 -m pip install PyMuPDF==1.26.6
npm test
npm run typecheck
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:18765 \
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=fixture-public npm run build
# Drivers browser opcionais; não alteram package/lockfile
npm install --no-save --package-lock=false playwright@1.62.1
npx playwright install --with-deps chromium
node tests/pdf-deployment-trace.mjs
EVENTCORE_PDF_SERVER_MODE=production node tests/quote-pdf.integration.mjs
node tests/aligned-flows.browser.mjs
node tests/notifications.integration.mjs
```

CI `EventCore CI / build` agora dispara em pull_request, main/branch desta feature e workflow_dispatch; provisiona essas dependências e roda unidades/type/build/trace/rotas PDF+browser+notificações sem destinatários reais. Configuração fonte não prova uma execução Actions ou branch protection hospedada: ambas permanecem validação do controlador.

Metadados hospedados lidos nesta continuação: 29 migrações, PR9 draft/open/unmerged ainda head bc8ad01/base-main f37f6b3 e 18 variáveis Vercel, apenas subject público de entrega no preview da branch. Todas as cinco migrações listadas acima, publicação do commit final e validação HTTPS/JWT/RLS, baseline antes/depois, credenciais/remetente/scheduler, dispositivos e PDF físico permanecem gates externos. Nenhuma migração hospedada, alteração remota, promoção, segredo ou envio foi realizado nesta rodada.

Resultados efetivamente observados no encerramento (todos exit 0; logs em `/workspace/scratch/0d27d86074e8/eventcore-final-fix-evidence/`):

| Comando / boundary | Resultado |
|---|---|
| `npm test`, `CODEX_PRIMARY_RUNTIME_PYTHON`/`CODEX_PRIMARY_RUNTIME_NODE_MODULES` unset e executáveis explícitos `EVENTCORE_*` | 80 testes, 80 pass, 0 fail/skip; Poppler `/usr/bin`, Python instalado com PyMuPDF 1.26.6 |
| `npm run typecheck` | `tsc --noEmit`, exit 0 |
| `npm run build` com boundary local e captura terminal | Next 15.5.27, compiled/types/pages 8/8/traces concluídos |
| `node tests/pdf-deployment-trace.mjs` | DejaVu regular/bold/licença, PDFKit/fonts, Sharp/libvips; todos os arquivos rastreados existem |
| Browser finance com `EVENTCORE_FINANCE_LIFECYCLE=1`, legacy_buyer em 360/390/1280; provider/coordinator em 390 | 8 jornadas pass: pagamento por trabalhador sem operações, venda/recibo/despesa/resolução/projeção, histórico/pagamentos e tipo agency/team preservados, draft enviado fechado, coordenador sem salário |
| `node tests/notifications.integration.mjs`, worker em 390 | 1 jornada pass: chegada/revogação/leitura e conta limpa ao sair; targets públicos/privados e negativa de consentimento |
| `EVENTCORE_PDF_SERVER_MODE=production node tests/quote-pdf.integration.mjs` | 7 cenários pass, incluindo HTTP 422 sem exportação para glyph não suportado; browser 390/1280 e dispatcher ack/retry/410 isolados; zero `profile_photo_cleanup_deferred` |
| `node tests/profile-photos.integration.mjs` | Next/Sharp reais; exatamente 2 warnings de cleanup injetados e assertados, sem warning extra |
| `node --trace-deprecation tests/web-push-deprecation-trace.mjs` | DEP0169 visível em código SDK inalterado, requisição criptografada produzida e zero rede |
| `git diff --check` | pass após remover whitespace da linha tocada |

A primeira captura redirecionada de build retornou exit 0 mas parou de registrar antes da tabela final. A captura terminal preservada em `build-final-verified.log` contém conclusão 8/8 e tabela de rotas; não é correção de produto. O único ajuste de produto após unidades/build foi o guard SQL do contrato, coberto pelo workflow 260. A suíte Node e o build inalterados não foram repetidos por esse ajuste exclusivamente SQL. PDFs HTTP foram renderizados por Poppler para inspeção visual: texto/colunas/totais/marca d’água/rodapé legíveis, sem clipping. Isso não prova visualizador PDF de dispositivo físico.

## Encerramento da revisão de código — 2026-10-08

A revisão do branch inteiro 38146fc..43f2faf gerou oito achados Important e oito Minor. Uma única rodada de correções foi registrada em `2ae076261e948196671083824350ef490d28efcb`; uma única revisão focada confirmou todos os oito Important e sete Minor corrigidos, sem novo achado Critical/Important/Minor. Parecer: conformidade das correções PASS; qualidade PASS WITH CONCERNS. O aviso DEP0169 de web-push3.6.7 permanece visível como manutenção futura, sem alteração de vendor ou supressão.

Evidência e decisões preservadas: [revisão original](2026-10-08-whole-branch-review.md), [correções e comandos/resultados](2026-10-08-final-fix.md), [revisão das correções](2026-10-08-final-fix-review.md), [registro de execução e decisões](2026-10-08-execution-record.md), [checkpoint hospedado somente de leitura](2026-10-08-hosted-checkpoint.json). Relatórios antigos são históricos; não substituem o parecer mais recente.

O PR9 continua sendo o destino da versão revisada. Atualização da árvore remota, execução real do EventCore CI e preview do commit final são verificações do controlador após este registro, com resultados atuais no próprio PR. Não houve merge/main, aplicação de migração hospedada, ativação do domínio de produção nem envio real. As cinco migrações, autorização/configuração de credenciais, remetente verificado, scheduler e provas HTTPS/dispositivo continuam pendentes conforme acima. A pasta temporária deste plano será removida após preservar estes registros; a aplicação, o worktree e os outros planos permanecem.
