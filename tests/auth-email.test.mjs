import test from "node:test";
import assert from "node:assert/strict";
import { emailAuthError } from "../lib/auth-email.ts";

test("email sending quota errors receive actionable Portuguese feedback",()=>{
  assert.match(emailAuthError({code:"over_email_send_rate_limit",status:429,message:"email rate limit exceeded"}),/limite temporário/);
  assert.match(emailAuthError({status:429,message:"Too many requests"}),/Muitas tentativas/);
});
test("unconfirmed login and expired links point users to resend",()=>{
  assert.match(emailAuthError({code:"email_not_confirmed",message:"Email not confirmed"}),/Reenviar e-mail/);
  assert.match(emailAuthError({message:"Email link is invalid or has expired"}),/novo link/);
});
test("other errors remain handled by existing error adapter",()=>{
  assert.equal(emailAuthError({code:"custom_unrelated_error",message:"something else"}),null);
  assert.equal(emailAuthError(null),null);
});

