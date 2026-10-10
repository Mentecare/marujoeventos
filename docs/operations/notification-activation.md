# Ativação controlada das notificações

## Recursos pendentes

- Dispositivo de teste identificado pelo proprietário, com autorização explícita pelo botão de push. No iPhone/iPad compatível, usar a instalação na Tela de Início quando exigida pelo sistema.
- Destinatário de e-mail de teste identificado pelo proprietário, endereço confirmado e preferência de recebimento habilitada.
- `RESEND_API_KEY` com acesso de envio e `NOTIFICATION_EMAIL_FROM` de domínio verificado, no ambiente Production da Vercel. Inserir a chave pelo painel seguro; não enviá-la em chat, arquivos, commits ou variáveis públicas. Configurar SMTP do Supabase Auth não configura automaticamente o dispatcher de notificações.

## Ordem de ativação

1. Confirmar a versão publicada, segredos/configuração por metadados e inscrição existente do dispositivo; não substituir chaves que possuam inscrições ativas.
2. Produzir somente um trabalho/oportunidade de homologação privado ou elegível, com destinatários de teste previamente identificados. Conferir preferências, confirmação do e-mail e consentimento do dispositivo. Não despachar a fila geral para testar.
3. Comprovar entrega no dispositivo/caixa de entrada e abertura do registro autorizado. Confirmar recusa/incompatibilidade de push sem bloquear central e e-mail. Não confundir aceite HTTP do provedor com recebimento real.
4. Homologar diariamente, pausa, canais, elegibilidade, revalidação, deduplicação, retentativas e encerramento com fixtures controlados. Mensagens levam somente título genérico e link protegido.
5. Só então ativar execução recorrente na infraestrutura existente. Vercel Hobby oferece cron diário; não atende sozinho a alertas imediatos. Avaliar Supabase Cron/pg_net, com frequência e limites compatíveis, usando os nomes Vault `eventcore_notification_dispatch_secret` e `eventcore_notification_worker_url`; nunca consultar/registrar os valores em texto.
6. Registrar ID do job, horário, resultado HTTP, quantidade processada, falhas e retentativas sem dados privados. Para interromper, desativar somente o job EventCore criado, preservando filas e inscrições. Não instalar um segundo dispatcher simultâneo.

Ainda não há prova de entrega externa nem job ativo neste acompanhamento. Esta preparação não representa ativação concluída.

Referências oficiais consultadas: https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/ ; https://vercel.com/docs/cron-jobs/usage-and-pricing ; https://supabase.com/docs/guides/cron ; https://supabase.com/docs/guides/functions/schedule-functions ; https://resend.com/docs/dashboard/domains/introduction .
