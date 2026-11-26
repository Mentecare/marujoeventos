# Operação de eventos: turnos, substituições e pagamentos parciais

Esta entrega amplia o EventCore existente (`Mentecare/marujoeventos`), preservando o desenho aprovado e todas as migrações anteriores. Não incorpora o sistema financeiro separado da Marujo.

## Fluxo entregue

- **Antes do evento:** orçamento e margem, funções/vagas, convites privados, condições aceitas e confirmação continuam no fluxo existente. A aba **Turnos** permite organizar profissionais da mesma função por dia/horário e ponto de encontro, dentro das datas do evento, com bloqueio de sobreposição do mesmo profissional entre eventos.
- **Equipe:** a substituição preserva a contratação anterior, registra o motivo, cria outro convite que exige aceite próprio e replica os turnos disponíveis. Presença ou pagamento anterior bloqueiam a substituição para preservar evidências. A operação é atômica: conflito desfaz a tentativa inteira.
- **Financeiro:** adiantamento, parcela e quitação registram pagamentos já realizados, com valor, data, forma, referência do comprovante e observação. Não executam transferências. O total contratado continua separado do total pago e do saldo. Valores acima do saldo e quitação incompleta são rejeitados no banco.
- **Conferência:** painel financeiro e detalhe individual incluem as parcelas, sem contar duas vezes o pagamento previsto legado. O profissional vê apenas seus recebimentos e seus turnos. Operadores sem permissão financeira não recebem valores.
- **Presença:** check-in, check-out e validação existentes foram preservados. A presença continua por contratação; não é um ponto independente por turno.

Não há upload de arquivo novo nesta entrega: o campo de comprovante armazena uma referência. O histórico de pagamentos, definições dos turnos e substituições é imutável. Depois de uma parcela, as condições aceitas não podem ser revisadas pelo fluxo normal. Correções, estornos e alterações de turnos já iniciados precisam de um fluxo específico futuro.

## Validação reproduzível

```sh
npm ci
npm test
npm run typecheck
npm run test:database
npm run build
```

O build requer as variáveis públicas do Supabase descritas em `.env.example`. Não inserir credenciais de produção em documentação ou commits.

O teste de banco usa PostgreSQL isolado via PGlite e executa todas as migrações na ordem. Auth e Storage têm estruturas auxiliares exclusivamente de teste. São executadas quatro suítes SQL: operações/pagamentos, workflows, privacidade financeira da interface e segurança comercial. Nenhum dado de usuário é usado ou alterado. Essa validação não substitui a homologação no Supabase hospedado.

Cobertura nova: parcelas e saldo em centavos, prevenção de duplicidade por chave, pagamento excessivo/futuro, aceite obrigatório, bloqueio de revisão após parcela, compatibilidade da quitação antiga, turnos fora do evento, conflito entre eventos, isolamento entre profissionais e organizações, substituição sem reaproveitar aceite e reversão de tentativa inválida. As suítes anteriores permanecem inalteradas.

## Ativação pendente

O Supabase do EventCore (`mzwlchgxkuqptiqyznqd`) estava **INACTIVE** em 26/11/2026. A restauração foi recusada pelo limite de dois projetos gratuitos ativos da organização. Nenhum outro projeto foi pausado e nenhum recurso pago foi criado.

Após liberar capacidade na organização ou disponibilizar outra opção autorizada:

1. Reativar o projeto existente; preservar banco, usuários e evidências.
2. Conferir o histórico remoto de migrações. Aplicar somente migrações pendentes, incluindo `20261126150655_eventcore_operations_payroll.sql`, primeiro em homologação. Não recriar o banco nem reaplicar migrações antigas manualmente.
3. Homologar com contas reais autorizadas de prestadora, operação sem financeiro, trabalhador e comprador: convite/aceite, turnos, presença, substituição, adiantamento, parcela e saldo final.
4. Confirmar a privacidade dos valores, referências e exportações e então promover a aplicação.

A migração é aditiva. Em caso de incidente, interromper novas gravações pelas RPCs e retornar a aplicação à versão anterior, preservando as tabelas novas e o histórico. A versão anterior não apresenta as parcelas novas corretamente; não continuar lançamentos financeiros por ela até reconciliar a situação. Não excluir evidências para fazer rollback.
