# Task 1 — correção delimitada do trace do CI

Status: DONE_WITH_CONCERNS. Falha original reproduzida e corrigida localmente; CI hospedado ainda pendente e auditoria registra advisories de produto preexistentes, fora desta correção.

## Escopo e causa comprovada

Base: `f924db94dcc2250ef21cd614c58b83c6573c9178`. Lidos o brief desta tarefa, `.github/workflows/ci.yml`, `tests/pdf-deployment-trace.mjs`, `next.config.ts`, manifests/lockfile nativos de Sharp, loader nativo instalado e integração existente do PDF. O plano anterior não foi consultado/refeito. Nenhum agente/helper/revisor foi disparado.

O workflow executava `next build` antes de `npm install --no-save --package-lock=false playwright@1.62.1`. O build registrava arquivos dos pacotes Sharp/libvips glibc e musl existentes naquele momento. A instalação posterior resolveu novamente a árvore e removeu os pacotes musl incompatíveis com o host glibc. Assim o trace passou a apontar para arquivos que já não existiam. A falha era uma inconsistência concreta entre dependências no instante do build e no instante da validação; não autorização para ignorar arquivos ausentes.

Evidência local Linux x64, Ubuntu glibc 2.39, Node 24.19.0 / npm 11.9.0:

- Após `npm ci`, `node_modules/@img` continha `colour`, `sharp-libvips-linux-x64`, `sharp-libvips-linuxmusl-x64`, `sharp-linux-x64`, `sharp-linuxmusl-x64`, `sharp-wasm32`.
- Os manifests dos pares glibc/musl possuem `libc: [glibc]` / `libc: [musl]`; as entradas correspondentes do lockfile não registram esse campo. Essa diferença explica a seleção divergente observada entre instalar o lock e resolver novamente os manifests.
- Antes de instalar Playwright, o trace existente da mesma árvore de código continha os dois pares e o teste passava. Não foi necessário reconstruir esse baseline já íntegro para reproduzir a alteração causada pela instalação.
- A instalação exata do workflow registrou `added 3 packages, removed 3 packages, and changed 3 packages in 24s`; removeu precisamente `sharp-libvips-linuxmusl-x64` e `sharp-linuxmusl-x64` de `@img`. Package/lockfile versionados permaneceram sem diff.
- O teste existente tornou-se RED na mesma libvips e linha 16 do CI run 37807230588/job 113414569877. Sharp continuou carregando os binários glibc, comprovados por `process.report.getReport().sharedObjects`.

Referências primárias consultadas: [instalação Sharp](https://sharp.pixelplumbing.com/install/) (seleção por plataforma/CPU/libc e dependências opcionais) e [configuração npm 11](https://docs.npmjs.com/cli/v11/using-npm/config/) (`package-lock=false` ignora o lock na instalação). A causalidade acima foi confirmada pela comparação real antes/depois, não inferida apenas da documentação.

## RED e mudança mínima

Comandos e resultados:

1. `node tests/pdf-deployment-trace.mjs`: PASS no baseline; todas as entradas do trace existiam.
2. `npm ci`: exit 0, 77 pacotes instalados em 28s; pares glibc/musl presentes. Log `/tmp/eventcore-ci-runtime-npm-ci.log`.
3. `node tests/pdf-deployment-trace.mjs`: PASS após `npm ci`.
4. `npm install --no-save --package-lock=false playwright@1.62.1`: exit 0; remoção registrada acima. Log `/tmp/eventcore-ci-runtime-playwright.log`.
5. `node tests/pdf-deployment-trace.mjs`: exit 1, `AssertionError [ERR_ASSERTION]: traced file missing: .../node_modules/@img/sharp-libvips-linuxmusl-x64/lib/libvips-cpp.so.8.18.7`, `tests/pdf-deployment-trace.mjs:16:35`. Log `/tmp/eventcore-ci-runtime-red.log`.

Apenas `.github/workflows/ci.yml` foi alterado: mover instalação de Playwright e instalação de Chromium para logo após `npm ci`, antes de testes/build; acrescentar comentário para manter instalações anteriores ao tracing. Os comandos/versões originais são preservados. O teste existente cobre o comportamento real de integridade e não foi alterado. Não foram adicionadas dependências do produto, exclusões de trace, testes que espelham YAML, DDL ou mudanças de UI/nav/Auth/integrações.

## GREEN e verificação efetiva

O build foi executado **após** a mesma instalação de Playwright que produziu o RED, mantendo a árvore final intacta entre build e trace. Configuração pública/credenciais foram fixtures idênticas às do workflow; nenhum segredo real, serviço de produção ou envio real foi utilizado.

```bash
NEXT_TELEMETRY_DISABLED=1 \
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:18765 \
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=fixture-public \
SUPABASE_SERVICE_ROLE_KEY=ci-placeholder \
GOOGLE_CLIENT_ID=ci-placeholder GOOGLE_CLIENT_SECRET=ci-placeholder \
GOOGLE_OAUTH_STATE_SECRET=ci-placeholder-ci-placeholder-ci-placeholder \
GOOGLE_TOKEN_ENCRYPTION_KEY=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
NEXT_PUBLIC_APP_URL=https://example.vercel.app npm run build
node tests/pdf-deployment-trace.mjs
npm run typecheck
EVENTCORE_PDF_SERVER_MODE=production \
EVENTCORE_CHROMIUM_EXECUTABLE=/workspace/scratch/0d27d86074e8/eventcore-browser-runtime/chromium \
EVENTCORE_PDF_OUTPUT=/tmp/eventcore-ci-runtime-pdf \
node tests/quote-pdf.integration.mjs
pdffonts /tmp/eventcore-ci-runtime-pdf/route-units.pdf
pdfimages -list /tmp/eventcore-ci-runtime-pdf/route-units.pdf
npm test
git diff --check
```

| Verificação | Resultado |
| --- | --- |
| Build concluído | exit 0; Next 15.5.27 compilação, types/static generation/tracing concluídos |
| Trace final | exit 0; PDFKit, fontes DejaVu/licença, fontes compiladas/AFMs Helvetica, Sharp e libvips presentes; **todos** arquivos rastreados existem |
| Bibliotecas efetivamente carregadas | Sharp 0.35.5 / libvips 8.18.7 glibc; realpaths de ambos objetos nativos carregados constam no trace; nenhuma entrada musl obsoleta |
| Typecheck | exit 0 |
| PDF integração produção | exit 0; Auth 401, tenant 404, política 400, venda PDF 200; RPC/Storage isolados; fallback existente e dados privados ausentes |
| PDF fontes | DejaVuSans-Bold e DejaVuSans CID TrueType, embedded=yes, subset=yes, unicode=yes |
| PDF decoder | WebP fixture processada por Sharp e imagem PNG 80×50 incorporada no PDF |
| Browser integração existente | 390/1280 px: preview/download, troca de totais, revisão invalida preview, requisição obsoleta rejeitada, responsividade; autorização push explícita e decline |
| Dispatcher incluído na mesma integração | ack/no-email-ack/expired; adapters com transportes isolados, nenhum envio externo real |
| `npm test` (uma única execução nesta tarefa, ao final) | exit 0; 80 testes, 80 pass, 0 fail, 0 skipped, 0 cancelled |
| `git diff --check` | exit 0 |

Houve uma leitura prematura do trace enquanto o build ainda coletava traces: falhou por ausência de `LICENSE-DejaVu.txt` no trace parcial. Essa execução não é GREEN nem uma regressão de build concluído; após aguardar exit 0 do build, o mesmo teste passou integralmente. Ela fica registrada para não omitir o resultado intermediário.

Logs temporários fora do código: `/tmp/eventcore-ci-runtime-{build,green-trace,typecheck,pdf,test}.log`; PDFs/screenshots/log do servidor em `/tmp/eventcore-ci-runtime-pdf`. As suites independentes de navegação/notificações já aprovadas não foram repetidas; a integração afetada do PDF já inclui os checks mencionados.

## Auditoria read-only solicitada pelo controlador

`npm audit --json` executado uma vez, sem `audit fix`, exit 1 por achados. JSON `/tmp/eventcore-ci-runtime-audit.json`; stderr contém apenas aviso ambiental npm `Unknown env config http-proxy`. Contagem: **2 nós vulneráveis**, `next` moderate (direto, via `postcss`) e `postcss` high (transitivo); zero critical. `npm ls next postcss playwright`: `next@15.5.27 → postcss@8.4.31`, `playwright@1.62.1 extraneous`. São dependências do produto, preexistentes no package/lockfile, não vulnerabilidades atribuídas ao Playwright. Este audit usa a árvore do lock e não constitui auditoria independente completa de todos os pacotes extraneous de teste.

| Advisory retornada no JSON | Severidade | Causa/arquivo e condição descrita pelo mantenedor | Patch PostCSS declarado |
| --- | --- | --- | --- |
| [GHSA-qx2v-qp2m-jg93](https://github.com/postcss/postcss/security/advisories/GHSA-qx2v-qp2m-jg93) | moderate, CVSS 6.1 | Stringify de CSS preserva `</style>`; XSS quando CSS controlado por atacante é reserializado e incorporado em HTML style. Caminho instalado de stringify: `node_modules/postcss/lib/stringifier.js` | 8.5.10; range `<8.5.10` |
| [GHSA-6g55-p6wh-862q](https://github.com/postcss/postcss/security/advisories/GHSA-6g55-p6wh-862q) | high, CVSS 7.5 | CSS não confiável com sourceMappingURL causa leitura de arquivo e exposição em erro; `lib/previous-map.js`, alcançado por `lib/input.js` | 8.5.12; range `<=8.5.11` |
| [GHSA-r28c-9q8g-f849](https://github.com/postcss/postcss/security/advisories/GHSA-r28c-9q8g-f849) | high, CVSS 7.5 | Traversal/leitura de .map via sourceMappingURL e divulgação no mapa resultante; `lib/previous-map.js` loadMap/loadFile | 8.5.18; range `<=8.5.17` |
| [GHSA-fxqj-rqcc-2cmp](https://github.com/postcss/postcss/security/advisories/GHSA-fxqj-rqcc-2cmp) | moderate; JSON score 0 sem vetor | Correção incompleta permite .map absoluta/traversal sem opção `from`, expondo sources/sourcesContent; `lib/previous-map.js` | 8.5.23; range `<=8.5.22` |

Advisories primárias do repositório PostCSS consultadas. Inspeção instalada confirmou `node_modules/postcss/lib/previous-map.js` lendo annotation por `readFileSync` sem contenção do caminho, e `node_modules/next/package.json` fixando PostCSS 8.4.31. O loader de Next em `node_modules/next/dist/build/webpack/loaders/postcss-loader/src/index.js` processa CSS durante build. A busca em `app`, `lib` e configuração não encontrou uso direto de PostCSS pelo aplicativo. Isso não prova ausência de exploração em todos os caminhos: não foi realizado pentest nem rastreamento completo de entrada CSS não confiável/retorno de mapas. Não afirmar produto explorável remotamente, nem seguro, somente com a auditoria.

`fixAvailable` do JSON indica Next **16.4.0**, `isSemVerMajor=true`. Não aplicado: mudar framework/override exige escopo separado e validar compatibilidade; os patches PostCSS acima não autorizam presumir que sobrescrever a dependência fixada de Next seja seguro. Este task corrige CI tracing, não advisories. Não houve mudança no package/lockfile e não foi repetido npm test após esta consulta read-only.

## Auto-revisão, arquivos e commit

- Diff final: somente a movimentação das duas etapas de instalação e comentário do workflow; sem alteração de permissões, branches, fixtures, comandos/versões ou validações existentes.
- Asserção `fs.existsSync` para cada entrada continua obrigatória; fontes/bibliotecas usadas foram conferidas no PDF e nos objetos nativos carregados.
- `package.json`, `package-lock.json`, `next.config.ts`, produto e testes permanecem sem diff. Nenhum segredo ou log foi adicionado ao código.
- Arquivos do controlador `docs/superpowers/plans/2026-10-08-ci-runtime-verification.md` e `docs/superpowers/validation/2026-10-08-hosted-ci-verification.md` não foram modificados/staged/commitados por este task.
- Arquivo de implementação: `.github/workflows/ci.yml`. Este relatório está em `.superpowers/` (ignorado pelo repositório), fora do commit de código.
- Commit: `776adf4` — `fix: install CI browser tools before deployment tracing`; somente `.github/workflows/ci.yml`, 3 inserções / 2 remoções. `git show --stat` e `git status --short` confirmaram que somente os dois arquivos untracked do controlador continuam fora do commit.

## Limites hospedados / próximos checks

Nenhum push/publicação/review externo feito por este task. Não declarar o novo run GitHub aprovado. Runner original Node 24.21.0 difere do Node 24.19.0 local; seleção nativa/RED coincide, mas a confirmação hospedada cabe ao controlador.

Chromium local reutilizado do runtime existente em vez de instalar o Chromium/apt completo do GitHub. No runner deve-se confirmar: instalações finais antes do build, build/types/test, trace integral, PDF produção, browser independente, notificações, resultado de auditoria e conclusão de todos os passos anteriormente pulados. Os limites/advisories acima permanecem explícitos até tratamento separado.
