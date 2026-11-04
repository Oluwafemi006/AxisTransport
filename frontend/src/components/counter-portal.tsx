"use client";

import { useCallback, useEffect, useState } from "react";
import { CounterPanel } from "./admin-portal";
import { LoginCard } from "./login-card";
import { AccessDenied, Loading, Notice, SectionHeading, StaffLogin, StaffShell, StaffTitle } from "./ui";
import type { NoticeState } from "./ui";
import { apiFetch, apiList, clearTokens, getAccessToken, money } from "@/lib/api";
import { actionErrorText } from "@/lib/portal-rules";
import type { Parcel, PaymentMethod, Trip, User } from "@/lib/types";

export function CounterPortal() {
  const [user, setUser] = useState<User | null>(null);
  const [trips, setTrips] = useState<Trip[]>([]);
  const [payments, setPayments] = useState<PaymentMethod[]>([]);
  const [message, setMessage] = useState("");
  const [loading, setLoading] = useState(true);
  const [accessDenied, setAccessDenied] = useState(false);

  const load = useCallback(async () => {
    if (!getAccessToken()) { setLoading(false); return; }
    setLoading(true); setMessage(""); setAccessDenied(false);
    try {
      const me = await apiFetch<User>("/auth/me/");
      if (!["COUNTER", "ADMIN"].includes(me.role)) { setUser(me); setAccessDenied(true); return; }
      const [allTrips, methods] = await Promise.all([
        apiList<Trip>("/trips/?all=true"),
        apiList<PaymentMethod>("/payment-methods/"),
      ]);
      setUser(me);
      setTrips(allTrips);
      setPayments(methods);
    } catch (reason) {
      setMessage(reason instanceof Error ? reason.message : "Chargement impossible.");
      if ((reason as { status?: number }).status === 401) { clearTokens(); setUser(null); }
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  if (accessDenied) return <AccessDenied area="l’équipe du guichet" />;
  if (!getAccessToken() || (!loading && !user)) {
    return (
      <StaffLogin error={message}>
        <LoginCard title="Interface guichet" onSuccess={() => void load()} />
      </StaffLogin>
    );
  }

  // Le panneau reste affiché pendant une actualisation : le démonter ferait perdre la vente en cours.
  return (
    <StaffShell user={user}>
      <StaffTitle eyebrow="Guichet" title="Vente de billets" />
      {message && <Notice notice={{ text: message, tone: "error" }} className="mb-5" />}
      {user ? <CounterPanel trips={trips} payments={payments} onChanged={load} /> : <Loading />}
      {user && <ParcelPrices />}
    </StaffShell>
  );
}

// Colis enregistrés : le prix de base vient du serveur, l'agence le change pour un gros colis.
function ParcelPrices() {
  const [parcels, setParcels] = useState<Parcel[]>([]);
  const [drafts, setDrafts] = useState<Record<number, string>>({});
  const [notice, setNotice] = useState<NoticeState>(null);

  const read = useCallback(async () => {
    try { setParcels((await apiList<Parcel>("/parcels/")).slice(0, 30)); }
    catch (reason) { setNotice({ text: actionErrorText(reason, "Les colis n’ont pas pu être chargés."), tone: "error" }); }
  }, []);
  useEffect(() => { void read(); }, [read]);

  const [methods, setMethods] = useState<PaymentMethod[]>([]);
  const [busyId, setBusyId] = useState<number | null>(null);
  const [checkouts, setCheckouts] = useState<Record<number, string>>({});
  useEffect(() => { apiList<PaymentMethod>("/payment-methods/").then((rows) => setMethods(rows.filter((row) => row.active))).catch(() => undefined); }, []);

  // Encaissement : espèces (confirmation), ou Mobile Money (page de paiement ouverte, puis vérification).
  async function collect(parcel: Parcel, method: PaymentMethod) {
    if (busyId) return;
    const online = method.online === true;
    if (!online && !window.confirm(`Espèces reçues ? Confirmez avoir reçu ${money(parcel.amount, "XOF")} de l’expéditeur.`)) return;
    setBusyId(parcel.id);
    try {
      const result = await apiFetch<{ checkout: { payment_url: string } | null }>(`/parcels/${parcel.id}/pay/`, { method: "POST", body: JSON.stringify({ payment_method: method.id }) });
      if (result.checkout?.payment_url) {
        setCheckouts({ ...checkouts, [parcel.id]: result.checkout.payment_url });
        window.open(result.checkout.payment_url, "_blank", "noopener");
        setNotice({ text: `Page de paiement ouverte pour le colis ${parcel.tracking_number}. Cliquez sur « Vérifier le paiement » une fois payé.`, tone: "info" });
      } else {
        setNotice({ text: `Colis ${parcel.tracking_number} payé.`, tone: "ok" });
        window.open(`/guichet/colis/${parcel.id}`, "_blank", "noopener");
      }
      await read();
    } catch (reason) { setNotice({ text: actionErrorText(reason, "L’encaissement n’a pas été enregistré."), tone: "error" }); }
    finally { setBusyId(null); }
  }

  async function verify(parcel: Parcel) {
    setBusyId(parcel.id);
    try {
      await apiFetch(`/parcels/${parcel.id}/verify/`, { method: "POST", body: "{}" });
      setNotice({ text: `Paiement reçu : colis ${parcel.tracking_number} payé.`, tone: "ok" });
      window.open(`/guichet/colis/${parcel.id}`, "_blank", "noopener");
      await read();
    } catch (reason) { setNotice({ text: actionErrorText(reason, "Paiement pas encore reçu."), tone: "error" }); }
    finally { setBusyId(null); }
  }

  async function save(parcel: Parcel) {
    try {
      await apiFetch(`/parcels/${parcel.id}/price/`, { method: "POST", body: JSON.stringify({ amount: (drafts[parcel.id] ?? "").trim() }) });
      setNotice({ text: `Prix du colis ${parcel.tracking_number} enregistré.`, tone: "ok" });
      await read();
    } catch (reason) { setNotice({ text: actionErrorText(reason, "Le prix n’a pas été enregistré."), tone: "error" }); }
  }

  return (
    <section className="card mt-5">
      <SectionHeading eyebrow="Gros colis : prix fixé par l’agence" title="Colis" />
      <Notice notice={notice} className="mb-3" />
      {parcels.length === 0 ? <p className="text-sm text-slate-500">Aucun colis enregistré.</p> : (
        <ul className="space-y-4">
          {parcels.map((parcel) => (
            <li key={parcel.id} className="border-b pb-4">
              <p className="font-semibold">{parcel.tracking_number} : {parcel.origin_detail.name} → {parcel.destination_detail.name}</p>
              <p className="text-sm text-slate-500">{parcel.description} · De {parcel.sender_name} à {parcel.recipient_name}</p>
              {parcel.photo_urls.length > 0 && (
                <div className="mt-2 flex gap-2">
                  {parcel.photo_urls.map((url) => <a key={url} href={url} target="_blank" rel="noreferrer"><img src={url} alt={`Colis ${parcel.tracking_number}`} className="h-20 w-20 rounded object-cover" /></a>)}
                </div>
              )}
              <div className="mt-2 flex items-center gap-2">
                <span className="text-sm">{parcel.amount ? money(parcel.amount, "XOF") : "Prix à fixer"}</span>
                <input className="field max-w-32" inputMode="numeric" aria-label={`Nouveau prix ${parcel.tracking_number}`} value={drafts[parcel.id] ?? ""} onChange={(event) => setDrafts({ ...drafts, [parcel.id]: event.target.value })} />
                <button className="secondary-button" onClick={() => void save(parcel)}>Enregistrer</button>
              </div>
              <div className="mt-2 flex flex-wrap items-center gap-2">
                {parcel.paid ? <span className="badge badge-green">Payé</span> : parcel.amount ? methods.map((method) => (
                  <button key={method.id} type="button" className="secondary-button" disabled={busyId === parcel.id} onClick={() => void collect(parcel, method)}>Encaisser · {method.label}</button>
                )) : <span className="text-sm text-slate-500">Fixez le prix avant d’encaisser.</span>}
                {!parcel.paid && checkouts[parcel.id] && <button type="button" className="primary-button" disabled={busyId === parcel.id} onClick={() => void verify(parcel)}>Vérifier le paiement</button>}
                <a className="text-button" href={`/guichet/colis/${parcel.id}`} target="_blank" rel="noreferrer">Ticket colis</a>
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
