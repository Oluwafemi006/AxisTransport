"use client";

import { FormEvent, useEffect, useState } from "react";
import { checkPasswordResetLink, submitPasswordResetLink } from "@/lib/api";

// Page ouverte depuis le lien « choisir un nouveau mot de passe » (e-mail, ou lien transmis par l'agence).
export default function NewPasswordPage() {
  const [token, setToken] = useState("");
  const [state, setState] = useState<"checking" | "ready" | "invalid" | "done">("checking");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const value = new URLSearchParams(window.location.search).get("token") || "";
    setToken(value);
    if (!value) { setState("invalid"); setMessage("Lien incomplet : ouvrez le lien reçu en entier."); return; }
    checkPasswordResetLink(value)
      .then(() => setState("ready"))
      .catch((reason) => { setState("invalid"); setMessage(reason instanceof Error ? reason.message : "Ce lien n’est plus valable."); });
  }, []);

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (busy) return;
    if (password !== confirmation) { setMessage("Les deux mots de passe ne correspondent pas."); return; }
    setBusy(true); setMessage("");
    try {
      setMessage((await submitPasswordResetLink(token, password)).detail);
      setState("done");
    } catch (reason) { setMessage(reason instanceof Error ? reason.message : "Le mot de passe n’a pas été changé."); }
    finally { setBusy(false); }
  }

  return (
    <main className="wrap" style={{ maxWidth: 440, padding: "32px 16px" }}>
      <form onSubmit={submit} className="login-card">
        <p className="eyebrow">Axis Transport</p>
        <h1 className="mt-2 text-2xl font-extrabold text-axis-900">Nouveau mot de passe</h1>
        {state === "checking" && <p className="mt-4 text-sm text-slate-500">Vérification du lien…</p>}
        {state === "invalid" && <p className="notice notice-error mt-4" role="alert">{message}</p>}
        {state === "done" && (
          <>
            <p className="notice notice-ok mt-4" role="status">{message}</p>
            <a className="primary-button mt-6 block w-full text-center" href="/">Aller à la connexion</a>
          </>
        )}
        {state === "ready" && (
          <>
            <label className="field-label mt-6" htmlFor="newPassword">Nouveau mot de passe</label>
            <input id="newPassword" type="password" className="field" autoComplete="new-password" value={password} onChange={(e) => setPassword(e.target.value)} required />
            <label className="field-label mt-4" htmlFor="newPasswordConfirmation">Confirmer le mot de passe</label>
            <input id="newPasswordConfirmation" type="password" className="field" autoComplete="new-password" value={confirmation} onChange={(e) => setConfirmation(e.target.value)} required />
            {message && <p className="notice notice-error mt-4" role="alert">{message}</p>}
            <button className="primary-button mt-6 w-full" disabled={busy}>{busy ? "Patientez…" : "Enregistrer"}</button>
          </>
        )}
      </form>
    </main>
  );
}
