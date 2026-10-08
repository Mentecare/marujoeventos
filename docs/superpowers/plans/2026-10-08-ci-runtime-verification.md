# EventCore — verificação do runtime no CI após publicação do PR

Este é um acompanhamento pontual da verificação hospedada. As tarefas do plano aprovado de fluxos, a revisão integral, a única onda de correções e sua revisão delimitada já terminaram. Não reiniciar esses trabalhos. A falha real abaixo surgiu durante a verificação do PR publicado.

## Spec e restrições globais

Requisitos vinculantes já aprovados, especialmente item 8:

> Faça mudanças incrementais e compatíveis. Não apague dados ou contratos existentes. Se houver trabalho em andamento, preserve-o.
>
> Faça as alterações necessárias no banco, servidor e interface, sem entregar apenas telas ou dados simulados.
>
> Não trate deploy, migração aplicada ou serviço integrado como concluído sem evidência.

- Preservar a interface, navegação, autenticação, integrações e infraestrutura existentes.
- A verificação deve continuar garantindo os arquivos efetivamente necessários ao PDF, suas fontes licenciadas e bibliotecas nativas. Não ignorar indiscriminadamente arquivos ausentes, desabilitar passos ou mascarar falhas.
- Não alterar os cinco arquivos de migração pendentes, dados hospedados, permissões financeiras, serviços externos, segredos ou destinatários reais nesta tarefa.
- Somente um implementador; ele não delega nem despacha revisores. O controlador fará uma revisão delimitada desta mudança e conferirá o CI real depois de publicar no PR já autorizado.
- A revisão integral dos fluxos já foi concluída. O acompanhamento revê apenas o diff desta nova falha, sem repetir a revisão integral ou a onda final anteriores.

## Task 1: Investigar e corrigir a falha real de pacote/CI do PDF

Base local limpa: `f924db94dcc2250ef21cd614c58b83c6573c9178`, árvore `ea2343b410b0df0b666993423ad20d5183f27855`.
PR 9: `Mentecare/marujoeventos`, remoto `e64ebdddca9bcae7693b6330ba5412b5d99553fa`, mesma árvore local.

Evidência real: GitHub EventCore CI run `37807230588`, job `113414569877`, Node `24.21.0`, Ubuntu x64. `npm ci`, `npm test` (80 casos), `npm run build`, typecheck e instalações de Playwright/Chromium passaram. Passo `node tests/pdf-deployment-trace.mjs` falhou; testes posteriores de PDF, navegação e notificações foram pulados.

```text
AssertionError [ERR_ASSERTION]: traced file missing:
/home/runner/work/marujoeventos/marujoeventos/node_modules/@img/sharp-libvips-linuxmusl-x64/lib/libvips-cpp.so.8.18.7
at tests/pdf-deployment-trace.mjs:16:35
```

O workflow constrói o Next antes de executar `npm install --no-save --package-lock=false playwright@1.62.1`. Esse passo posterior registrou `added 3 packages, removed 3 packages, changed 3 packages`; isto é uma pista, não uma causa confirmada. Inspecione o trace e as dependências reais antes/depois, compare a plataforma local com o runner e consulte documentação primária quando necessário. Não alterar o teste para presumir que um binário ausente nunca é necessário.

1. Ler workflow, teste de trace, configuração Next e regras de instalação dos pacotes nativos; reproduzir a falha ou obter evidência precisa do ponto onde o conjunto de dependências diverge.
2. Registrar causa comprovada, o teste que ficou vermelho e seus comandos/resultados. O teste de integração/trace existente pode ser o teste cobridor; evitar testes que apenas espelhem a ordem textual do YAML.
3. Corrigir minimamente a instalação/build/validação conforme a causa demonstrada. Preservar versões e funcionalidade do produto; não instalar dependências novas no runtime do produto só para atender o ambiente de testes.
4. Executar os checks afetados e o comando padrão `npm test`. Verificar que fontes e bibliotecas da plataforma efetivamente usadas continuam no pacote e são utilizáveis. Identificar qualquer evidência que só o runner GitHub poderá fornecer, sem declarar o CI hospedado aprovado.
5. Fazer auto-revisão, commit somente dos arquivos da tarefa (não o plano/ledger do controlador), e escrever relatório completo no caminho indicado. Retornar somente status, commits, resumo de testes e preocupações.

O relatório deve conter: causa, reprodução/RED, mudança mínima, GREEN, comandos/resultados, auto-revisão, arquivos/commits, limites e próximos checks hospedados. Logs temporários ficam fora do código. Não repetir suites amplas já aprovadas sem uma mudança ou falha que justifique.

## Task 2: Corrigir advisories concretas de PostCSS sem trocar o framework

O audit read-only da Task1 retornou `next` moderate via `postcss` high, ambos nós da mesma dependência `next@15.5.27 → postcss@8.4.31`. Playwright não é a causa. O audit automático oferece Next16.4.0 major; não executar `npm audit fix --force` nem atualizar Next/React.

As fontes primárias verificadas pelo controlador indicam patches PostCSS dentro da série8:

- https://github.com/postcss/postcss/security/advisories/GHSA-qx2v-qp2m-jg93 : XSS stringify, afetado<8.5.10.
- https://github.com/postcss/postcss/security/advisories/GHSA-6g55-p6wh-862q : leitura/informação sourceMappingURL, afetado<=8.5.11.
- https://github.com/postcss/postcss/security/advisories/GHSA-r28c-9q8g-f849 : traversal/map, afetado<=8.5.17.
- https://github.com/postcss/postcss/security/advisories/GHSA-fxqj-rqcc-2cmp : patch incompleto sem from, afetado<=8.5.22, patch8.5.23.
- https://github.com/postcss/postcss/releases/tag/8.5.23 : release do mantenedor.

Inspeção focada não encontrou entrada CSS de usuário no app/lib: PostCSS é usado pelo build Next para globals.css. Isso limita a evidência de exposição, não elimina os achados nem prova ausência de exploração. Não alegar ataque/exposição de segredos reais.

1. Validar que PostCSS8.5.23 está disponível no registry oficial e que um override npm estreito para a dependência do Next pode manter a API série8 sem alterar versões do framework. Se houver incompatibilidade real, reportar precisamente antes de ampliar escopo.
2. Cobrir comportamentos das advisories com regressões que usam somente arquivos temporários sintéticos, sem ler segredos reais. Reproduzir RED na versão atual; provar GREEN da versão corrigida. No mínimo: sourceMappingURL que sai do diretório com from; URI absoluta sem from; preservação do processamento CSS legítimo. Investigar também XSS stringify e registrar resultado. Evitar asserts de string da versão ou de textos do package.json que apenas espelham o pin.
3. Atualizar package/lockfile minimamente; candidato é override `next: { postcss: "8.5.23" }`, a validar na árvore efetiva. Não manipular manualmente vendor instalado nem suprimir audit. Verificar `npm ci` + preparação Playwright antes do build preservam a versão corrigida e os guards de tracing.
4. Rodar regressões cobridoras, `npm audit --json`, `npm test` uma vez no final, typecheck/build/trace e o browser existente afetado pelo build CSS (ao menos jornadas provider e finance em390px). Conferir resultados reais, incluindo se algum advisory continua ou um patch quebra comportamento legítimo. Não declarar segurança universal/CI hospedado aprovado.
5. Auto-revisar, commit somente dos arquivos da Task2 (excluir plano/documentos do controlador), e relatório incremental no caminho indicado: causa, RED/GREEN, comandos/saídas, árvore dependências, fontes primárias, arquivos/commits, warnings e limites. Retornar status/commits/resumo/preocupações. Nenhum subagente.

Esta tarefa trata apenas os achados concretos recém-observados na verificação de publicação; não reinicia features, migrações ou a revisão integral encerrada. A revisão subsequente é delimitada a este diff e seus riscos reais de build/dependência.

Esclarecimento de verificação surgido na execução: provider390 falhou no count imediato de editor após notice de orçamento enviado; handler exibe notice antes de aguardar refresh e só então remove editor. Rerun intacto passou, mas não elimina a janela observada. Corrigir somente a espera do teste browser: aguardar editor detached com prazo limitado e manter assert count0; sem sleeps gerais ou mudanças de produto. Incluir o diff e evidência RED/reexecução cobrindo provider390 no relatório/revisão. Não repetir npm test se já executado no mesmo patch e a única edição posterior for desse standalone browser.
