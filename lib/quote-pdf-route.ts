import type { SupabaseClient } from '@supabase/supabase-js';
import type { SaleQuoteDTO } from './commercial.ts';
import { commercialApi } from './commercial.ts';
import { ActorError, commercialActor } from './actor-server.ts';
import { renderQuotePdf, type QuotePdfDetails } from './quote-pdf.ts';
import { quoteIssuerLogo } from './quote-pdf-logo.ts';

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type QuotePdfRouteDependencies = {
  actor?: typeof commercialActor;
  fetchQuote?: (db: SupabaseClient, id: string) => Promise<SaleQuoteDTO>;
  render?: typeof renderQuotePdf;
  issuerLogo?: typeof quoteIssuerLogo;
};

function failure(status: number, code: string): Response {
  return Response.json({ error: code }, { status, headers: { 'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff' } });
}

export async function quotePdfResponse(request: Request, id: string, dependencies: QuotePdfRouteDependencies = {}): Promise<Response> {
  if (!uuidPattern.test(id)) return failure(404, 'quote_not_found');
  const actor = dependencies.actor ?? commercialActor;
  const fetchQuote = dependencies.fetchQuote ?? ((db, quoteId) => commercialApi(db).quote(quoteId));
  const render = dependencies.render ?? renderQuotePdf;
  let quote: SaleQuoteDTO;
  let callerDb: SupabaseClient;
  try {
    const caller = await actor(request);
    callerDb = caller.db;
    const fetched = await fetchQuote(caller.db, id);
    if (!fetched || fetched.id !== id) return failure(404, 'quote_not_found');
    quote = fetched;
  } catch (error) {
    if (error instanceof ActorError) return failure(error.status, error.status === 401 ? 'unauthorized' : error.status === 403 ? 'forbidden' : 'commercial_unavailable');
    // RPC authorization, not-found and tenancy errors intentionally share a
    // generic response so a quote identifier cannot be used for enumeration.
    return failure(404, 'quote_not_found');
  }
  const requestedDetails = new URL(request.url).searchParams.get('details');
  const details: QuotePdfDetails = requestedDetails === 'units' ? 'units' : 'totals';
  if (details === 'units' && !quote.show_unit_prices) return failure(400, 'unit_prices_not_available');
  try {
    const issuerLogo = await (dependencies.issuerLogo ?? quoteIssuerLogo)(callerDb, quote.issuer.id);
    const pdf = await render(quote, { details, issuerLogo });
    const filename = `orcamento-eventcore-${id}.pdf`;
    return new Response(new Uint8Array(pdf), { status: 200, headers: {
      'Content-Type': 'application/pdf',
      'Content-Disposition': `attachment; filename="${filename}"`,
      'Cache-Control': 'private, no-store',
      'X-Content-Type-Options': 'nosniff',
    } });
  } catch (error) {
    if(error instanceof Error&&error.message==='unsupported_pdf_text')return failure(422,'unsupported_pdf_text');
    return failure(500, 'pdf_unavailable');
  }
}
