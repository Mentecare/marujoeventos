"use client";

import { useEffect, useState } from 'react';
import type { SaleQuoteDTO } from '@/lib/commercial';
import { supabase } from '@/lib/supabase-browser';

export function QuotePdf({ quote }: { quote: SaleQuoteDTO }) {
  const [details, setDetails] = useState<'totals' | 'units'>(quote.show_unit_prices ? 'units' : 'totals');
  const [url, setUrl] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => () => { if (url) URL.revokeObjectURL(url); }, [url]);

  async function openPdf(download: boolean) {
    setBusy(true);
    setError('');
    try {
      const { data } = await supabase.auth.getSession();
      if (!data.session?.access_token) throw new Error('Sessão expirada. Entre novamente para gerar o PDF.');
      const response = await fetch(`/api/quotes/${quote.id}/pdf?details=${details}`, {
        headers: { Authorization: `Bearer ${data.session.access_token}` },
        cache: 'no-store',
      });
      if (!response.ok) throw new Error(response.status === 400 ? 'Este orçamento não permite mostrar valores unitários.' : 'Não foi possível gerar o orçamento agora.');
      const objectUrl = URL.createObjectURL(await response.blob());
      setUrl(previous => { if (previous) URL.revokeObjectURL(previous); return objectUrl; });
      if (download) {
        const link = document.createElement('a');
        link.href = objectUrl;
        link.download = `orcamento-eventcore-${quote.id}.pdf`;
        link.click();
      }
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Não foi possível gerar o orçamento agora.');
    } finally {
      setBusy(false);
    }
  }

  return <div className="quotePdfTools">
    <div className="quotePdfOptions">
      <span className="subtle">PDF para o cliente</span>
      {quote.show_unit_prices && <label className="check"><input type="radio" name={`pdf-details-${quote.id}`} checked={details === 'units'} onChange={() => setDetails('units')} /> Totais e unitários</label>}
      <label className="check"><input type="radio" name={`pdf-details-${quote.id}`} checked={details === 'totals'} onChange={() => setDetails('totals')} /> Somente totais</label>
    </div>
    <div className="actions">
      <button className="btn secondary" type="button" disabled={busy} onClick={() => void openPdf(false)}>{busy ? 'Gerando…' : 'Visualizar PDF'}</button>
      <button className="btn ghost" type="button" disabled={busy} onClick={() => void openPdf(true)}>Baixar PDF</button>
    </div>
    {error && <p className="error" role="alert">{error}</p>}
    {url && <iframe className="quotePdfPreview" title={`Prévia do orçamento ${quote.title}`} src={url} />}
  </div>;
}
