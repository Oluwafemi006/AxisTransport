"use client";

import { useEffect, useState } from "react";
import { QRCodeSVG } from "qrcode.react";
import { Brand } from "@/components/brand";
import { apiFetch, formatDate, money } from "@/lib/api";
import type { ParcelReceipt } from "@/lib/types";

// Ticket colis remis à l'expéditeur : imprimé à l'agence, ou enregistré en PDF depuis la fenêtre d'impression.
export function ParcelTicket({ id }: { id: string }) {
  const [receipt, setReceipt] = useState<ParcelReceipt | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    apiFetch<ParcelReceipt>(`/parcels/${encodeURIComponent(id)}/receipt/`)
      .then(setReceipt)
      .catch((reason) => setError(reason instanceof Error ? reason.message : "Ticket indisponible."));
  }, [id]);

  if (error) return <main className="wrap py-10"><p className="notice notice-error">{error}</p></main>;
  if (!receipt) return <main className="wrap py-10"><p>Chargement du ticket…</p></main>;

  const rows: Array<[string, string]> = [
    ["Numéro de suivi", receipt.tracking_number],
    ["Trajet", `${receipt.origin} → ${receipt.destination}`],
    ["Expéditeur", `${receipt.sender_name} · ${receipt.sender_phone}`],
    ["Destinataire", `${receipt.recipient_name} · ${receipt.recipient_phone}`],
    ["Contenu", receipt.description],
    ["Prix", receipt.amount === null ? "À fixer par l’agence" : money(receipt.amount, receipt.currency)],
    ["Paiement", receipt.paid ? `Payé · ${receipt.payment_mode}${receipt.paid_at ? ` · ${formatDate(receipt.paid_at)}` : ""}` : "Non payé"],
  ];
  if (receipt.departure_at) rows.splice(2, 0, ["Départ du bus", formatDate(receipt.departure_at)]);
  rows.push(["Enregistré le", formatDate(receipt.created_at)]);

  return (
    <main className="mx-auto w-full max-w-md px-4 py-6 print:p-0">
      <div className="mb-4 flex gap-2 print:hidden">
        <button type="button" className="primary-button flex-1" onClick={() => window.print()}>Imprimer ou enregistrer en PDF</button>
        <a className="secondary-button" href="/guichet">Retour</a>
      </div>
      <article className="rounded-[14px] border border-[var(--line)] bg-white p-5">
        <div className="mb-3 flex items-center justify-between gap-3"><Brand /><span className={receipt.paid ? "badge badge-green" : "badge badge-amber"}>{receipt.paid ? "Payé" : "Non payé"}</span></div>
        <h1 className="text-xl font-extrabold text-axis-900">{receipt.title}</h1>
        <div className="my-4 flex justify-center"><QRCodeSVG value={receipt.tracking_number} size={140} level="M" includeMargin /></div>
        <dl className="space-y-2 text-sm">
          {rows.map(([label, value]) => (
            <div key={label} className="flex justify-between gap-3 border-b border-[var(--line)] pb-1">
              <dt className="text-slate-500">{label}</dt>
              <dd className="text-right font-semibold">{value}</dd>
            </div>
          ))}
        </dl>
        <p className="mt-4 text-xs text-slate-500">Présentez ce ticket ou le numéro de suivi pour suivre et retirer le colis.</p>
      </article>
    </main>
  );
}
