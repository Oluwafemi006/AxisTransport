"use client";

import { PasswordInput } from "./password-input";
import { FormEvent, useState } from "react";
import { changeMyPassword } from "@/lib/api";

// Mot de passe provisoire saisi par un administrateur : il doit être remplacé avant d'accéder au reste.
export function ForcedPasswordChange({ onDone }: { onDone: () => void }) {
  const [current, setCurrent] = useState("");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (busy) return;
    if (password !== confirmation) { setError("Les deux mots de passe ne correspondent pas."); return; }
    setBusy(true); setError("");
    try {
      await changeMyPassword(current, password);
      onDone();
    } catch (reason) { setError(reason instanceof Error ? reason.message : "Le mot de passe n’a pas été changé."); }
    finally { setBusy(false); }
  }

  return (
    <form onSubmit={submit} className="login-card" style={{ margin: "32px auto", maxWidth: 440 }}>
      <p className="eyebrow">Première connexion</p>
      <h1 className="mt-2 text-2xl font-extrabold text-axis-900">Choisissez votre mot de passe</h1>
      <p className="mt-2 text-sm text-slate-500">Votre mot de passe actuel est provisoire : remplacez-le pour continuer.</p>
      <label className="field-label mt-6" htmlFor="forcedCurrent">Mot de passe provisoire</label>
      <PasswordInput id="forcedCurrent" className="field" autoComplete="current-password" value={current} onChange={(e) => setCurrent(e.target.value)} required />
      <label className="field-label mt-4" htmlFor="forcedNew">Nouveau mot de passe</label>
      <PasswordInput id="forcedNew" className="field" autoComplete="new-password" value={password} onChange={(e) => setPassword(e.target.value)} required />
      <label className="field-label mt-4" htmlFor="forcedConfirmation">Confirmer le mot de passe</label>
      <PasswordInput id="forcedConfirmation" className="field" autoComplete="new-password" value={confirmation} onChange={(e) => setConfirmation(e.target.value)} required />
      {error && <p className="notice notice-error mt-4" role="alert">{error}</p>}
      <button className="primary-button mt-6 w-full" disabled={busy}>{busy ? "Patientez…" : "Enregistrer et continuer"}</button>
    </form>
  );
}
