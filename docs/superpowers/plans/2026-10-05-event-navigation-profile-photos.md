# EventCore: abertura de eventos e fotos de perfil

## Resultado autorizado

Um clique em Meus eventos abre a operação em uma tela própria, visível imediatamente, com retorno à lista. Preservar as seis etapas, o dashboard, a navegação móvel e as funções definidas somente na criação. O menu da conta dá acesso às páginas permitidas e a editar dados, foto e portfólio.

O perfil permite uma foto de apresentação e até dez fotos de trabalhos, cada original com até 3 MB, em JPEG, PNG ou WebP. Contratantes podem visualizar as fotos ao abrir o perfil profissional. Exigir declaração de autoria/registro real e ausência de IA; não apresentar a declaração como verificação automática de autenticidade. Não criar imagens ilustrativas de trabalhos.

## Armazenamento e permissões

Bucket privado, imagens normalizadas no servidor com Sharp, sem metadados EXIF, até 1600 px e 3 MB. Rejeitar tipo falsificado, SVG, animação, arquivos inválidos e dimensões excessivas. Upload com token validado e perfil ativo. As chaves administrativas ficam somente no servidor. As imagens são lidas por URLs temporárias assinadas depois de autorização.

Metadados em profile_photos, com uma posição de avatar e dez posições de portfólio. RPCs validam o usuário real, declaração, objeto enviado e cota sob bloqueio do perfil, prevenindo ultrapassagem por requisições simultâneas. Sem escrita direta autenticada nos metadados ou no bucket. Leitura permitida ao dono ativo e a contratantes/equipe autorizados de perfis profissionais ativos, seguindo os critérios do diretório. Substituir avatar só após upload e confirmação; remover arquivos anteriores usando Storage API. Remoção verifica proprietário e permite repetição após falha.

Revisão final: limpeza durável em tabela acessível somente pelo servidor, com gatilho que registra objetos substituídos/removidos dentro da transação. Envio registra caminho com tolerância de 15 minutos antes de subir o arquivo; confirmação remove esse registro atomicamente. Limpeza é repetida nas chamadas de mídia do dono, preserva caminhos ativos e objetos ainda em envio. Remoção confirma metadados antes de apagar Storage. Rejeitar a reutilização de caminho marcado para limpeza. Validar bytes totais do multipart em streaming, inclusive sem Content-Length; rejeitar APNG e oferecer Atualizar fotos para renovar URLs temporárias.

## Execução

1. Reproduzir o clique no celular com verificação falhando; escrever testes de imagem e cota/permissões.
2. Implementar tela de evento e menu, mantendo os fluxos existentes.
3. Criar migração aditiva, APIs de mídia e componentes de perfil/galeria. Não alterar registros existentes.
4. Testar imagens reais como arquivos, autenticação, tipo/tamanho, limite, concorrência, exclusão, acesso ao perfil e navegação em celular/desktop. Testes SQL dentro de transação com rollback.
5. Fazer revisão independente final, corrigir problemas, abrir PR, verificar preview, mesclar e conferir produção e cache do app.

## Verificação

Testes de unidade, typecheck e build; navegador com Supabase simulado nas fronteiras externas, API Next real e processamento real dos bytes; migração e permissões exercitadas no banco real em transações revertidas. Conferir preservação dos dados de operação e que nenhum arquivo de teste foi publicado como portfólio real.
