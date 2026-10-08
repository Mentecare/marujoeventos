# Ativação dos fluxos alinhados — 08/10/2026

Este registro sucede os checkpoints históricos anteriores. A autorização explícita do usuário em 08/10 desbloqueou o PR9, as cinco migrações revisadas, a publicação coordenada no domínio existente e os novos segredos de push/dispatcher inicialmente no Preview da branch. Nenhuma autorização foi solicitada novamente para esses itens.

## Versão publicada e acesso

- [EventCore](https://eventcore.space/): produção `dpl_7XfURTP5korgmjarqoH8LGZB32jR`, target production, READY, commit `cea9a61befb4263a337e2f8c6290693b6638470d`.
- [PR9](https://github.com/Mentecare/marujoeventos/pull/9): integrado com head esperado `e0b165f3b791e6aa3d131d773e2c34950d616b3e`. Comparação head→merge retorna zero arquivos alterados: o merge mantém o código aprovado.
- [CI aprovado](https://github.com/Mentecare/marujoeventos/actions/runs/37810524189): SUCCESS; 87 testes, build/type/trace, sete cenários PDF/dispatcher/browser e 21 jornadas de perfis/viewport. Seus transports externos são isolados; isso não é entrega real.
- Preview recompilado após os novos segredos: `dpl_Hdb9eVLTWdEjQMuhtLSXMDBY94ZW`, READY, API target staging (ambiente Preview), mesmo head aprovado. Não divulgar links de bypass.

Na interface, use **Eventos → Novo evento → Funções e vagas → Dias de contratação**. Funções, quantidade e dias iniciais continuam definidos somente na criação. Clicar em um evento abre suas etapas; pagamentos/financeiro aparecem conforme autorização.

O menu da conta permite editar dados, foto, portfólio e **Notificações e preferências**. Contas comerciais sem complemento usam **Meu perfil → Identificação e atividade comercial** para informar CPF ou CNPJ e a atividade; isso não reclassificou automaticamente os registros anteriores. Na área comercial, use os pedidos/propostas e o editor do orçamento para prévia e PDF. O acesso exige a organização e o participante autorizados.

## Banco e preservação comprovados

Supabase EventCore `mzwlchgxkuqptiqyznqd`, PostgreSQL17.11, passou de 29 para **34 migrações**. As cinco SQL aprovadas foram aplicadas em ordem por apply_migration; nenhum reset, remoção de tabela ou reinterpretação de valores históricos foi feito.

| Arquivo revisado | Versão inicial da aplicação pelo serviço | Versão reconciliada com o repositório |
| --- | --- | --- |
| eventcore_commercial_foundation | 20261008225342 | 20261005194714 |
| eventcore_workflows_history | 20261008225358 | 20261006082244 |
| eventcore_work_finance_index | 20261008225400 | 20261006203715 |
| eventcore_notifications_public_sharing | 20261008225404 | 20261006204723 |
| eventcore_final_flow_corrections | 20261008225407 | 20261008022315 |

O serviço gerou timestamps atuais. Depois da aplicação, uma transação guardada reconciliou **somente os cinco novos marcadores**, por nome/versão/hash exatos, com os arquivos revisados. O SQL registrado permaneceu igual; os 29 marcadores e seus statements anteriores permaneceram iguais. A lista remota foi novamente conferida: 34 versões alinhadas, sem reaplicar SQL nem alterar os arquivos históricos. Referência: [documentação oficial de migration repair](https://supabase.com/docs/reference/cli/supabase-migration-repair).

Foi capturado um baseline privado das 26 tabelas originais, das definições/ACL/RLS/constraints/triggers/indexes/buckets e do estado anterior de produção. Tokens de Auth e ciphertext OAuth não foram recuperados; o hash da conexão Google foi calculado no banco. A comparação imediatamente antes das migrações, depois e após os fixtures manteve todos os hashes/contagens das **colunas originais** iguais. O archive privado tem SHA256 `ac1c47a229bd51cc99a34802f675a93fd5466313ac4d709d5dd3be278b8ee7e0`; ele não faz parte do Git.

## Verificações efetivas e limites

| Verificação | Evidência atual |
| --- | --- |
| Contratação, termos/dias, venda/remuneração, trabalho externo, histórico/avaliações e isolamento | workflows-security executado no banco hospedado, com papéis reais do PostgreSQL, assertions e BEGIN/ROLLBACK: PASS |
| Financeiro independente e coordenador sem/com autorização; legado comprador sem nova contratação direta | interface-finance-security hospedado, assertions e rollback: PASS |
| Público/privado, convites, preferências, outbox/leases, retentativas e anonimato | notifications-security hospedado com rollback: PASS após correção do predicado do teste |
| Declaração de foto real, limite10, dono/contratante/anônimo e bucket privado | profile-photos hospedado, metadata Storage, assertions e rollback: PASS; nenhum binário enviado |
| Preservação depois dos testes | 26 hashes originais iguais; dois usuários originais; zero fixture fixo restante; zero contratos/propostas/notificações/outbox/dispositivos; dois objetos de foto originais |
| Unidades após os ajustes do teste | npm test: 87/87, zero falhas/skip; git diff --check: PASS |
| Publicação | Produção READY, aliases eventcore.space/www mapeados ao deployment correto; raiz200 e sw.js200; tela pública de login observada no navegador |
| Logs | Nenhum grupo error/fatal retornado para esta produção na janela consultada de30min; limita-se às requisições exercitadas |
| PDF HTTPS sem JWT | Fetch retorna401, mas o wrapper não forneceu corpo da aplicação; navegação ao endpoint foi ERR_BLOCKED_BY_CLIENT. Não classificado como prova de autorização da aplicação |
| HTTPS com JWT, PDF hospedado autorizado, OAuth e upload binário | Ainda não comprovados nesta ativação; não equivalem aos fixtures SQL ou transports de CI |

Os fixtures usam a implementação hospedada, sem substituir Auth/Storage functions por shims. As claims são definidas no contexto SQL dos papéis de teste; **não são uma sessão GoTrue/JWT por HTTPS**. Nenhum registro de avaliação/contrato/pagamento de teste foi persistido e nenhum destinatário real recebeu divulgação.

O teste de notificações original falhou porque o regex procurava220/440 em todo JSON, incluindo UUID aleatório. Uma reprodução determinística com UUID seguro contendo esses números gerou a mesma rejeição RED. A mudança é somente no utilitário temporário de teste: normaliza UUIDs antes da busca, com controles independentes que continuam rejeitando remuneração220 e texto privado, e aceitam também UUID aninhado de proposta contendo280/5600. A suíte hospedada final passou. O INSERT de especialidades do fixture workflows foi limitado ao seu prefixo UUID, para não alcançar perfis reais. **Código de produção e as cinco migrações aprovadas permanecem iguais.**

A tentativa de verificar HTTPS autenticado pelo runtime retornou `network approval was cancelled before a decision was returned`. Não houve leitura de credenciais existentes, extração de sessão do navegador ou inserção de senha por API de baixo nível. O navegador abriu o login; uma sessão de homologação fornecida pelo fluxo seguro ainda é necessária para essas jornadas. Não confundir esse limite de teste com falha comprovada da autenticação do produto.

## Configuração e dependências de entrega

As 17 entradas existentes de Google/Supabase continuam com os mesmos IDs, nomes, tipos e escopos. Foram criadas e verificadas **somente no Preview da branch** as chaves pública/privada VAPID e NOTIFICATION_DISPATCH_SECRET. O subject público existente foi preservado. Há21 entradas; nenhum segredo foi escrito no repositório, relatório ou exposto em resposta.

- Central e permissões: banco hospedado verificado.
- Push: credenciais Preview salvas, recompilação READY. Registro real do dispositivo, consentimento e entrega física ainda pendentes. Os segredos **não estão em produção**, para preservar o estágio inicial autorizado.
- E-mail: RESEND_API_KEY e NOTIFICATION_EMAIL_FROM continuam ausentes. Faltam serviço, domínio/remetente verificado e destinatário de teste. Não houve simulação de envio.
- Scheduler: não ativado. Antes de agendar, provar endpoint autorizado e envio para dispositivo/destinatário de teste. Os scripts existentes de setup/recover permanecem preservados; não foi criado cron ou serviço adicional.
- Reputação pública: declaração do usuário para fotos legítimas; não há alegação de detecção infalível de imagem de IA.
- DEP0169 de web-push3.6.7 permanece acompanhamento upstream anterior, sem supressão/vendor patch.

## Advisors e recuperação

Os advisors foram comparados antes/depois. Não são “limpos”: antes havia cleanup RLS sem policy1, definer autenticado20, leaked-password protection desativada1, índices sem uso21 e policies permissivas múltiplas9. Depois: RLS sem policy5 (inclui as quatro filas privadas intencionalmente sem acesso browser), definer anônimo1 (a prévia pública sanitizada), definer autenticado68 (RPCs com guards testados), leaked-password protection1; FK sem índice19, auth initplan6 e índices sem uso28. As nove duplicidades permissivas anteriores não foram retornadas. Otimização dos novos avisos de performance fica registrada; não houve mudança adicional de infraestrutura/segurança por preferência técnica.

A atribuição automática de domínios foi suspensa durante a preparação; a produção antiga permaneceu ativa até o build compatível estar READY e os testes hospedados passarem. A promoção mapeou os domínios ao mesmo build de produção preparado. A retomada da atribuição automática foi aceita pela API ao final; o conector não inclui esse campo no GET normalizado.

Recuperação preserva registros/evidências e a RLS estrita. A produção anterior `dpl_EzuwQTc2uJAz3UFS6JCN7zwQuC3w`/mainf37f6b3 é referência, **não rollback isolado seguro** contra os guards novos: parar novos callers, manter filas sem scheduler, revogar apenas execute de RPCs novos mutantes/worker quando necessário e preparar definições compatíveis individualmente revisadas a partir do baseline. Nunca apagar snapshots, termos, contratos, pagamentos ou avaliações, reabrir financeiro global, atribuir organizações históricas ou reexecutar migrações antigas em massa.

O checkpoint estruturado está em [2026-10-08-activation-checkpoint.json](2026-10-08-activation-checkpoint.json). Registros anteriores permanecem como histórico; este arquivo e o PR9 atualizado registram a ativação atual.

