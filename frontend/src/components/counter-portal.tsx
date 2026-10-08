"use client";

import { useCallback, useEffect, useState } from "react";
import { CounterPanel } from "./admin-portal";
import { Brand } from "./brand";
import { LoginCard } from "./login-card";
import { AccessDenied } from "./ui";
import { apiFetch, apiList, clearTokens, getAccessToken } from "@/lib/api";
import type { PaymentMethod, Trip, User } from "@/lib/types";

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
  if (!getAccessToken() || (!loading && !user)) return <main className="min-h-screen bg-axis-950 px-4 py-10"><div className="mx-auto max-w-md"><Brand light /><div className="mt-10"><LoginCard title="Interface guichet" onSuccess={() => void load()} /></div>{message && <p className="mt-4 rounded-xl bg-red-50 p-3 text-sm text-red-700">{message}</p>}</div></main>;

  return (
    <main className="min-h-screen bg-axis-50">
      <header className="bg-axis-950 px-4 py-4 text-white">
        <div className="mx-auto flex max-w-6xl items-center justify-between">
          <Brand light />
          <div className="text-right"><p className="text-sm font-bold">{user?.first_name || user?.username}</p><button onClick={() => { clearTokens(); location.reload(); }} className="text-xs text-axis-300">Déconnexion</button></div>
        </div>
      </header>
      <div className="mx-auto max-w-6xl px-4 py-8">
        <p className="eyebrow">Guichet</p>
        <h1 className="mb-6 mt-1 text-3xl font-bold text-axis-950">Vente de billets</h1>
        {message && <p className="mb-5 rounded-xl bg-red-50 p-3 text-sm text-red-700">{message}</p>}
        {loading ? <div className="h-44 animate-pulse rounded-2xl bg-axis-100" /> : <CounterPanel trips={trips} payments={payments} onChanged={load} />}
      </div>
    </main>
  );
}
