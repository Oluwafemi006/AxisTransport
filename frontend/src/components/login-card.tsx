"use client";

import { FormEvent, useState } from "react";
import { login } from "@/lib/api";

export function LoginCard({ title, onSuccess, allowRegistration = false }: { title: string; onSuccess: () => void; allowRegistration?: boolean }) {
  const [registering, setRegistering] = useState(false);
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [phone, setPhone] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      if (registering) {
        const response = await fetch(`${process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000/api"}/auth/register/`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ username, password, first_name: firstName, last_name: lastName, phone }),
        });
        if (!response.ok) {
          const payload = await response.json().catch(() => ({}));
          throw new Error(payload.username?.[0] || payload.password?.[0] || payload.detail || "Création du compte impossible.");
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

  return (
    <form onSubmit={submit} className="mx-auto w-full max-w-md rounded-3xl border border-axis-100 bg-white p-7 shadow-card">
      <p className="eyebrow">{registering ? "Nouveau client" : "Accès sécurisé"}</p>
      <h1 className="mt-2 text-2xl font-bold text-axis-950">{registering ? "Créer mon compte" : title}</h1>
      <p className="mt-2 text-sm text-slate-500">{registering ? "Ce compte permet de retrouver billets, colis et locations." : "Saisissez vos identifiants Axis."}</p>
      {registering && <div className="mt-6 grid grid-cols-2 gap-3"><div><label className="field-label" htmlFor="firstName">Prénom</label><input id="firstName" className="field" value={firstName} onChange={(e) => setFirstName(e.target.value)} /></div><div><label className="field-label" htmlFor="lastName">Nom</label><input id="lastName" className="field" value={lastName} onChange={(e) => setLastName(e.target.value)} /></div></div>}
      <label className={`field-label ${registering ? "mt-4" : "mt-6"}`} htmlFor="username">Identifiant</label>
      <input id="username" className="field" value={username} onChange={(e) => setUsername(e.target.value)} required />
      <label className="field-label mt-4" htmlFor="password">Mot de passe</label>
      <input id="password" type="password" className="field" value={password} onChange={(e) => setPassword(e.target.value)} required />
      {registering && <><label className="field-label mt-4" htmlFor="registerPhone">Téléphone</label><input id="registerPhone" className="field" value={phone} onChange={(e) => setPhone(e.target.value)} /></>}
      {error && <p className="mt-4 rounded-xl bg-red-50 p-3 text-sm text-red-700">{error}</p>}
      <button className="primary-button mt-6 w-full" disabled={busy}>{busy ? "Patientez…" : registering ? "Créer et se connecter" : "Se connecter"}</button>
      {allowRegistration && <button type="button" onClick={() => { setRegistering(!registering); setError(""); }} className="mt-4 w-full text-sm font-bold text-axis-700">{registering ? "J’ai déjà un compte" : "Créer un compte client"}</button>}
    </form>
  );
}
