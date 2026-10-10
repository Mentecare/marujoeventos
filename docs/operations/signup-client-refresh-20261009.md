# Diagnóstico de cadastro repetido e proteção de versão

Em 2026-10-09, após PR #12, houve conta confirmada porém incompleta sem rascunho privado. O cadastro recente não possuía a chave de controle `registration_nonce` que somente a rota servidor cria. Os logs Auth mostram `POST /signup` direto do navegador, sinalizando uma página/PWA antiga ainda aberta. O código atual está publicado na Vercel e usa exclusivamente `POST /api/auth/register`, que armazena um rascunho privado até a confirmação do e-mail.

O SW v10 passa a bloquear tentativas de cadastro direto pelo caminho antigo, evitando a criação silenciosa de novos perfis incompletos em guias antigas controladas pelo SW. A interface atual identifica o fluxo novo com o texto **Cadastro seguro atualizado** e avisa quando há atualização do Service Worker, sem recarregar formulários automaticamente. Não se alteram banco, SMTP, OAuth, notificações, regras comerciais ou dados existentes.

Validação: CI, Vercel READY, abrir uma nova aba `https://eventcore.space`, verificar a identificação do novo cadastro antes de testar. Usuários criados pela versão antiga não têm como recuperar documento ou especialidades que não chegaram ao servidor; devem concluir apenas os campos ausentes na mesma conta, sem criar uma duplicata.
