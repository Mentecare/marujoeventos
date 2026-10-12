# Execução incremental — 09/10/2026

| Task | Estado | Evidência | Decisão |
| --- | --- | --- | --- |
| Avisos privados comerciais | publicado e migração aplicada | PR13 integrado; CI31 completo; 13 checks HTTPS com duas sessões GoTrue reais; sete verificações de estado/autorização no banco hospedado | Reutilizar fila e autorização financeira existentes |

Dependências: a alteração do banco exige o aplicativo/service worker compatíveis; cron somente após entrega real controlada. Nenhuma segunda revisão integral da implementação anterior. Execução nativa e uma revisão final do novo diff.

Provas anteriores deste acompanhamento: sete sessões GoTrue reais; 69 checks HTTPS de jornadas/finanças/preferências/Storage; PDFs curto com e sem unitários, logo real e longo de quatro páginas. A revisão visual e extração confirmaram totais, marca d'água, rodapé, paginação e ausência do marcador de custo interno. Fotos usadas: screenshot legítimo de teste, não fotografia de trabalho nem imagem gerada.

Limpeza comprovada: logout global dos sete usuários de teste com HTTP 204; remoção dos uploads próprios pelas APIs; remoção dos fixtures delimitados pela namespace, com proteção das linhas originais. Os 56 totais e hashes de tabelas comparados retornaram exatamente ao baseline anterior aos testes, incluindo Google e Storage. Essa comparação precede o novo login de Douglas, que naturalmente cria/atualiza sua sessão de autenticação.

Em 10/10/2026 UTC, login real de Douglas/Administrador confirmado pela página publicada usando entrada segura. Não foi escolhido tipo de empresa nem preenchido CPF fictício na conta real. A interface indica conexão Google existente; isso não prova uma nova sincronização.

Foram preservadas as mudanças posteriores de main, incluindo PR11 (reenvio da confirmação) e PR12 (cadastro em uma etapa), até `bb86ad98af8bb5024f163493fba2d0afc9b07a28`. A migração de cadastro posterior já aplicada no banco tem versão `20261010011932`; seu registro não foi alterado. O arquivo de origem em Git mantém o nome publicado por seu autor.

Push: configuração VAPID de produção e dispatcher autenticado comprovados, com fila vazia (zero entregas). E-mail de notificações: `RESEND_API_KEY` e `NOTIFICATION_EMAIL_FROM` ausentes em produção. SMTP de autenticação e notificações são integrações distintas. Nenhuma entrega física de push/e-mail foi comprovada; nenhum agendamento foi ativado. Faltam dispositivo/destinatário identificados pelo usuário e integração de envio de notificações configurada.

## Fechamento da publicação e da homologação dos novos avisos

- PR13: https://github.com/Mentecare/marujoeventos/pull/13 ; merge `037d461d0fadf7a87b3ff774a9cb22025c02bec0`. Incluiu os registros do PR10 por ancestralidade, preservando PR11/PR12.
- CI31, run `38013360287`: concluído com sucesso. Unidades, build, typecheck, trace PDF, integração de PDFs, navegador e integração isolada de notificações. Esses testes de transporte não são entrega física de e-mail/push.
- Deploy `dpl_GWmSr7CgUSzJy8zKPND8Sm3hCV3s`: READY, produção, SHA do merge, aliases `eventcore.space` e `www.eventcore.space` comprovados.
- Migração aplicada por `apply_migration`: `20261010013258_eventcore_commercial_notifications`, total hospedado 36. MD5 do SQL local e do registro hospedado iguais: `3e7fee14897be9dae173efb51408c61b`. Somente o arquivo desta nova migração foi renomeado para corresponder à versão efetivamente aplicada; nenhum marcador histórico foi alterado.
- Após publicação, 13 verificações HTTPS com duas contas temporárias: pedido restrito à prestadora, rascunho sem divulgação, proposta restrita ao cliente, DTOs sem dados privados, contrato correto para ambas as partes, histórico autorizado, pedido contratado suprimido e acesso anônimo negado. Os sete predicados hospedados confirmaram o pedido contratado, proposta irmã ainda enviada/válida, canal de e-mail habilitado como controle positivo, bloqueio das propostas aceita/irmã no envio, leitura autorizada e negação aos demais perfis. Nenhum dispatcher/adaptador externo foi chamado.
- Logout global de ambas as contas de teste: HTTP 204. Limpeza delimitada pela namespace `ec090926`, com guarda das linhas anteriores. Resultado: zero usuários/especialidades de teste. Nova consulta em 12/10 confirmou zero fixtures.
- Nesta segunda rodada, 53 das 57 tabelas comparadas mantiveram contagens e hashes integrais. Nas quatro tabelas de autenticação/perfis que mudaram no intervalo, as cinco linhas originais de perfis e de identidades mantiveram seus hashes; havia novo cadastro fora da namespace de teste. `auth.users` e `auth.sessions` também mudaram no intervalo, portanto não se afirma igualdade global de hashes desta rodada. Não foram sobrescritas alterações de autenticação posteriores. Google, Storage e registros comerciais/operacionais originais passaram na comparação.

## Retomada conferida em 12/10/2026

Main e produção incluem a correção posterior PR14, SHA `1f01876273b8f74341fe9a984a2284e96496b373`, deploy `dpl_C3WAN18sYdu4Q4UZWuqSb2V7o3zD` READY. PR10/PR13 estão integrados. As quatro configurações VAPID/dispatcher continuam em Production; as duas variáveis de e-mail de notificações continuam ausentes. A migração comercial aplicada continua registrada na versão acima. Esta retomada preserva integralmente o trabalho posterior de cadastro.

O último pedido de entrada segura foi interrompido pelo usuário; a sessão final de navegador não foi comprovada. Não repetir coleta de credenciais sem novo pedido. A primeira entrada havia sido comprovada na conta Douglas; nenhuma senha foi lida ou registrada pelo agente.

Pendências reais: entrega push em dispositivo identificado e com consentimento; integração/e-mail de teste identificado; cron depois dos canais validados; jornadas comerciais completas em navegador com contas identificadas; nova sincronização Google controlada. O sucesso das APIs e dos testes isolados não substitui essas provas.
