"use client";

import { useCallback, useEffect, useState } from "react";
import { CounterPanel } from "./admin-portal";
import { LoginCard } from "./login-card";
import { AccessDenied, Loading, Notice, StaffLogin, StaffShell, StaffTitle } from "./ui";
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
    </StaffShell>
  );
}
