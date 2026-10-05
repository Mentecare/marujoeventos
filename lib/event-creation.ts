export type EventCreationInput = {
  event: {
    client_id: string; name: string; venue: string; start_at: string; end_at: string;
    status: string; arrival_tolerance_minutes: number; notes: string | null;
  };
  services: {
    specialty_id: string; quantity_needed: number; reserve_target: number;
    freelancer_unit_cost: number | null; briefing: string | null;
    requirements: string | null; open_marketplace: boolean;
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
  const services = functionKeys.map((key, index) => {
    const field = (name: string) => text(`function.${key}.${name}`);
    const specialty = field("specialty_id"), quantity = Number(field("quantity_needed"));
    const reserve = Number(field("reserve_target") || 0), rawCost = field("cost");
    const cost = rawCost === "" ? null : Number(rawCost);
    if (!specialty || !Number.isInteger(quantity) || quantity < 1 || quantity > 2147483647 ||
      !Number.isInteger(reserve) || reserve < 0 || reserve > 2147483647 ||
      (cost !== null && (!Number.isFinite(cost) || cost < 0 || cost > 9999999999.99 || Math.round(cost * 100) / 100 !== cost))) {
      throw new Error(`Confira a especialidade, as vagas, as reservas e o valor da função ${index + 1}.`);
    }
    return { specialty_id: specialty, quantity_needed: quantity, reserve_target: reserve,
      freelancer_unit_cost: cost, briefing: field("briefing") || null,
      requirements: field("requirements") || null, open_marketplace: field("open_marketplace") === "on" };
  });
  return { event: { name, client_id: client, venue, start_at: start.toISOString(), end_at: end.toISOString(),
    status, arrival_tolerance_minutes: tolerance, notes: text("notes") || null }, services };
}
