# EventCore — CI e preview após publicação da árvore revisada

Registro do controlador. A fase de implementação/revisão integral já está encerrada conforme `2026-10-08-final-fix-review.md`. Esta verificação acompanha apenas o pacote e a publicação da mesma versão; não reinicia o projeto ou a revisão dos fluxos.

## Publicação efetivamente confirmada

- PR [9](https://github.com/Mentecare/marujoeventos/pull/9), draft/open/unmerged, main `f37f6b303269d739c84c947cf301d267b753560b` preservada.
- Commit remoto `e64ebdddca9bcae7693b6330ba5412b5d99553fa`, árvore `ea2343b410b0df0b666993423ad20d5183f27855`, exatamente igual ao HEAD local `f924db94dcc2250ef21cd614c58b83c6573c9178`. Publicação por árvore GitHub com parent real e update não forçado/lease; nenhuma reescrita do histórico remoto.
- Vercel `dpl_A2jYvuujvTKA4SCcb6b7fuMNRiGx`, mesmo commit remoto, `READY`, target null, [preview](https://marujoeventos-ocxv0eplj-douglas-factory-project.vercel.app). Logs efetivos: build Next compilou, gerou 8/8 páginas, coletou traces e criou as funções. Isso não é promoção de produção ou prova de fluxo autorizado com os novos RPCs.
- Fetch pelo plugin Vercel: `/` 200; `/sw.js` 200; `/o/11111111-1111-4111-8111-111111111111` 404, cache private/no-store. ID sintaticamente inválido no PDF retorna 404; não serve de prova de autenticação. Com UUID válido e sem JWT, o plugin retornou `deployment_authentication_required`/401 e não disponibilizou o corpo da aplicação; a recusa Auth da aplicação hospedada permanece não comprovada.

## Falha real do primeiro CI desta árvore

GitHub EventCore CI [run37807230588](https://github.com/Mentecare/marujoeventos/actions/runs/37807230588), job113414569877, Node24.21.0, Ubuntu x64.

- Checkout/setup, Poppler, PyMuPDF1.26.6, npm ci, npm test (80/80), build Next, typecheck, Playwright1.62.1 e Chromium passaram.
- `node tests/pdf-deployment-trace.mjs` falhou (exit1):

```text
AssertionError [ERR_ASSERTION]: traced file missing:
/home/runner/work/marujoeventos/marujoeventos/node_modules/@img/sharp-libvips-linuxmusl-x64/lib/libvips-cpp.so.8.18.7
at tests/pdf-deployment-trace.mjs:16:35
```

- Integrações PDF, navegação e notificações posteriores foram SKIPPED, não aprovadas.
- `npm install --no-save --package-lock=false playwright@1.62.1`, executado depois do build, registrou `added 3 packages, removed 3 packages, changed 3 packages`. A investigação local reproduziu o trace verde antes dessa instalação e a mesma ausência vermelha depois; o relatório delimitado preservará comandos/resultados e o fix.
- Avisos não confundidos com aprovações: atualização futura do runtime dos actions v4/v5 e aviso upstream web-push DEP0169 já documentado. Nenhum aviso foi suprimido nem usado para declarar integração real.

## Correção delimitada do CI já concluída

Commit local `776adf46fc89c58479957f773cdbfc9a2205296b` move somente as duas instalações existentes antes do build; mantém versões e o teste de todos os arquivos. O implementador reproduziu a mesma ausência RED; após rebuild com a árvore final, o trace integral, bibliotecas glibc efetivamente carregadas, fontes incorporadas, decoder WebP/PNG, integração PDF produção/browser/dispatcher, typecheck e80/80 testes passaram. Revisão delimitada specPASS/qualityPASS, zero findings. Não equivale ao próximo CI remoto aprovado. Relatório e revisão preservados em `2026-10-08-ci-trace-report.md` / `2026-10-08-ci-trace-review.md`.

O audit concreto também achou dois nós vulneráveis (`next` moderado via `postcss` alto). O mecanismo usado no build Next resolvia PostCSS8.4.31. Fontes primárias do mantenedor indicam correções série8 até8.5.23; Next16.4.0 major oferecido automaticamente não foi aplicado. A tarefa seguinte trata somente esse patch compatível, com comportamento RED/GREEN e build/browser reais, mantendo o framework. Não foi encontrado uso de CSS fornecido por usuários na inspeção focada; isso limita a evidência de exposição e não constitui prova de ausência de exploração.

## Patch compatível implementado, verificação hospedada ainda pendente

Commit local `1f0eaba8846ba4f9e09f1c20d2c0a1a18c81adff` aplica override somente `next.postcss=8.5.23`, mantendo Next15.5.27/React19.1.9. Sete regressões usam a dependência efetivamente resolvida pelo Next: quatro casos de leitura/serialização inseguros falham na versão anterior e passam no patch; três controles CSS/mapas legítimos permanecem aprovados. Novo `npm test`87/87, zero falhas/skips; audit atual0, build/type/trace e journeys finance/provider390 passam. Isso não é segurança universal nem prova de exploração real do app.

Primeiro provider390 falhou no count imediato do editor após notice; handler publica notice antes do refresh/removal. Rerun intacto passou; a verificação foi corrigida com espera detached limitada5s e assert count0 preservado, e o covering provider390 final passou. Nenhuma interface de produto alterada. Provisioning local APT/Chromiumdownload falhou por permissões/ZIP; runtime já validado153 usado via seam existente, sem alterar o workflow. GitHub ainda deve provar seu Chromium padrão/apt e todos os passos. Relatório completo em `2026-10-08-postcss-report.md`; revisão delimitada specPASS/qualityPASS, zero findings, em `2026-10-08-postcss-review.md`. Check focado independente confirmou a resolução de PostCSS usada pelo loader Next. Novo CI e preview da árvore corrigida serão verificados pelo controlador; resultados atuais no PR9.

## Gates externos preservados

Leitura atual do Supabase existente: 29 migrações aplicadas, última `20261005151147_eventcore_function_contract_days`; os cinco arquivos aditivos continuam pendentes. Não houve DDL/merge/promoção/cron/envio real neste acompanhamento.

Metadados Vercel atuais: 18 entradas; variáveis anteriores Google/Supabase preservadas, somente subject público da notificação adicionado na feature preview. Continuam ausentes VAPID pública/privada, dispatcher secret, Resend key e remetente confirmado. A recusa automática anterior à gravação de nova chave privada exige autorização concreta para esse segredo/destino; não foi repetida ou contornada.

Ativação compatível, baseline imediatamente anterior e comparação das colunas históricas/ACL/RLS, HTTPS com JWT, Storage/OAuth reais, dispositivo físico autorizado e envio somente para destinatários de teste continuam pendentes. Não aplicar isoladamente schema estrito contra a interface anterior da produção.
