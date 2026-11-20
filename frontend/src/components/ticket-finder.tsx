"use client";

import { FormEvent, useState } from "react";
import { EmptyState, Notice, type NoticeState, SectionHeading, StatusBadge, ticketTone } from "./ui";
import { apiFetch } from "@/lib/api";
import { counterSearchError, soldTicketWhatsappHref } from "@/lib/portal-rules";
import type { Ticket } from "@/lib/types";

// Guichet : retrouver le billet d'un client (référence ou téléphone) pour le lui renvoyer. Jamais d'annulation ici.
export function TicketFinder() {
  const [query, setQuery] = useState("");
  const [rows, setRows] = useState<Ticket[] | null>(null);
  const [notice, setNotice] = useState<NoticeState>(null);
  const [copied, setCopied] = useState("");
  const [busy, setBusy] = useState(false);

  async function search(event: FormEvent) {
    event.preventDefault();
    const error = counterSearchError(query);
    if (error) { setNotice({ text: error, tone: "error" }); return; }
    setBusy(true); setNotice(null);
    try {
      setRows(await apiFetch<Ticket[]>(`/tickets/counter-search/?q=${encodeURIComponent(query.trim())}`));
    } catch (reason) {
      setRows(null);
      setNotice({ text: reason instanceof Error ? reason.message : "Recherche impossible.", tone: "error" });
    } finally {
      setBusy(false);
    }
  }

  async function copy(link: string, reference: string) {
    try { await navigator.clipboard.writeText(link); setCopied(reference); } catch { setNotice({ text: "Copie impossible : sélectionnez le lien à la main.", tone: "error" }); }
  }

  const origin = typeof window === "undefined" ? "" : window.location.origin;
  return (
    <section className="card mt-5">
      <SectionHeading eyebrow="Référence ou téléphone" title="Retrouver un billet" />
      <form onSubmit={search} className="flex flex-wrap gap-2">
        <input className="field min-w-0 flex-1" type="search" aria-label="Référence ou téléphone" value={query} onChange={(e) => setQuery(e.target.value)} placeholder="AX-… ou 01 97 00 00 00 (6 chiffres au moins)" />
        <button className="primary-button" disabled={busy || !query.trim()}>{busy ? "Recherche…" : "Rechercher"}</button>
      </form>
      <Notice notice={notice} className="mt-3" />
      {rows !== null && (rows.length === 0 ? <EmptyState title="Aucun billet" text="Vérifiez la référence ou le numéro de téléphone." /> : (
        <ul className="mt-3 space-y-2">
          {rows.map((ticket) => {
            const link = ticket.public_url || `${origin}/t/${encodeURIComponent(ticket.reference)}`;
            return (
              <li key={ticket.id} className="rounded-lg border border-slate-200 p-3 text-sm">
                <div className="flex flex-wrap items-center gap-2">
                  <p className="min-w-0 flex-1 font-semibold break-all">{ticket.reference}</p>
                  <StatusBadge tone={ticketTone(ticket.status)}>{ticket.status_display}</StatusBadge>
                </div>
                <p className="mt-1">{ticket.segment_label || ticket.trip_detail?.route_detail?.label} · {ticket.departure_label} · {ticket.passenger_name}</p>
                <div className="mt-2 flex flex-wrap gap-2">
                  <a className="secondary-button" href={link} target="_blank" rel="noreferrer">Voir le billet</a>
                  <a className="primary-button" href={soldTicketWhatsappHref(ticket, link)} target="_blank" rel="noopener noreferrer">Envoyer par WhatsApp</a>
                  <button type="button" className="secondary-button" onClick={() => void copy(link, ticket.reference)}>{copied === ticket.reference ? "Lien copié" : "Copier le lien"}</button>
                  {typeof navigator !== "undefined" && "share" in navigator && (
                    <button type="button" className="secondary-button" onClick={() => void navigator.share({ title: `Billet AXIS Transport ${ticket.reference}`, url: link }).catch(() => undefined)}>Partager</button>
                  )}
                </div>
              </li>
            );
          })}
        </ul>
      ))}
    </section>
  );
}
