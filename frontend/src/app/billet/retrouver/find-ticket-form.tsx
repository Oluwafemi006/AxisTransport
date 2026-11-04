"use client";

import { FormEvent, useState } from "react";
import { apiFetch } from "@/lib/api";

// Référence + téléphone de l'achat : le serveur renvoie seulement la référence, puis la page du billet s'ouvre.
export function FindTicketForm() {
  const [reference, setReference] = useState("");
  const [phone, setPhone] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setError("");
    try {
      const found = await apiFetch<{ reference: string }>(
        "/client/tickets/lookup/",
        { method: "POST", body: JSON.stringify({ reference: reference.trim(), phone: phone.trim() }) },
        false,
      );
      window.location.href = `/t/${encodeURIComponent(found.reference)}`;
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Recherche impossible.");
      setBusy(false);
    }
  }

  return (
    <form onSubmit={submit} className="login-card mx-auto w-full max-w-md">
      <p className="eyebrow">Billet</p>
      <h1 className="mt-2 text-2xl font-extrabold text-axis-900">Retrouver mon billet</h1>
      <p className="mt-2 text-sm text-slate-500">Saisissez la référence du billet (ex. AX-20261105-1A2B3C4D) et le téléphone donné à l’achat.</p>
      <label className="field-label mt-6" htmlFor="findReference">Référence du billet</label>
      <input id="findReference" className="field" autoCapitalize="characters" value={reference} onChange={(e) => setReference(e.target.value)} required />
      <label className="field-label mt-4" htmlFor="findPhone">Téléphone</label>
      <input id="findPhone" className="field" type="tel" autoComplete="tel" value={phone} onChange={(e) => setPhone(e.target.value)} required />
      {error && <p className="notice notice-error mt-4" role="alert">{error}</p>}
      <button className="primary-button mt-6 w-full" disabled={busy}>{busy ? "Recherche…" : "Retrouver mon billet"}</button>
      <a className="text-button mt-4 block w-full text-center" href="/">Retour à l’accueil</a>
    </form>
  );
}
