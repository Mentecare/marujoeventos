# Revisão única do novo diff — 09/10/2026

Revisor independente `review_notification_completion`, execução nativa. Leu spec, plano e todo o novo diff contra `0520301`. Não alterou arquivos, banco ou publicação; não reviu a implementação anterior inteira.

Um achado P2: uma proposta irmã continua `sent` depois que outra proposta do mesmo pedido é aceita. O pedido fica `contracted`, mas o primeiro gate permitia envio externo da irmã. Correção: para envio de proposta vinculada, exigir pedido ainda `quoted`; preservar leitura autorizada da proposta aceita na central.

O controlador reproduziu a falha com duas propostas e canal de e-mail explicitamente habilitado; acrescentou também lease real do banco que passa antes do aceite e deve falhar depois. Os testes de expiração/aceite passaram a ter controle positivo de elegibilidade, evitando um falso positivo devido a canal desabilitado.

RED comprovado no PostgreSQL descartável: `FAIL: sibling proposal cannot alert after another proposal contracts the request`. Após exigir o pedido ainda `quoted`, GREEN: `commercial-notifications.sql` 115 statements, `notifications-security.sql` 161 e `commercial-security.sql` 176. O teste de expiração usa a data de negócio brasileira, evitando o falso limite na virada do dia UTC. Não são envios externos.

Nos demais pontos o revisor aprovou spec e qualidade/segurança por inspeção: gate financeiro equivalente, DTO sem dados privados, exclusão de rascunhos/clientes externos, revogação, deduplicação, migração sem backfill e navegação autorizada com foco. Revisão de código não é prova de navegador, push ou e-mail real. Esta é a única revisão final deste acompanhamento; a onda de correção é delimitada ao achado e suas consequências testáveis.
