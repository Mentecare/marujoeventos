# SDD ledger — plan: docs/superpowers/plans/2026-10-08-ci-runtime-verification.md

Escopo: nova falha real do GitHub CI após publicação do PR, run37807230588/job113414569877. Plano anterior concluído, arquivado e seu workspace removido; não reiniciar.

| Tarefa/interface | Produz/consome | Verificação prévia |
| --- | --- | --- |
| Task 1 consigo mesma | Instalação final de dependências → build Next → trace PDF → integrações | Exige causa comprovada e teste cobridor real; não aceita ignorar ausência de arquivos ou inverter requisito para fazer teste passar. Consistente. |
| Task 1 / controlador de publicação | Commit/reprodução local → diff revisto → árvore remota idêntica → CI GitHub | Autorização já existente para PR/preview; nenhuma alteração de banco, segredo ou produção nesta tarefa. Consistente. |

Ruling: tratar a falha nova do CI como acompanhamento delimitado da verificação hospedada, com implementador e revisão apenas de seu diff — surgiu depois do encerramento comprovado da revisão integral/única onda final e impede declarar a versão verificável — custo se errado: reavaliar a suficiência do pacote e repetir seus testes antes de homologar, sem usar esse acompanhamento para reiniciar os fluxos aprovados.

Task 1: início; BASE f924db94dcc2250ef21cd614c58b83c6573c9178. Sem mutação hospedada, sem novo envio real.

Task 1: implementação776adf46fc89c58479957f773cdbfc9a2205296b; causa/RED reproduzidos em host glibc x64: instalação pós-build removeu pares musl. Instalações agora antes do build, teste de todos os arquivos preservado. Relatório e logs efetivos lidos: trace/PDF produção/build/type e80/80npm aprovados. Audit read-only achou2 nós next/postcss moderado/alto; correção de CI não altera produto/lock. Revisão delimitada pendente; novo CI remoto ainda não executado.

Preflight Task2 recém-originada pelo audit efetivo; advisories primárias abertas e faixas de patch conferidas. Não se presume exploração remota ou equivalência total entre séries de PostCSS.

| Tarefas/interface | Produz/consome | Verificação |
| --- | --- | --- |
| Task2 consigo mesma | Patch série8 → regressões de leitura/serialização CSS → build real | Exige RED/GREEN e uso legítimo preservado. Não usar só audit verde ou comparação de versão como prova de comportamento. |
| Task1/Task2 | Instalações finais antes do build → resolução npm/override → trace íntegro | Task1 preserva versões enquanto corrige ordem; Task2 altera somente dependência PostCSS por patch justificado. Escopos distintos compatíveis. |
| Task2/controlador | Commit revisto → árvore idêntica publicada → CI/preview reais | Framework, schema e segredos não mudam. Publicação/verificação remota continua controlador. |

Task 1: complete (commitsf924db9..776adf4, review clean). Review /root/review_hosted_ci_trace specPASS/qualityPASS, zerofindings, controlador leu relatório. CI GitHub com instalações/Node completos ainda é gate de publicação, não requisito de fonte dispensado.

Task 2: início; BASE776adf46fc89c58479957f773cdbfc9a2205296b; patch série8/RED e preservação de build/interface serão verificados antes de publicar.

Task2 checkpoint: efetivo Next→PostCSS8.4.31 reproduz4 falhas segurança/3 controles legítimos; override estreito8.5.23 +npmci e preparoPlaywright preservam Next/React,7/7GREEN e audit0. Build/type/trace efinance390PASS. Provisioning APT falhou por setgroups/seteuid do ambiente, zip Chromiumdownload inválido; reutilizado runtime existente153, semescalation/CI alterado. Provider390 falhou no count imediato após notice; rerun sequencial intactoPASS, handler notice antes de refresh/removal identifica janela do teste. Controlador solicita aguardar detached com timeout e manter count0; nenhum produto alterado/flake oculto.

Task2 implementação1f0eaba8846ba4f9e09f1c20d2c0a1a18c81adff; relatório final lido:4 arquivos, patch parent-only8.5.23 +7 regressões efetivas NextCSS +espera browser detached5s mantendo assert0. Npm87/87, build/type/trace/audit0 efinance/provider390 finaisPASS; falha inicialprovider e provisioning permanecem registrados. Nenhuma DDL/UI/segredo/publicação/envio. Revisão delimitada começa776adf4..1f0eaba; controller-owneddocs não stageados pelo worker.

Task 2: complete (commits776adf4..1f0eaba, review clean). /root/review_postcss_compatible specPASS/qualityPASS, zerofindings; controlador leu relatório completo. Check focado independente de resolver confirma loaderNext e testes mesma8.5.23; versionsframework preservadas. HostedCI/provisioning ainda gate externo, sem alegação universal de segurança.

Fonte do acompanhamento: completa; duas tarefas delimitadas revistas, sem repetir revisão integral/onda final. Arquivar brief/relatórios/revisões/ledger pertinentes no Git antes de remover apenas este workspace. Controlador segue publicação featurePR9/preview e CI reais; main/DDL/creds/envio continuam sem autorização concreta adicional ou prova. Os registros anteriores permanecem íntegros.
