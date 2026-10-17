import { money } from "./api";
import type { TicketPrintInfo } from "./types";

// Mise en page du billet (page web et image) : uniquement des données du serveur, rien n'est inventé.
// Une information facultative absente est masquée ; une information de l'agence absente s'écrit « À renseigner ».

export const TO_FILL = "À renseigner";

export interface PrintableTicket {
  reference: string;
  origin: string;
  destination: string;
  boarding_at: string | null;
  departure_at: string | null;
  arrival_at: string | null;
  seat_label: string;
  passenger_name: string;
  amount: number | string;
  currency: string;
  print_info?: TicketPrintInfo;
}

export function ticketRows(ticket: PrintableTicket, formatDate: (iso: string) => string): Array<[string, string]> {
  const info = ticket.print_info;
  const rows: Array<[string, string]> = [
    ["Référence", ticket.reference],
    ["Trajet", ticket.origin && ticket.destination ? `${ticket.origin} → ${ticket.destination}` : TO_FILL],
  ];
  if (info?.boarding_place) rows.push(["Lieu d'embarquement", info.boarding_place]);
  if (ticket.boarding_at) rows.push(["Embarquement", formatDate(ticket.boarding_at)]);
  if (ticket.departure_at) rows.push(["Départ", formatDate(ticket.departure_at)]);
  if (ticket.arrival_at) rows.push(["Arrivée prévue", formatDate(ticket.arrival_at)]);
  rows.push(["Siège", ticket.seat_label && ticket.seat_label !== "N/A" ? ticket.seat_label : TO_FILL]);
  rows.push(["Passager", ticket.passenger_name || TO_FILL]);
  rows.push(["Prix du billet", money(ticket.amount, ticket.currency)]);
  if (info) {
    if (info.paid) rows.push(["Statut", "Payé"]);
    rows.push(["Vente", info.sale]);
    if (info.payment_mode) rows.push(["Mode de paiement", info.payment_mode]);
    if (info.buyer_ifu) rows.push(["IFU de l'acheteur", info.buyer_ifu]);
    // HT / taxes / TTC : seulement si l'IFU de l'agence est renseigné (le serveur n'envoie le détail que dans ce cas).
    if (info.price_excl_tax !== null) {
      rows.push(["Prix HT", money(info.price_excl_tax, ticket.currency)]);
      for (const line of info.tax_lines) rows.push([`${line.name} ${line.rate} % (incluse)`, money(line.amount, ticket.currency)]);
      rows.push(["Prix TTC", money(info.price_incl_tax, ticket.currency)]);
    }
  }
  return rows;
}

// Bas du billet : agence (jamais les comptes bancaires) et conditions.
export function ticketFooter(info: TicketPrintInfo | undefined): string[] {
  const agency = info?.agency;
  const value = (text: string | undefined) => (text && text.trim() ? text.trim() : TO_FILL);
  return [
    `Raison sociale : ${value(agency?.legal_name)}`,
    `IFU : ${value(agency?.ifu)} · RCCM : ${value(agency?.rccm)}`,
    `Adresse : ${value(agency?.address)}`,
    `Contacts : ${value([agency?.phones, agency?.email].filter((item) => item && item.trim()).join(" · "))}`,
    `Conditions : ${value(info?.conditions)}`,
  ];
}
