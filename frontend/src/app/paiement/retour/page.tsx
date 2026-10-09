"use client";

import { useCallback, useEffect, useState } from "react";
import { apiFetch } from "@/lib/api";
import { clearGuestBooking, loadGuestBooking, type GuestBooking } from "@/lib/guest-booking";
import type { Ticket } from "@/lib/types";

type Recovery = "none" | "checking" | "issued" | "waiting" | "failed";

// Page vers laquelle le prestataire de paiement renvoie le voyageur.
// Elle n'émet rien : elle demande au serveur de vérifier le paiement, et seul le serveur émet le billet.
export default function PaymentReturnPage() {
  const [status, setStatus] = useState<string | null>(null);
  const [recovery, setRecovery] = useState<Recovery>("none");
  const [ticket, setTicket] = useState<Ticket | null>(null);
  const [detail, setDetail] = useState("");

  // Réservation faite sans compte dans ce navigateur : le billet se récupère ici, même si l'onglet d'origine est fermé.
  const recover = useCallback(async (stored: GuestBooking, transactionId: string | null) => {
    setRecovery("checking");
    setDetail("");
    const headers = { "X-Booking-Token": stored.token };
    try {
      const current = await apiFetch<{ tickets: Ticket[] }>(`/client/bookings/${stored.id}/`, { headers }, false);
      let found = current.tickets[0];
      const reference = stored.transactionId ?? transactionId;
      if (found?.status === "HELD" && stored.paymentMethod && reference) {
        const paid = await apiFetch<{ booking: { tickets: Ticket[] } }>(`/client/bookings/${stored.id}/pay/`, { method: "POST", headers, body: JSON.stringify({ payment_method: stored.paymentMethod, external_reference: reference }) }, false);
        found = paid.booking.tickets[0];
      }
      if (found?.status === "ISSUED") { setTicket(found); setRecovery("issued"); return; }
      setRecovery("waiting");
    } catch (reason) {
      setDetail(reason instanceof Error ? reason.message : "");
      setRecovery("failed");
    }
  }, []);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    setStatus(params.get("status"));
    const stored = loadGuestBooking();
    if (stored) void recover(stored, params.get("id"));
  }, [recover]);

  const refused = status !== null && status !== "approved" && status !== "pending";
  const retry = () => { const stored = loadGuestBooking(); if (stored) void recover(stored, new URLSearchParams(window.location.search).get("id")); };

  return (
    <div className="min-h-screen bg-slate-100 py-10 px-4 text-slate-900">
      <div className="max-w-md mx-auto bg-white rounded-3xl shadow-xl border border-slate-200 p-7 text-center">
        <img src="/images/axis-logo.png" alt="AXIS Transport" width={570} height={176} className="mx-auto h-14 w-auto" />
        <h1 className="mt-4 text-2xl font-black">
          {recovery === "issued" ? "Votre billet est prêt" : refused ? "Paiement non abouti" : "Retour du paiement"}
        </h1>

        {recovery === "issued" && ticket && (
          <div className="mt-4">
            <p className="text-sm text-slate-600">Le paiement est confirmé. Billet {ticket.reference}.</p>
            <a href={`/t/${ticket.reference}`} onClick={clearGuestBooking} className="primary-button mt-5 w-full">
              Voir et télécharger mon billet
            </a>
            <p className="mt-3 text-xs text-slate-500">Sans compte, ce billet n’est pas conservé sur le site : téléchargez-le maintenant.</p>
          </div>
        )}

        {recovery === "checking" && <p className="mt-4 text-sm text-slate-600" role="status">Vérification du paiement…</p>}

        {(recovery === "waiting" || recovery === "failed") && (
          <div className="mt-4">
            <p className="text-sm text-slate-600">
              {recovery === "waiting" ? "Le paiement n’est pas encore confirmé. Aucun billet n’est émis tant que le paiement n’est pas confirmé." : detail || "La vérification n’a pas abouti."}
            </p>
            <button onClick={retry} className="primary-button mt-5 w-full">Vérifier à nouveau</button>
          </div>
        )}

        {recovery === "none" && (
          <>
            <p className="mt-3 text-sm text-slate-600">
              {refused
                ? "Le prestataire de paiement n’a pas validé cette opération. Aucun billet n’est émis tant que le paiement n’est pas confirmé."
                : "Votre billet est émis dès que le paiement est confirmé. Revenez là où vous avez commencé votre réservation."}
            </p>
            <a href="axistransport://paiement/retour" className="mt-6 block rounded-xl bg-slate-900 px-4 py-3 text-sm font-bold text-white">
              Retourner dans l’application Axis
            </a>
            <p className="mt-2 text-xs text-slate-500">L’application vérifie le paiement automatiquement à votre retour.</p>
            <div className="mt-6 border-t border-slate-200 pt-5 text-sm text-slate-600">
              <p className="font-semibold text-slate-800">Vous avez réservé sur le site ?</p>
              <p className="mt-1">Revenez sur l’onglet Axis Transport resté ouvert et cliquez sur « J’ai payé · vérifier ».</p>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
