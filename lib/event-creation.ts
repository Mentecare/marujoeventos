import { remunerationTotal, type WorkOrigin } from './commercial.ts';
export type EventCreationInput = {
  event: {
    organization_id?: string; origin?: WorkOrigin; commercial_contract_id?: string; public_region?: string; client_id: string; name: string; venue: string; start_at: string; end_at: string;
    status: string; arrival_tolerance_minutes: number; notes: string | null;
  };
  services: {
    specialty_id: string; quantity_needed: number; reserve_target: number; contract_days: number;
    freelancer_unit_cost: number | null; briefing: string | null;
    requirements: string | null; public_description?: string; open_marketplace: boolean; remuneration_basis?: 'daily' | 'service'; remuneration_rate?: number; benefits?: string | null; additions?: number; deductions?: number; planned_hours?: number | null;
  }[];
};

export function buildEventCreation(fields: FormData, functionKeys: string[]): EventCreationInput {
  const text = (name: string) => String(fields.get(name) ?? "").trim();
  const name = text("name"), client = text("client_id"), venue = text("venue");
  const start = new Date(text("start_at")), end = new Date(text("end_at"));
  const tolerance = Number(text("tolerance") || 0), status = text("status");
  if (!name || !client || !venue) throw new Error("Preencha o nome, o cliente e o local do evento.");
  if (!Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime()) || end <= start) {
    throw new Error("Informe os horários do evento com o término após o início.");
  }
  if (!Number.isInteger(tolerance) || tolerance < 0 || tolerance > 180) throw new Error("Informe uma tolerância entre 0 e 180 minutos.");
  if (!["planning", "staffing", "confirmed"].includes(status)) throw new Error("Selecione um status válido para o novo evento.");
  const origin = text('origin');
  if (origin && !['platform','whatsapp','referral','other'].includes(origin)) throw new Error('Informe uma origem válida.');
  if (text('public_region').length > 150) throw new Error('Informe uma região de até 150 caracteres.');
  const services = functionKeys.map((key, index) => {
    const field = (name: string) => text(`function.${key}.${name}`);
    const specialty = field("specialty_id"), quantity = Number(field("quantity_needed"));
    const reserve = Number(field("reserve_target") || 0), rawCost = field("cost");
    const days = fields.has(`function.${key}.contract_days`) ? Number(field("contract_days")) : 1;
    const cost = rawCost === "" ? null : Number(rawCost);
    if (!Number.isInteger(days) || days < 1 || days > 2147483647) {
      throw new Error(`Informe uma quantidade inteira de dias, maior que zero, para a função ${index + 1}.`);
    }
    if (!specialty || !Number.isInteger(quantity) || quantity < 1 || quantity > 2147483647 ||
      !Number.isInteger(reserve) || reserve < 0 || reserve > 2147483647 ||
      (cost !== null && (!Number.isFinite(cost) || cost < 0 || cost > 9999999999.99 || Math.round(cost * 100) / 100 !== cost))) {
      throw new Error(`Confira a especialidade, as vagas, as reservas e o valor da função ${index + 1}.`);
    }
    if (field('public_description').length > 2000) throw new Error(`Confira a descrição pública da função ${index + 1}.`);
    const basis = field('remuneration_basis');
    const terms = basis ? { remuneration_basis: basis as 'daily' | 'service', remuneration_rate: Number(field('remuneration_rate')), benefits: field('benefits') || null, additions: Number(field('additions') || 0), deductions: Number(field('deductions') || 0), planned_hours: field('planned_hours') ? Number(field('planned_hours')) : null } : null;
    let total = cost;
    if (terms) {
      if (!field('remuneration_rate') || (terms.planned_hours !== null && (!Number.isFinite(terms.planned_hours) || terms.planned_hours < 0 || terms.planned_hours > 9999.99 || Math.abs(Math.round(terms.planned_hours * 100) / 100 - terms.planned_hours) > 1e-9)) || (terms.benefits?.length ?? 0) > 2000) throw new Error(`Confira as condições da função ${index + 1}.`);
      total = remunerationTotal({ basis: terms.remuneration_basis, rate: terms.remuneration_rate, contract_days: days, additions: terms.additions, deductions: terms.deductions });
    }
    return { ...(terms || {}), ...(field('public_description') ? { public_description: field('public_description') } : {}), specialty_id: specialty, quantity_needed: quantity, reserve_target: reserve, contract_days: days,
      freelancer_unit_cost: total, briefing: field("briefing") || null,
      requirements: field("requirements") || null, open_marketplace: field("open_marketplace") === "on" };
  });
  return { event: { ...(text('public_region') ? { public_region: text('public_region') } : {}), ...(text('organization_id') ? { organization_id: text('organization_id') } : {}), ...(origin ? { origin: origin as WorkOrigin } : {}), ...(text('commercial_contract_id') ? { commercial_contract_id: text('commercial_contract_id') } : {}), name, client_id: client, venue, start_at: start.toISOString(), end_at: end.toISOString(),
    status, arrival_tolerance_minutes: tolerance, notes: text("notes") || null }, services };
}
