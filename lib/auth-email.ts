/** Human-readable authentication errors, independent of the email transport. */
type AuthErrorLike = {code?: string|null; message?: string|null; status?: number|null};
export function emailAuthError(error:unknown):string|null {
  if(!error||typeof error!=="object")return null;
  const value=error as AuthErrorLike;
  const code=String(value.code||"").toLowerCase();
  const message=String(value.message||"").toLowerCase();
  if(code==="over_email_send_rate_limit"||/email rate limit exceeded|too many email requests/.test(message))return "O serviço de e-mail atingiu o limite temporário de envios. Aguarde antes de tentar novamente. Se persistir, entre em contato com o suporte do EventCore.";
  if(code==="over_request_rate_limit"||value.status===429)return "Muitas tentativas em pouco tempo. Aguarde antes de tentar novamente.";
  if(code==="email_not_confirmed"||message.includes("email not confirmed"))return "Seu e-mail ainda não foi confirmado. Confira sua caixa de entrada ou use Reenviar e-mail de confirmação.";
  if(code==="email_address_not_authorized"||message.includes("email address not authorized"))return "O serviço de e-mails não está configurado para este destinatário. Entre em contato com o suporte do EventCore.";
  if(code==="otp_expired"||/email link is invalid|token has expired|expired token/.test(message))return "O link de confirmação expirou ou é inválido. Solicite um novo link na tela de entrada.";
  return null;
}

