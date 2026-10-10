# Cadastro único com e-mail confirmado

## Problema
Em 09/10/2026, usuários informaram todos os dados no cadastro público (incluindo CPF/CNPJ e especialidades), mas a UI antiga fazia `auth.signUp` apenas com nome/telefone/tipo em `user_metadata`. A RPC `complete_profile` era executada somente com sessão imediata, que não existe quando a confirmação por e-mail está ativa. Após validar o endereço, o usuário precisava preencher o formulário novamente.

## Fluxo novo (ativação depende da migração)
- A rota servidor `POST /api/auth/register` valida documento e especialidades, faz a inscrição de autenticação no Supabase e armazena um rascunho completo em `pending_signup_profiles` usando exclusivamente `service_role`.
- O rascunho tem RLS habilitado, sem acesso anon/authenticated, chave primária referenciando o usuário, e expiração em 30 dias. Documentos privados **não** entram em JWT, `user_metadata`, logs ou localStorage.
- Ao confirmar e entrar, o cliente chama `complete_pending_signup()` uma única vez por inicialização. A função definer autentica o usuário via `auth.uid()`, exige e-mail confirmado e chama `complete_profile` em transação. Isso cria especialidades, identidade privada e atividade conforme o fluxo existente e remove o rascunho.
- A operação preserva contas existentes, não regrava perfis finalizados e continua permitindo edição voluntária de perfil. Se a transação falhar, o rascunho permanece privado para uma segunda tentativa.
- Emails de autenticação saem pelo SMTP Resend configurado no Supabase, não pela rota Next.js.

## Ordem segura de promoção
1. Verificar testes/CI do PR.
2. **Antes de publicar o novo frontend** aplicar somente a migração SQL adicional do PR no projeto Supabase EventCore `mzwlchgxkuqptiqyznqd` (salva no GitHub). Verificar RLS, grants e função.
3. Mesclar o PR e aguardar a publicação Vercel pronta.
4. Homologar cadastro com um documento de teste exclusivo e e-mail novo, confirmação via e-mail (mesmo ou outro dispositivo), entrada sem formulário repetido, especialidades, privacidade e atividades para equipe/empresa.
5. Validar acesso de usuário legado, reenvio, CPF duplicado e concorrência; nenhum dado comercial deve mudar.

## Limitações e retenção
- Cadastros iniciados antes desta implantação não tiveram o formulário completo guardado; não é possível reconstruir CPF ou especialidades a partir de `user_metadata`. Usuários legados precisam finalizar uma vez, se ainda incompletos.
- Rascunhos completados são removidos imediatamente. Para os expirados, a rota de registro executa limpeza best-effort nos cadastros subsequentes. Configurar uma rotina agendada de purga, com verificação operacional.
- Para problemas com spam, verificar DKIM/SPF/DMARC, templates, reputação e logs de entrega; verificar domínio no Resend não garante posição na caixa de entrada.

## Testes e privacidade
Não usar documentos reais em fixtures. Não registrar senhas, tokens nem payloads em console, Analytics ou APM. Limites de e-mail permanecem sujeitos às políticas do Supabase e Resend.
