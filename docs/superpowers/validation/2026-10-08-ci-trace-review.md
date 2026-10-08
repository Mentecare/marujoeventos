# Task 1 — revisão delimitada

Commit revisado: `776adf46fc89c58479957f773cdbfc9a2205296b`, base `f924db94dcc2250ef21cd614c58b83c6573c9178`.

## Spec compliance: PASS, com confirmação hospedada pendente

A mudança atende ao brief: antecipa as instalações existentes de Playwright/Chromium para depois de `npm ci` e antes de testes/build/tracing, conservando comandos, versões e validações. A causa descrita no relatório tem evidência local específica: a instalação posterior removeu os pacotes Sharp/libvips musl e fez o teste existente falhar no mesmo arquivo da execução hospedada original; reconstruir com a árvore final produziu trace íntegro. Nenhuma ausência foi ignorada e nenhum teste de integridade foi enfraquecido.

O relatório documenta `npm test` (80/80), build, typecheck, trace integral e integração de PDF em produção, incluindo fontes incorporadas e uso efetivo das bibliotecas glibc. A modificação não alcança UI, navegação, Auth, integrações de produto, DB, segredos ou produção, nem adiciona dependência ao runtime do produto. Preserva a configuração de infraestrutura existente; altera apenas a ordem necessária das etapas de CI.

## Code quality: PASS

Diff mínimo e coerente com a causa reproduzida. O comentário em `.github/workflows/ci.yml:24` explica o requisito de ordem; as etapas em `:25–26` estabelecem a árvore final antes de `npm run build`. Os passos posteriores continuam executando as validações existentes. Não há complexidade adicional nem exclusões de arquivos/plataformas que possam ocultar falhas reais.

## Findings

- Critical: nenhum.
- Important: nenhum.
- Minor: nenhum.

## Evidência e limites

Revisão restrita ao brief, ao relatório e ao pacote de diff `review-f924db9..776adf4.diff`, lido uma vez. Não houve releitura de arquivos alterados, inspeção adicional, repetição de suites, nem mutação de checkout/index/HEAD; somente este relatório de revisão foi escrito. Os resultados locais são evidência documentada pelo executor, não execuções independentes desta revisão.

Não equivale a aprovação de CI hospedado. O runner original usa Node 24.21.0, enquanto a reprodução usa 24.19.0; Chromium local foi reutilizado, sem reproduzir a instalação Chromium/apt completa. O próximo run GitHub deve confirmar o build e trace com a árvore final e executar todos os checks antes pulados, incluindo browser e notificações independentes. A execução prematura sobre trace parcial está corretamente registrada como falha intermediária, sem ser contada como GREEN.

A auditoria read-only registra duas dependências vulneráveis preexistentes (`next` e `postcss`, zero critical) e quatro advisories de PostCSS. Ela não prova exposição remota do produto, segurança de todos os caminhos nem auditoria completa dos pacotes extraneous de teste. O relatório explicita esses limites e não atribui os achados ao Playwright ou à mudança. Uma atualização major de Next/override de PostCSS requer trabalho separado; não é requisito para aceitar esta correção delimitada de ordem do CI.
