# EventCore: eventos e portfólio

## Verificações

- 24 testes de unidade: domínio e financeiro existentes, criação de funções, formatos reais de imagem, orientação, metadados, tamanho/dimensões, animação WebP/APNG, declaração e limite real do corpo multipart sem Content-Length.
- TypeScript e build Next.js aprovados.
- API Next real e Sharp, com Auth/PostgREST/Storage simulados somente na fronteira externa: autenticação, campos, imagem inválida/grande, upload normalizado, troca de avatar, cota de dez fotos, limpeza após falha, perda de resposta depois de commit, remoção idempotente, isolamento entre donos, leitura do contratante, renovação de URLs e recuperação de objeto ausente. Um upload chunked excessivo é recusado antes de salvar; o transporte pode responder 413 ou encerrar a conexão que ainda está enviando bytes.
- SQL executado no Supabase real em transação revertida: cota, declaração, validação do objeto, avatar único, proprietário/contratante, bloqueio de inativos/anon, escrita direta negada, limpeza durável também em chamada direta de RPC, término da etapa de envio e recusa de caminhos marcados para limpeza.
- Navegação e abertura de eventos: 105 verificações, dois tipos de perfil e sete larguras (360–1280 px). Detalhe visível, lista/formulário substituídos, seis etapas e retorno à lista.
- Criação de eventos em 360/390/1280 px: múltiplas funções, remoção do rascunho, validação, erro com preservação dos campos, bloqueio de duplo envio, evento confirmado mesmo com falha de atualização e gestão de publicação das vagas existentes.

## Revisão e armazenamento

Revisão independente encontrou problemas de limpeza, remoção parcial e corpo de upload sem limite efetivo. Corrigidos com fila persistente acessível somente pelo servidor, gatilho transacional, remoção dos metadados antes da limpeza, proteção de objetos ativos/em envio e leitura limitada em streaming. APNG é rejeitado e Atualizar fotos renova os links. Um objeto ausente permanece removível sem bloquear a coleção.

Bucket privado, originais até 3 MB, JPEG/PNG/WebP; saída WebP até 1600 px. Uma foto de perfil e dez fotos de trabalhos por conta. Fotos reais e ausência de IA são declarações obrigatórias do autor, sem promessa de detecção automática de autenticidade.

Migrações aplicadas: 20261005103123 e 20261005143141. Verificação de segurança: fila sem políticas para usuários por ser exclusiva do servidor; RPCs SECURITY DEFINER têm validação explícita do ator e privilégios restritos. Avisos anteriores de configuração de senha não foram alterados nesta atualização.

Nenhuma foto/arquivo/limpeza de teste persistiu no Supabase. Eventos, funções e contratações conservaram os mesmos registros e hashes durante a validação.

## Reproduzir a API local

```bash
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:18765 NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=preview-publishable-key npm run build
node tests/profile-photos.integration.mjs
npm test
npm run typecheck
```

As fixtures são apenas pixels/arquivos de validação, nunca imagens publicadas como trabalhos reais.
