# EventCore — completar avisos privados comerciais

Escopo de execução já autorizado em 09/10/2026, complementando `2026-10-05-aligned-flows.md`. Na versão publicada `cea9a61`, pedidos de contratação e propostas enviadas não possuem gatilhos de notificação. A confirmação de contrato já possui. Corrigir apenas essa lacuna, reaproveitando central, outbox, dispatcher, preferências e comercial existentes.

- Um pedido novo avisa somente proprietário e membros com autorização financeira da prestadora destinatária, compatível com a autorização do workspace comercial. Coordenadores sem essa autorização, freelancers, solicitante e organizações estranhas não recebem esse aviso.
- Uma proposta enviada avisa somente proprietário e membros com autorização financeira da agência/cenografia destinatária. Rascunhos e orçamentos para clientes externos sem conta não geram divulgação. O aceite continua usando a notificação de contrato existente.
- Títulos e links são genéricos: `/?request=<UUID>` e `/?proposal=<UUID>`. Não incluir cliente, descrição, documentos, valores, remuneração ou margem.
- A abertura resolve a organização autorizada e o registro exato no comercial existente, com foco acessível. Identificador conhecido não concede acesso.
- A elegibilidade é revalidada ao consultar a central e antes do envio. Pedido cancelado ou contratado não gera novo alerta de pedido; proposta expirada/aceita/cancelada não gera novo envio de proposta. A central pode preservar a proposta aceita enquanto autorizada.
- Preservar inscrições e preferências, deduplicação, retentativas, canais, pausa e cadência. Migração aditiva sem backfill histórico e com recuperação documentada.
- Não ativar cron nem enviar push/e-mail antes da validação controlada com dispositivo e destinatário identificados pelo usuário. Sem novo serviço pago. Nenhuma mudança visual além do destino e foco dos links.

Provas: regressão RED/GREEN de links no aplicativo/service worker; teste SQL transacional de destinatários, estado e isolamento; jornadas HTTPS com sessões GoTrue reais de sete contas temporárias identificadas, sem destinatários externos; preservação dos hashes originais. Testes locais com transporte isolado continuam classificados separadamente.
