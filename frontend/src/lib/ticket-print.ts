import { money } from "./api";
import type { TicketPrintInfo } from "./types";

// Mise en page du billet (page web et image) : uniquement des données du serveur, rien n'est inventé.
// Une information facultative absente, dont toutes les mentions de l'agence, est masquée.

export const TO_FILL = "À renseigner";

export interface PrintableTicket {
  reference: string;
  origin: string;
  destination: string;
  boarding_display?: string;
  alighting_display?: string;
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
  const origin = info?.origin || ticket.origin;
  const destination = info?.destination || ticket.destination;
  const boardingDisplay =
    info?.boarding_display ||
    ticket.boarding_display ||
    (origin && info?.boarding_point_name ? `${origin} – ${info.boarding_point_name}` : origin);
  const alightingDisplay =
    info?.alighting_display ||
    ticket.alighting_display ||
    (destination && info?.alighting_point_name ? `${destination} – ${info.alighting_point_name}` : destination);
  const rows: Array<[string, string]> = [
    ["Référence", ticket.reference],
    ["Trajet", origin && destination ? `${origin} → ${destination}` : TO_FILL],
  ];
  if (boardingDisplay) rows.push(["Embarquement", boardingDisplay]);
  if (alightingDisplay) rows.push(["Débarquement", alightingDisplay]);
  if (info?.boarding_place && !info?.boarding_point_name) rows.push(["Lieu d'embarquement", info.boarding_place]);
  if (ticket.boarding_at) {
    rows.push([boardingDisplay ? "Heure d'embarquement" : "Embarquement", formatDate(ticket.boarding_at)]);
  }
  const depLabel = info?.departure_label || "Départ";
  const depTime = info?.departure_at || ticket.departure_at;
  if (depTime) rows.push([depLabel, formatDate(depTime)]);
  if (ticket.arrival_at) rows.push(["Arrivée prévue", formatDate(ticket.arrival_at)]);
  rows.push(["Siège", ticket.seat_label && ticket.seat_label !== "N/A" ? ticket.seat_label : TO_FILL]);
  rows.push(["Passager", ticket.passenger_name || TO_FILL]);
  rows.push(["Prix du billet", money(ticket.amount, ticket.currency)]);
  if (info) {
    if (info.paid) rows.push(["Statut", "Payé"]);
    rows.push(["Vente", info.sale]);
    if (info.payment_mode) rows.push(["Mode de paiement", info.payment_mode]);
    if (info.buyer_ifu) rows.push(["IFU de l'acheteur", info.buyer_ifu]);
  }
  return rows;
}

// Bas du billet : agence (jamais les comptes bancaires) et conditions ; une mention vide n'a pas de ligne.
export function ticketFooter(info: TicketPrintInfo | undefined): string[] {
  const agency = info?.agency;
  const clean = (text: string | undefined) => text?.trim() ?? "";
  const legalIds = [
    clean(agency?.ifu) && `IFU : ${clean(agency?.ifu)}`,
    clean(agency?.rccm) && `RCCM : ${clean(agency?.rccm)}`,
  ].filter(Boolean).join(" · ");
  const contacts = [clean(agency?.phones), clean(agency?.email)].filter(Boolean).join(" · ");
  return [
    clean(agency?.legal_name) && `Raison sociale : ${clean(agency?.legal_name)}`,
    legalIds,
    clean(agency?.address) && `Adresse : ${clean(agency?.address)}`,
    contacts && `Contacts : ${contacts}`,
    clean(info?.conditions) && `Conditions : ${clean(info?.conditions)}`,
  ].filter(Boolean);
}
