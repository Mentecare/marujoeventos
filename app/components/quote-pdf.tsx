"use client";

import { useEffect, useRef, useState } from 'react';
import type { SaleQuoteDTO } from '@/lib/commercial';
import { supabase } from '@/lib/supabase-browser';

export function QuotePdf({ quote }: { quote: SaleQuoteDTO }) {
  const [details, setDetails] = useState<'totals' | 'units'>(quote.show_unit_prices ? 'units' : 'totals');
  const [preview, setPreview] = useState<{ key: string; url: string } | null>(null);
  const currentRequest = useRef<AbortController | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const effectiveDetails = quote.show_unit_prices ? details : 'totals';
  const previewKey = `${quote.id}:${quote.revision}:${quote.show_unit_prices}:${effectiveDetails}`;
  const currentKey = useRef(previewKey);
  currentKey.current = previewKey;
  useEffect(() => {
    setPreview(null); setError(''); setBusy(false);
    return () => { currentRequest.current?.abort(); };
  }, [previewKey]);
  useEffect(() => () => { if (preview) URL.revokeObjectURL(preview.url); }, [preview]);

  async function openPdf(download: boolean) {
    currentRequest.current?.abort();
    const controller = new AbortController();
    currentRequest.current = controller;
    const requestKey = previewKey;
    setBusy(true);
    setError('');
    try {
      const { data } = await supabase.auth.getSession();
      if (!data.session?.access_token) throw new Error('Sessão expirada. Entre novamente para gerar o PDF.');
      const response = await fetch(`/api/quotes/${quote.id}/pdf?details=${effectiveDetails}`, {
        headers: { Authorization: `Bearer ${data.session.access_token}` },
        cache: 'no-store',
        signal: controller.signal,
      });
      if (!response.ok) throw new Error(response.status === 422 ? 'O orçamento contém caracteres sem suporte no PDF. Revise o texto antes de exportar.' : response.status === 400 ? 'Este orçamento não permite mostrar valores unitários.' : 'Não foi possível gerar o orçamento agora.');
      const blob = await response.blob();
      if (controller.signal.aborted || currentKey.current !== requestKey) return;
      const objectUrl = URL.createObjectURL(blob);
      setPreview({ key: requestKey, url: objectUrl });
      if (download) {
        const link = document.createElement('a');
        link.href = objectUrl;
        link.download = `orcamento-eventcore-${quote.id}.pdf`;
        link.click();
      }
    } catch (caught) {
      if (!controller.signal.aborted && currentKey.current === requestKey) setError(caught instanceof Error ? caught.message : 'Não foi possível gerar o orçamento agora.');
    } finally {
      if (currentRequest.current === controller && currentKey.current === requestKey) setBusy(false);
    }
  }

  return <div className="quotePdfTools">
    <div className="quotePdfOptions">
      <span className="subtle">PDF para o cliente</span>
      {quote.show_unit_prices && <label className="check"><input type="radio" name={`pdf-details-${quote.id}`} checked={effectiveDetails === 'units'} onChange={() => setDetails('units')} /> Totais e unitários</label>}
      <label className="check"><input type="radio" name={`pdf-details-${quote.id}`} checked={effectiveDetails === 'totals'} onChange={() => setDetails('totals')} /> Somente totais</label>
    </div>
    <div className="actions">
      <button className="btn secondary" type="button" disabled={busy} onClick={() => void openPdf(false)}>{busy ? 'Gerando…' : 'Visualizar PDF'}</button>
      <button className="btn ghost" type="button" disabled={busy} onClick={() => void openPdf(true)}>Baixar PDF</button>
    </div>
    {error && <p className="error" role="alert">{error}</p>}
    {preview?.key === previewKey && <iframe className="quotePdfPreview" title={`Prévia do orçamento ${quote.title}`} src={preview.url} />}
  </div>;
}
