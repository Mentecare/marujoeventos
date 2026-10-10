# Execução incremental — 09/10/2026

| Task | Estado | Evidência | Decisão |
| --- | --- | --- | --- |
| Avisos privados comerciais | verificado localmente; publicação pendente | 95 testes Node; migrações em PostgreSQL descartável; regressões de privacidade, estado, deduplicação e leases | Reutilizar fila e autorização financeira existentes |

Dependências: a alteração do banco exige o aplicativo/service worker compatíveis; cron somente após entrega real controlada. Nenhuma segunda revisão integral da implementação anterior. Execução nativa e uma revisão final do novo diff.

Provas anteriores deste acompanhamento: sete sessões GoTrue reais; 69 checks HTTPS de jornadas/finanças/preferências/Storage; PDFs curto com e sem unitários, logo real e longo de quatro páginas. A revisão visual e extração confirmaram totais, marca d'água, rodapé, paginação e ausência do marcador de custo interno. Fotos usadas: screenshot legítimo de teste, não fotografia de trabalho nem imagem gerada.

Limpeza comprovada: logout global dos sete usuários de teste com HTTP 204; remoção dos uploads próprios pelas APIs; remoção dos fixtures delimitados pela namespace, com proteção das linhas originais. Os 56 totais e hashes de tabelas comparados retornaram exatamente ao baseline anterior aos testes, incluindo Google e Storage. Essa comparação precede o novo login de Douglas, que naturalmente cria/atualiza sua sessão de autenticação.

Em 10/10/2026 UTC, login real de Douglas/Administrador confirmado pela página publicada usando entrada segura. Não foi escolhido tipo de empresa nem preenchido CPF fictício na conta real. A interface indica conexão Google existente; isso não prova uma nova sincronização.

Foram preservadas as mudanças posteriores de main, incluindo PR11 (reenvio da confirmação) e PR12 (cadastro em uma etapa), até `bb86ad98af8bb5024f163493fba2d0afc9b07a28`. A migração de cadastro posterior já aplicada no banco tem versão `20261010011932`; seu registro não foi alterado. O arquivo de origem em Git mantém o nome publicado por seu autor.

Push: configuração VAPID de produção e dispatcher autenticado comprovados, com fila vazia (zero entregas). E-mail de notificações: `RESEND_API_KEY` e `NOTIFICATION_EMAIL_FROM` ausentes em produção. SMTP de autenticação e notificações são integrações distintas. Nenhuma entrega física de push/e-mail foi comprovada; nenhum agendamento foi ativado. Faltam dispositivo/destinatário identificados pelo usuário e integração de envio de notificações configurada.
