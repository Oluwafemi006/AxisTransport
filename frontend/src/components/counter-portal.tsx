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
  const [shown, setShown] = useState(30);

  const read = useCallback(async () => {
    try { setParcels(await apiList<Parcel>("/parcels/")); }
    catch (reason) { setNotice({ text: actionErrorText(reason, "Les colis n’ont pas pu être chargés."), tone: "error" }); }
  }, []);
  useEffect(() => { void read(); }, [read]);

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
          {parcels.slice(0, shown).map((parcel) => (
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
            </li>
          ))}
        </ul>
      )}
      {parcels.length > shown && (
        <button type="button" className="secondary-button mt-4 w-full" onClick={() => setShown(shown + 30)}>
          Afficher plus ({parcels.length - shown} colis restants)
        </button>
      )}
    </section>
  );
}
