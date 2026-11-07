"use client";

import { PasswordInput } from "./password-input";
import { FormEvent, useState } from "react";
import { API_URL, login, requestPasswordReset } from "@/lib/api";

function ForgotPassword({ onBack }: { onBack: () => void }) {
  const [email, setEmail] = useState("");
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (busy) return;
    setError("");
    setBusy(true);
    try {
      setNotice((await requestPasswordReset(email)).detail);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Opération impossible.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={submit} className="login-card">
      <p className="eyebrow">Compte client</p>
      <h1 className="mt-2 text-2xl font-extrabold text-axis-900">Mot de passe oublié</h1>
      {notice ? (
        <p className="notice mt-4" role="status">{notice} Ouvrez le lien reçu pour choisir votre nouveau mot de passe.</p>
      ) : (
        <>
          <p className="mt-2 text-sm text-slate-500">Saisissez l’e-mail de votre compte : vous recevrez un lien pour choisir un nouveau mot de passe. Personnel ou compte sans e-mail : contactez un administrateur.</p>
          <label className="field-label mt-6" htmlFor="resetEmail">E-mail</label>
          <input id="resetEmail" type="email" className="field" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
          {error && <p className="notice notice-error mt-4" role="alert">{error}</p>}
          <button className="primary-button mt-6 w-full" disabled={busy}>{busy ? "Patientez…" : "Recevoir un lien"}</button>
        </>
      )}
      <button type="button" onClick={onBack} className="text-button mt-4 w-full">Retour à la connexion</button>
    </form>
  );
}

export function LoginCard({ title, onSuccess, allowRegistration = false }: { title: string; onSuccess: () => void; allowRegistration?: boolean }) {
  const [registering, setRegistering] = useState(false);
  const [forgot, setForgot] = useState(false);
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      if (registering) {
        const response = await fetch(`${API_URL}/auth/register/`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ username, password, first_name: firstName, last_name: lastName, phone, email }),
        });
        if (!response.ok) {
          const payload = await response.json().catch(() => ({}));
          throw new Error(payload.username?.[0] || payload.email?.[0] || payload.password?.[0] || payload.detail || "Création du compte impossible.");
        }
      }
      await login(username, password);
      onSuccess();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Connexion impossible.");
    } finally {
      setBusy(false);
    }
  }

  if (forgot) return <ForgotPassword onBack={() => setForgot(false)} />;

  return (
    <form onSubmit={submit} className="login-card">
      <p className="eyebrow">{registering ? "Nouveau client" : "Accès sécurisé"}</p>
      <h1 className="mt-2 text-2xl font-extrabold text-axis-900">{registering ? "Créer mon compte" : title}</h1>
      <p className="mt-2 text-sm text-slate-500">{registering ? "Ce compte permet de retrouver billets, colis et locations." : "Saisissez vos identifiants Axis."}</p>
      {registering && (
        <div className="mt-6 grid grid-cols-2 gap-3">
          <div>
            <label className="field-label" htmlFor="firstName">Prénom</label>
            <input id="firstName" className="field" value={firstName} onChange={(e) => setFirstName(e.target.value)} />
          </div>
          <div>
            <label className="field-label" htmlFor="lastName">Nom</label>
            <input id="lastName" className="field" value={lastName} onChange={(e) => setLastName(e.target.value)} />
          </div>
        </div>
      )}
      <label className={`field-label ${registering ? "mt-4" : "mt-6"}`} htmlFor="username">Identifiant</label>
      <input id="username" className="field" autoComplete="username" value={username} onChange={(e) => setUsername(e.target.value)} required />
      <label className="field-label mt-4" htmlFor="password">Mot de passe</label>
      <PasswordInput id="password" className="field" autoComplete={registering ? "new-password" : "current-password"} value={password} onChange={(e) => setPassword(e.target.value)} required />
      {registering && (
        <>
          <label className="field-label mt-4" htmlFor="registerPhone">Téléphone</label>
          <input id="registerPhone" className="field" value={phone} onChange={(e) => setPhone(e.target.value)} />
          <label className="field-label mt-4" htmlFor="registerEmail">E-mail (pour retrouver votre mot de passe)</label>
          <input id="registerEmail" type="email" className="field" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} />
        </>
      )}
      {error && <p className="notice notice-error mt-4" role="alert">{error}</p>}
      <button className="primary-button mt-6 w-full" disabled={busy}>{busy ? "Patientez…" : registering ? "Créer et se connecter" : "Se connecter"}</button>
      {allowRegistration && !registering && (
        <button type="button" onClick={() => { setForgot(true); setError(""); }} className="text-button mt-4 w-full">Mot de passe oublié ?</button>
      )}
      {allowRegistration && (
        <button type="button" onClick={() => { setRegistering(!registering); setError(""); }} className="text-button mt-4 w-full">
          {registering ? "J’ai déjà un compte" : "Créer un compte client"}
        </button>
      )}
    </form>
  );
}
