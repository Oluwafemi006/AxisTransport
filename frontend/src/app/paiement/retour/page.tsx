"use client";

import { useEffect, useState } from "react";

// Page vers laquelle le prestataire de paiement renvoie le voyageur.
// Elle n'émet rien : seul le serveur confirme un paiement, depuis l'application ou le site.
export default function PaymentReturnPage() {
  const [status, setStatus] = useState<string | null>(null);

  useEffect(() => {
    setStatus(new URLSearchParams(window.location.search).get("status"));
  }, []);

  const refused = status !== null && status !== "approved" && status !== "pending";

  return (
    <div className="min-h-screen bg-slate-100 py-10 px-4 text-slate-900">
      <div className="max-w-md mx-auto bg-white rounded-3xl shadow-xl border border-slate-200 p-7 text-center">
        <p className="text-xs font-bold uppercase tracking-widest text-slate-400">AXIS Transport</p>
        <h1 className="mt-2 text-2xl font-black">
          {refused ? "Paiement non abouti" : "Retour du paiement"}
        </h1>
        <p className="mt-3 text-sm text-slate-600">
          {refused
            ? "Le prestataire de paiement n’a pas validé cette opération. Aucun billet n’est émis tant que le paiement n’est pas confirmé."
            : "Votre billet est émis dès que le paiement est confirmé. Revenez là où vous avez commencé votre réservation."}
        </p>

        <a
          href="axistransport://paiement/retour"
          className="mt-6 block rounded-xl bg-slate-900 px-4 py-3 text-sm font-bold text-white"
        >
          Retourner dans l’application Axis
        </a>
        <p className="mt-2 text-xs text-slate-500">
          L’application vérifie le paiement automatiquement à votre retour.
        </p>

        <div className="mt-6 border-t border-slate-200 pt-5 text-sm text-slate-600">
          <p className="font-semibold text-slate-800">Vous avez réservé sur le site ?</p>
          <p className="mt-1">
            Revenez sur l’onglet Axis Transport resté ouvert et cliquez sur « J’ai payé · vérifier ».
          </p>
        </div>
      </div>
    </div>
  );
}
