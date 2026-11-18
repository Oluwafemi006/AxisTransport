"use client";

import { useEffect, useRef, useState } from "react";
import { apiFetch } from "@/lib/api";
import {
  RETURN_MESSAGES, RETURN_POLL_LIMIT_MS, RETURN_POLL_MS, announceSaleResult, clearPendingSale, isFinalState,
  loadPendingSale, staffReturnState, staffSpaceHomePath, type ReturnState, type StaffSpace,
} from "@/lib/staff-sale";
import type { Booking } from "@/lib/types";

const SPACE_LABELS: Record<StaffSpace, string> = { guichet: "Guichet", controleur: "Contrôle", admin: "Administration" };

type View = ReturnState | "verification" | "inconnu" | "connexion";

// Retour de FedaPay après une vente faite par le personnel (/paiement/retour/<espace>).
// La page n'émet rien : elle demande au serveur de vérifier le paiement (même chemin que « Vérifier le paiement »),
// réessaie pendant 2 minutes, puis prévient la fenêtre d'origine par le stockage du navigateur.
export function StaffPaymentReturn({ space }: { space: StaffSpace }) {
  const [view, setView] = useState<View>("verification");
  const [reference, setReference] = useState<string | null>(null);
  const [exhausted, setExhausted] = useState(false);
  const [attempt, setAttempt] = useState(0);
  const timer = useRef<number | null>(null);

  useEffect(() => {
    const sale = loadPendingSale();
    if (!sale) { setView("inconnu"); return; }
    const providerStatus = new URLSearchParams(window.location.search).get("status");
    const started = Date.now();
    let cancelled = false;
    setExhausted(false);

    const tick = async () => {
      let bookingStatus: string | null = null;
      let ticketReference: string | null = null;
      let unauthorized = false;
      const read = (booking: Booking) => { bookingStatus = booking.status; ticketReference = booking.tickets?.[0]?.reference ?? null; };
      try {
        const payload = await apiFetch<{ booking: Booking }>(`/staff/sales/${sale.bookingId}/verify/`, {
          method: "POST",
          body: JSON.stringify({ payment_method: sale.paymentMethod, external_reference: sale.transactionId }),
        });
        read(payload.booking);
      } catch (reason) {
        // Paiement pas encore reçu (refus du serveur) : on relit seulement l'état de la vente.
        if ((reason as { status?: number }).status === 401) unauthorized = true;
        try { read((await apiFetch<{ booking: Booking }>(`/staff/sales/${sale.bookingId}/`)).booking); }
        catch (again) { if ((again as { status?: number }).status === 401) unauthorized = true; }
      }
      if (cancelled) return;
      if (unauthorized && bookingStatus === null) { setView("connexion"); return; }
      const state = staffReturnState(bookingStatus, providerStatus);
      setView(state);
      if (ticketReference) setReference(ticketReference);
      announceSaleResult(sale.bookingId, state);
      if (isFinalState(state)) { clearPendingSale(sale.bookingId); return; }
      if (state === "echoue") return;
      if (Date.now() - started >= RETURN_POLL_LIMIT_MS) { setExhausted(true); return; }
      timer.current = window.setTimeout(() => void tick(), RETURN_POLL_MS);
    };
    void tick();
    return () => { cancelled = true; if (timer.current) window.clearTimeout(timer.current); };
  }, [attempt]);

  const home = staffSpaceHomePath(space);
  const label = SPACE_LABELS[space];
  const message = view === "verification"
    ? { title: "Vérification du paiement…", text: "Le serveur interroge le service Mobile Money." }
    : view === "inconnu"
      ? { title: "Vente introuvable dans ce navigateur", text: "Retrouvez la vente dans l’écran des ventes : les ventes en attente y sont listées avec un bouton « Vérifier »." }
      : view === "connexion"
        ? { title: "Session expirée", text: `Reconnectez-vous dans l’espace ${label}, puis vérifiez la vente dans l’écran des ventes.` }
        : RETURN_MESSAGES[view];
  const tone = view === "paye" ? "ok" : view === "echoue" || view === "expire" || view === "connexion" ? "error" : "info";

  return (
    <div className="min-h-screen bg-slate-100 px-4 py-10 text-slate-900">
      <div className="mx-auto max-w-md rounded-3xl border border-slate-200 bg-white p-7 text-center shadow-xl">
        <img src="/images/axis-logo.png" alt="AXIS Transport" width={570} height={176} className="mx-auto h-14 w-auto" />
        <p className="eyebrow mt-4">Espace {label}</p>
        <h1 className="mt-2 text-2xl font-black" data-state={view}>{message.title}</h1>
        <p role="status" className={`notice notice-${tone === "ok" ? "ok" : tone === "error" ? "error" : "info"} mt-4 text-left`}>{message.text}</p>
        {view === "paye" && reference && <p className="mt-3 text-sm font-bold">Billet {reference}</p>}
        {view === "attente" && !exhausted && <p className="mt-3 text-xs text-slate-500">Nouvelle vérification automatique toutes les 5 secondes.</p>}

        <a href={home} className="primary-button mt-6 w-full">Retour à l’accueil · {label}</a>
        {view === "paye" && reference && (
          <a href={`/t/${encodeURIComponent(reference)}`} className="secondary-button mt-3 w-full">Afficher / imprimer le billet</a>
        )}
        {(exhausted || view === "echoue") && (
          <button type="button" className="secondary-button mt-3 w-full" onClick={() => { setView("verification"); setAttempt((n) => n + 1); }}>Vérifier à nouveau</button>
        )}
      </div>
    </div>
  );
}
