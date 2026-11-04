"use client";

import { useCallback, useEffect, useState } from "react";
import { EmptyState, Loading, Notice, type NoticeState, SectionHeading, StatusBadge, ticketTone } from "./ui";
import { apiFetch, money } from "@/lib/api";
import { soldTicketWhatsappHref } from "@/lib/portal-rules";
import type { SoldTicket } from "@/lib/types";

// Billets vendus aujourd'hui (lecture seule) : l'agent voit ses ventes, l'administrateur toutes (décidé par le serveur).
export function SoldToday({ refreshKey = 0 }: { refreshKey?: number }) {
  const [rows, setRows] = useState<SoldTicket[] | null>(null);
  const [notice, setNotice] = useState<NoticeState>(null);

  const load = useCallback(async () => {
    try {
      setRows(await apiFetch<SoldTicket[]>("/staff/sales/today/"));
      setNotice(null);
    } catch {
      setRows([]);
      setNotice({ text: "La liste des billets vendus n’a pas pu être chargée. Réessayez.", tone: "error" });
    }
  }, []);

  useEffect(() => { void load(); }, [load, refreshKey]);

  const origin = typeof window === "undefined" ? "" : window.location.origin;
  return (
    <section className="card mt-5">
      <SectionHeading eyebrow="Lecture seule" title="Billets vendus aujourd’hui" />
      <button className="secondary-button mb-3" onClick={() => void load()}>Actualiser</button>
      {rows === null ? <Loading /> : rows.length === 0 ? <EmptyState title="Aucun billet vendu" text="Les billets vendus aujourd’hui apparaîtront ici." /> : (
        <ul className="space-y-2">
          {rows.map((row) => {
            const link = row.public_url || `${origin}/t/${encodeURIComponent(row.reference)}`;
            return (
              <li key={row.id} className="rounded-lg border border-slate-200 p-3 text-sm">
                <div className="flex flex-wrap items-center gap-2">
                  <p className="min-w-0 flex-1 font-semibold break-all">{row.reference}</p>
                  <StatusBadge tone={ticketTone(row.status)}>{row.status_display}</StatusBadge>
                </div>
                <p className="mt-1">{row.route} · Siège {row.seat} · {row.passenger_name}</p>
                <p className="text-slate-500">
                  {money(row.amount_fcfa)} · vendu à {new Date(row.sold_at).toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit", timeZone: "Africa/Porto-Novo" })}
                  {row.sold_by_name ? ` · ${row.sold_by_name}` : ""}
                </p>
                <div className="mt-2 flex flex-wrap gap-2">
                  <a className="secondary-button" href={link} target="_blank" rel="noreferrer">Ouvrir le billet</a>
                  <a className="primary-button" href={soldTicketWhatsappHref(row, link)} target="_blank" rel="noopener noreferrer">Envoyer par WhatsApp</a>
                </div>
              </li>
            );
          })}
        </ul>
      )}
      <Notice notice={notice} />
    </section>
  );
}
