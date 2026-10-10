# EventCore: e-mail de autenticação com Resend

## Estado e motivo
Em 2026-10-09 o Supabase Auth do EventCore (`mzwlchgxkuqptiqyznqd`) retornou HTTP 429 / `over_email_send_rate_limit` em requisições `/signup`. A configuração SMTP padrão do Supabase não é apropriada para cadastros públicos de produção.

Esta alteração adiciona tratamento amigável dos erros, reenvio de confirmação com bloqueio visual por 60 segundos, preservação do e-mail após um cadastro pendente e testes automatizados. **Ela não configura, por si só, o SMTP e não substitui a confirmação obrigatória.**

## Ativação operacional, em ordem

1. Conectar a conta Resend autorizada pelo proprietário. Criar/usar o plano gratuito (verificar quotas vigentes).
2. Cadastrar o domínio `eventcore.space` no Resend. Publicar **exatamente** os registros DNS que o Resend informar no provedor DNS (GoDaddy, se seguir hospedado lá). Preservar os registros web do domínio, principalmente A/CNAME que levam à Vercel; não substituir inadvertidamente MX de uma caixa postal existente. Aguardar status de domínio verificado (SPF/DKIM e demais requisitos do provedor).
3. Criar uma chave restrita a envio de e-mails e armazená-la **apenas** no campo de senha SMTP do Supabase Auth; não versionar e não enviar em mensagens. No Resend, SMTP padrão: host `smtp.resend.com`, porta `465` (TLS/SSL), usuário `resend`, senha = chave privada Resend. Remetente `no-reply@eventcore.space`, nome `EventCore`.
4. No Supabase do projeto EventCore, navegar para **Authentication > SMTP Settings** e habilitar Custom SMTP com os valores. **Manter confirmação obrigatória habilitada**. Não mudar configurações de OAuth, RLS, tabelas ou segredos Google.
5. Em **Authentication > URL Configuration**, definir **Site URL** = `https://eventcore.space` e conferir as Redirect URLs permitidas (no mínimo `https://eventcore.space/**`; acrescentar `https://www.eventcore.space/**` somente se usado). Há registros antigos com referer `http://localhost:3000`; é indispensável verificar o Site URL atual antes de considerar os links corrigidos.
6. Em **Authentication > Rate Limits**, verificar e ajustar o limite de envio por e-mail para ficar compatível com as quotas reais do Resend e o tráfego esperado, mantendo prevenção de abuso e cooldown de reenvio.
7. Homologar com **um e-mail de teste controlado**: cadastro pendente → mensagem recebida → clique com redirecionamento válido → login → conclusão do perfil → e-mail reenviado quando necessário. Validar estados de erro 429 e link expirado sem expor se e-mail de terceiros existe.
8. Conferir logs de autenticação e entrega no Supabase/Resend, registrar evidências e só depois considerar o envio oficialmente ativo. Usuários bloqueados devem solicitar novo link, sem apagar contas existentes.

Referências:
- https://supabase.com/docs/guides/auth/auth-smtp
- https://supabase.com/docs/guides/auth/redirect-urls
- https://resend.com/docs/send-with-supabase-smtp

## Segurança
Nunca publicar a chave Resend, `service_role` ou credenciais SMTP em GitHub, Vercel client env, imagens ou chats. E-mail de confirmação é ação de autenticação do Supabase, não notificação de marketing. Não desabilitar `Confirm email` como solução para rate limit.
