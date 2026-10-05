"use client";

import { type FormEvent, useRef, useState } from "react";
import { buildEventCreation, type EventCreationInput } from "@/lib/event-creation";

export function EventCreationForm({ clients, specialties, busy, onCreate }: {
  clients: { id: string; trade_name: string }[];
  specialties: { id: string; name: string; active: boolean }[];
  busy: boolean;
  onCreate: (input: EventCreationInput) => Promise<boolean>;
}) {
  const [functionKeys, setFunctionKeys] = useState<string[]>([]);
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);
  const sequence = useRef(0), submitting = useRef(false);
  const locked = busy || saving;
  const availableSpecialties = specialties.filter(specialty => specialty.active);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (locked || submitting.current) return;
    const form = event.currentTarget;
    setError("");
    try {
      const input = buildEventCreation(new FormData(form), functionKeys);
      submitting.current = true; setSaving(true);
      if (await onCreate(input)) { form.reset(); setFunctionKeys([]); }
    } catch (error) {
      setError(error instanceof Error ? error.message : "Não foi possível criar o evento. Confira os dados e tente novamente.");
    } finally { submitting.current = false; setSaving(false); }
  }

  return <form className="panel form eventCreationForm" onSubmit={submit}>
    <h2>Novo evento</h2>
    <fieldset className="eventCreationFields" disabled={locked}>
      <label>Nome do evento<input className="input" name="name" required/></label>
      <label>Cliente<select className="select" name="client_id" required><option value="">Selecione</option>{clients.map(client => <option key={client.id} value={client.id}>{client.trade_name}</option>)}</select></label>
      <label>Local<input className="input" name="venue" required/></label>
      <div className="formGrid"><label>Início<input className="input" name="start_at" type="datetime-local" required/></label><label>Término<input className="input" name="end_at" type="datetime-local" required/></label></div>
      <div className="formGrid"><label>Status<select className="select" name="status" defaultValue="planning"><option value="planning">Planejamento</option><option value="staffing">Montando equipe</option><option value="confirmed">Confirmado</option></select></label><label>Tolerância de chegada (min)<input className="input" name="tolerance" type="number" min="0" max="180" step="1" defaultValue="15"/></label></div>
      <label>Observações internas<textarea className="textarea" name="notes"/></label>
      <section className="eventCreationFunctions" aria-label="Funções na criação do evento">
        <h3>Funções e vagas</h3>
        <p className="subtle">Inclua as funções antes de criar o evento. Depois de salvar, não será possível adicionar novas funções.</p>
        {functionKeys.map((key, index) => <fieldset className="functionDraft form" key={key}>
          <legend>Função {index + 1}</legend>
          <button className="btn ghost functionRemove" type="button" onClick={() => setFunctionKeys(keys => keys.filter(item => item !== key))} aria-label={`Remover função ${index + 1}`}>Remover função</button>
          <label>Especialidade<select className="select" name={`function.${key}.specialty_id`} required defaultValue=""><option value="">Selecione</option>{availableSpecialties.map(specialty => <option key={specialty.id} value={specialty.id}>{specialty.name}</option>)}</select></label>
          <div className="formGrid"><label>Vagas<input className="input" name={`function.${key}.quantity_needed`} type="number" min="1" max="2147483647" step="1" defaultValue="1" required/></label><label>Reservas<input className="input" name={`function.${key}.reserve_target`} type="number" min="0" max="2147483647" step="1" defaultValue="0"/></label></div>
          <label>Valor por profissional (R$)<input className="input" name={`function.${key}.cost`} type="number" inputMode="decimal" min="0" max="9999999999.99" step="0.01"/></label>
          <label>Briefing<textarea className="textarea" name={`function.${key}.briefing`}/></label>
          <label>Requisitos<textarea className="textarea" name={`function.${key}.requirements`}/></label>
          <label className="check"><input name={`function.${key}.open_marketplace`} type="checkbox"/>Publicar em Oportunidades</label>
        </fieldset>)}
        {!functionKeys.length && <p className="subtle">Nenhuma função incluída. Se precisar de equipe, adicione as funções agora.</p>}
        <button className="btn secondary" type="button" disabled={!availableSpecialties.length} onClick={() => { const key = String(++sequence.current); setFunctionKeys(keys => [...keys, key]); }}>Adicionar função</button>
        {!availableSpecialties.length && <small className="subtle">As especialidades ainda não estão disponíveis. Atualize para carregar as opções.</small>}
      </section>
      {error && <p className="error" role="alert">{error}</p>}
      <button className="btn" disabled={!clients.length}>{saving ? "Criando evento…" : "Criar evento"}</button>
      {!clients.length && <small className="subtle">Cadastre um cliente da sua organização antes de criar um evento.</small>}
    </fieldset>
  </form>;
}
