import { quotePdfResponse } from '@/lib/quote-pdf-route';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  return quotePdfResponse(request, (await params).id);
}
