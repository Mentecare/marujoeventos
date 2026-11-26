# EventCore → Cloudflare: preparação de implantação e recuperação

Estado em 26/11/2026: preparação de hospedagem concluída; migração integral do backend e publicação ainda pendentes. Não considerar esta branch um EventCore independente do Supabase.

## Entrega verificável

- Next.js existente preservado e compilado com OpenNext 1.20.19 para Workers; atualização de compatibilidade de Next 15.5.27 para 15.5.29, sem recriação do projeto.
- `wrangler.jsonc` para o Worker `eventcore-cloudflare`, assets e observabilidade. Sem rotas de produção/custom domains: o endereço oficial permanece no provedor atual.
- Scripts `build:cloudflare`, `preview:cloudflare`, `deploy:cloudflare` e `typegen:cloudflare`.
- Arquivo privado de recuperação em D1 com verificação de integridade, contagem e registros imutáveis. Esse arquivo é exclusivamente uma fonte para restauração revisada; não substitui as tabelas operacionais, RPCs ou autenticação.
- Conversor `scripts/cloudflare-recovery.mjs`: exige contagens completas, rejeita linhas duplicadas e campos de segredo inesperados e mantém o payload original. Não recalcula valores monetários ou troca UUIDs.
- Nenhum outro projeto pausado e nenhum recurso pago contratado. Em uma etapa posterior, via plugin, foram criados o D1 e um Worker de preparação, sem alterar o domínio oficial.

## Compilação

```sh
npm ci
npm test
npm run typecheck
npm run build:cloudflare
npx wrangler deploy --dry-run --outdir /tmp/eventcore-cloudflare-dry-run
```

O build recebe as variáveis públicas de `.env.example`. As credenciais de servidor são secrets e não devem constar do Git, do Wrangler vars ou de arquivos públicos. O bundle da preparação ainda depende dos clientes e RPCs Supabase existentes (`EVENTCORE_BACKEND=supabase`). Hospedar este bundle no Cloudflare, por si só, não remove essa dependência.

A compilação OpenNext e o dry-run do Wrangler passaram. O bundle comprimido foi de aproximadamente 1,62 MiB. A inicialização com `wrangler dev` neste executor falhou em `os.networkInterfaces` (`uv_interface_addresses`); isso não equivale a uma validação de runtime no Cloudflare. Há um aviso de chave duplicada emitido por dependência de fontes/PDF; a geração efetiva do PDF ainda precisa ser homologada em Workers.

## Recuperação privada

Foi localizado `eventcore-private-recovery-20261008.zip`, capturado em **08/10/2026 às 22:49:04 UTC**. O snapshot inclui dados de 26 tabelas: 38 registros foram arquivados localmente nas 23 tabelas elegíveis. As contagens do arquivo foram verificadas. O snapshot é anterior à data desta entrega; ele não comprova que não houve mudanças posteriores.

Três tabelas são excluídas explicitamente: `google_oauth_connections`, `integrations` e `profile_private_identity`. Não reutilizar tokens, chaves, hashes de identificação ou conexões OAuth no novo backend sem um processo específico. As fotos do backup são metadados; os arquivos dos objetos também precisam ser recuperados. O backup não fornece exportação completa de usuários/senhas do Auth. Novos acessos devem ser vinculados com verificação de identidade, sem atribuir contas apenas por uma correspondência não verificada de e-mail.

Os arquivos com dados reais estão somente em diretórios privados ignorados pelo Git. O SQL versionado contém exclusivamente a estrutura vazia. A importação de teste foi feita com `wrangler d1 --local`, sem upload de dados reais ou gravações remotas.

```sh
# Execute sobre uma cópia privada do JSON extraído do ZIP.
node scripts/cloudflare-recovery.mjs snapshot.json cloudflare/private/archive.sql
# O UUID real está configurado; --local abaixo continua sendo uma validação local.
npx wrangler d1 migrations apply EVENTCORE_DB --local --config cloudflare/wrangler.d1.jsonc
npx wrangler d1 execute EVENTCORE_DB --local --config cloudflare/wrangler.d1.jsonc --file cloudflare/private/archive.sql
```

`cloudflare/wrangler.d1.jsonc` foi atualizado com o UUID do banco real. A migração `0001_recovery_archive.sql` já foi aplicada remotamente e registrada em `d1_migrations`; não reaplicar seu SQL manualmente. Nenhum snapshot foi importado no banco remoto. O estado inicial do arquivo é `unreconciled`; importar um snapshot não o promove automaticamente a dados atuais ou a um sistema pronto.

## Pendências para a migração integral autorizada

1. A conexão autenticada pelo plugin já foi verificada. D1 e Worker inicial foram criados. Habilitar R2 no painel, autorizar Cloudflare Workers/Pages no GitHub para `Mentecare/marujoeventos` e confirmar o caminho do domínio, que não consta da conta Cloudflare.
2. Recuperar/reconciliar os dados atuais ou validar formalmente o recorte histórico disponível. Não recriar contas existentes sem o vínculo seguro e não apagar o Supabase.
3. Converter o esquema operacional PostgreSQL para D1 e portar as regras hoje presentes em RPCs, triggers e RLS para uma API autenticada. Preservar a separação entre preço de venda e remuneração, permissões por organização, aceite, operações atômicas, idempotência e evidências financeiras.
4. Implementar autenticação, verificação e recuperação de conta, referências/arquivos privados em R2, notificações e integrações. Não tratar chamadas de RPC não convertidas como sucesso nem retornar dados fictícios.
5. Testar no Worker real com perfis de comprador, prestadora, operação sem financeiro e profissional: cadastro, convites, orçamento/PDF, turnos, presença, substituição, parcelas, saldo, arquivos e exportações. Repetir a cobertura de isolamento e concorrência no D1.
6. Somente após essa validação, ativar o backend Cloudflare, publicar e direcionar `eventcore.space`. Manter uma forma de retornar a hospedagem anterior, sem apagar dados ou evidências.

A autorização do usuário para a migração já existe. Não é necessária nova autorização genérica para continuar. As dependências concretas são acesso autenticado à conta e recuperação/reconciliação do histórico antes do corte de produção.

## Recursos provisionados via plugin — 26/11/2026

- Conta: `bc93540cad47c0397ef19e42f12ba1ee`.
- Banco D1 `eventcore`: `67010f9d-7fa7-4cf8-8bbe-880515321855`, região primária ENAM. As três tabelas de recuperação e os dois triggers de imutabilidade foram conferidos no banco real. Migração registrada em `d1_migrations`. Contagens verificadas: **zero registros privados e zero snapshots importados**.
- Subdomínio Workers da conta: `douglas-eventcore`.
- Worker `eventcore-cloudflare`: tag `39166b68a3bb4814836c8123263fbb06`, vinculado ao D1. Código de preparação em `cloudflare/bootstrap-worker.mjs`, logs/traces ativos e URLs de preview desativadas.
- O bootstrap aceita somente GET /health, sem revelar dados; as demais rotas retornam 503. Não é o aplicativo EventCore funcional. A versão compilada deverá substituí-lo após a validação do backend.
- A publicação do bootstrap e a vinculação D1 foram confirmadas pela API. O teste HTTP /health não pôde ser concluído: a ferramenta de leitura web informou endereço inacessível. Não considerar runtime da aplicação homologado.
- Listar R2 retornou **403, código 10042**, pedindo habilitação no dashboard. Não foi iniciado um plano ou cadastro de cobrança.
- Criar a conexão de build com o GitHub retornou **404, código 8000008**, informando projeto desconectado da conta Git. Não foram criados tokens de build ou autorizações mais amplas.
- A consulta de zonas para `eventcore.space` retornou lista vazia. DNS e domínio de produção não foram alterados.
- O executor da sessão ficou indisponível nesta continuação. A compilação anterior e seus testes continuam como evidência da preparação, não como validação de código novo ou do backend D1.
