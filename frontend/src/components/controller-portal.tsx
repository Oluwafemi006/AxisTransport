"use client";

import { FormEvent, useCallback, useEffect, useRef, useState } from "react";
import { Brand } from "./brand";
import { LoginCard } from "./login-card";
import { AccessDenied, EmptyState, StatusBadge } from "./ui";
import { apiFetch, apiList, clearTokens, formatDate, getAccessToken } from "@/lib/api";
import type { Seat, Ticket, Trip, User } from "@/lib/types";

type ScanResult = { ticket: Ticket; control_id: number };

export function ControllerPortal() {
  const [user, setUser] = useState<User | null>(null);
  const [trips, setTrips] = useState<Trip[]>([]);
  const [tripId, setTripId] = useState("");
  const [seats, setSeats] = useState<Seat[]>([]);
  const [tickets, setTickets] = useState<Ticket[]>([]);
  const [result, setResult] = useState<ScanResult | null>(null);
  const [message, setMessage] = useState("");
  const [loading, setLoading] = useState(true);
  const [accessDenied, setAccessDenied] = useState(false);

  const load = useCallback(async () => {
    if (!getAccessToken()) { setLoading(false); return; }
    setLoading(true); setAccessDenied(false);
    try {
      const me = await apiFetch<User>("/auth/me/");
      if (!["CONTROLLER", "ADMIN"].includes(me.role)) { setUser(me); setAccessDenied(true); return; }
      const allTrips = await apiList<Trip>("/trips/?all=true");
      setUser(me); setTrips(allTrips.filter((trip) => !["COMPLETED", "CANCELLED"].includes(trip.status)));
    } catch (reason) { setMessage(reason instanceof Error ? reason.message : "Connexion impossible."); if ((reason as { status?: number }).status === 401) { clearTokens(); setUser(null); } }
    finally { setLoading(false); }
  }, []);

  const loadTrip = useCallback(async (id: string) => {
    if (!id) { setSeats([]); setTickets([]); return; }
    const [seatData, ticketData] = await Promise.all([apiList<Seat>(`/seats/?trip=${id}`), apiList<Ticket>(`/tickets/?trip=${id}`)]);
    setSeats(seatData); setTickets(ticketData);
  }, []);

  useEffect(() => { void load(); if ("serviceWorker" in navigator) void navigator.serviceWorker.register("/sw.js"); }, [load]);
  useEffect(() => { void loadTrip(tripId); }, [tripId, loadTrip]);

  async function validate(value: string, method: "QR" | "MANUAL") {
    setMessage(""); setResult(null);
    try {
      const isReference = value.toUpperCase().startsWith("AX-");
      const response = await apiFetch<ScanResult>("/tickets/validate-qr/", { method: "POST", body: JSON.stringify({ [isReference ? "reference" : "qr_token"]: value.trim(), trip: tripId ? Number(tripId) : null, method }) });
      setResult(response); setMessage("Ticket valide. Contrôle enregistré."); await loadTrip(tripId);
    } catch (reason) { setMessage(reason instanceof Error ? reason.message : "Ticket refusé."); }
  }

  if (accessDenied) return <AccessDenied area="l’équipe de contrôle" />;
  if (!getAccessToken() || (!loading && !user)) return <main className="min-h-screen bg-axis-950 px-4 py-10"><div className="mx-auto max-w-md"><Brand light /><div className="mt-10"><LoginCard title="Interface contrôleur" onSuccess={() => void load()} /></div>{message && <p className="mt-4 rounded-xl bg-red-50 p-3 text-sm text-red-700">{message}</p>}</div></main>;

  return <main className="min-h-screen bg-axis-950 pb-10 text-white"><header className="border-b border-white/10 px-4 py-4"><div className="mx-auto flex max-w-5xl items-center justify-between"><Brand light /><div className="text-right"><p className="text-sm font-bold">{user?.first_name || user?.username}</p><button onClick={() => { clearTokens(); location.reload(); }} className="text-xs text-axis-300">Déconnexion</button></div></div></header><div className="mx-auto max-w-5xl px-4 py-6"><p className="text-xs font-bold uppercase tracking-[.18em] text-axis-300">Contrôle embarquement / à bord</p><h1 className="mt-2 text-3xl font-bold">Vérifier un billet</h1><label className="mt-6 block text-xs font-semibold text-axis-200">Voyage contrôlé</label><select className="mt-2 w-full rounded-2xl border border-white/15 bg-white/10 px-4 py-3 text-white outline-none" value={tripId} onChange={(e) => setTripId(e.target.value)}><option className="text-axis-950" value="">Choisir le voyage</option>{trips.map((trip) => <option className="text-axis-950" key={trip.id} value={trip.id}>{trip.route_detail.label} · {formatDate(trip.departure_at)}</option>)}</select><div className="mt-6 grid gap-5 md:grid-cols-2"><Scanner disabled={!tripId} onValue={(value) => void validate(extractToken(value), "QR")} /><ManualValidation disabled={!tripId} onSubmit={(value) => void validate(value, "MANUAL")} /></div>{message && <div className={`mt-5 rounded-2xl p-4 text-sm font-semibold ${result ? "bg-emerald-500/20 text-emerald-100" : "bg-red-500/20 text-red-100"}`}>{message}</div>}{result && <article className="mt-5 rounded-2xl bg-white p-5 text-axis-950"><div className="flex items-start justify-between gap-4"><div><p className="text-xs font-bold text-axis-600">{result.ticket.reference}</p><h2 className="mt-1 text-xl font-bold">{result.ticket.passenger_name}</h2><p className="mt-1 text-sm text-slate-500">Siège {result.ticket.seat_detail.number} · {result.ticket.trip_detail.route_detail.label}</p></div><StatusBadge tone="green">Contrôlé</StatusBadge></div></article>}<SeatOverview seats={seats} tickets={tickets} enabled={Boolean(tripId)} /></div></main>;
}

function Scanner({ disabled, onValue }: { disabled: boolean; onValue: (value: string) => void }) {
  const video = useRef<HTMLVideoElement>(null); const stream = useRef<MediaStream | null>(null); const frame = useRef<number | null>(null); const [active, setActive] = useState(false); const [error, setError] = useState("");
  async function start() {
    setError("");
    const Detector = (window as unknown as { BarcodeDetector?: new (config: { formats: string[] }) => { detect: (source: HTMLVideoElement) => Promise<Array<{ rawValue: string }>> } }).BarcodeDetector;
    if (!Detector) { setError("Lecture caméra QR indisponible sur ce navigateur. Utilisez la validation manuelle."); return; }
    try {
      stream.current = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" }, audio: false });
      if (!video.current) return;
      video.current.srcObject = stream.current; await video.current.play(); setActive(true);
      const detector = new Detector({ formats: ["qr_code"] });
      const scan = async () => { if (!video.current || !stream.current) return; const codes = await detector.detect(video.current).catch(() => []); if (codes[0]?.rawValue) { stop(); onValue(codes[0].rawValue); return; } frame.current = requestAnimationFrame(scan); };
      frame.current = requestAnimationFrame(scan);
    } catch { setError("Accès caméra refusé ou indisponible."); }
  }
  function stop() { if (frame.current) cancelAnimationFrame(frame.current); stream.current?.getTracks().forEach((track) => track.stop()); stream.current = null; setActive(false); }
  useEffect(() => stop, []);
  return <section className="rounded-3xl border border-white/10 bg-white/5 p-5"><p className="text-xs font-bold uppercase tracking-[.14em] text-axis-300">Scan QR</p><div className="mt-4 aspect-[4/3] overflow-hidden rounded-2xl bg-black/30"><video ref={video} className="h-full w-full object-cover" muted playsInline />{!active && <div className="grid h-full place-items-center px-6 text-center text-sm text-axis-200">Cadrez le QR code du ticket dans la caméra.</div>}</div><button disabled={disabled} onClick={active ? stop : () => void start()} className="mt-4 w-full rounded-xl bg-white px-4 py-3 text-sm font-bold text-axis-950">{active ? "Arrêter la caméra" : "Démarrer le scan"}</button>{error && <p className="mt-3 text-xs text-amber-200">{error}</p>}</section>;
}

function ManualValidation({ disabled, onSubmit }: { disabled: boolean; onSubmit: (value: string) => void }) {
  const [value, setValue] = useState("");
  function submit(event: FormEvent) { event.preventDefault(); if (value.trim()) onSubmit(value.trim()); }
  return <form onSubmit={submit} className="rounded-3xl border border-white/10 bg-white/5 p-5"><p className="text-xs font-bold uppercase tracking-[.14em] text-axis-300">Validation manuelle</p><h2 className="mt-3 text-xl font-bold">Référence ou jeton</h2><p className="mt-2 text-sm leading-6 text-axis-200">À utiliser en cas de caméra indisponible. Le serveur applique les mêmes contrôles anti-fraude.</p><label className="mt-6 block text-xs font-semibold text-axis-200">Référence du ticket</label><input className="mt-2 w-full rounded-xl border border-white/15 bg-white/10 px-4 py-3 text-white outline-none placeholder:text-axis-400" placeholder="AX-… ou UUID" value={value} onChange={(e) => setValue(e.target.value)} required /><button disabled={disabled} className="mt-4 w-full rounded-xl bg-axis-500 px-4 py-3 text-sm font-bold text-white">Valider manuellement</button></form>;
}

function SeatOverview({ seats, tickets, enabled }: { seats: Seat[]; tickets: Ticket[]; enabled: boolean }) {
  if (!enabled) return null;
  const ticketBySeat = new Map(tickets.map((ticket) => [ticket.seat, ticket]));
  return <section className="mt-6 rounded-3xl bg-white p-5 text-axis-950"><div className="flex items-end justify-between gap-4"><div><p className="text-xs font-bold uppercase tracking-[.14em] text-axis-600">Vue consolidée</p><h2 className="mt-1 text-xl font-bold">Sièges du voyage</h2></div><p className="text-xs text-slate-500">{tickets.filter((t) => ["CHECKED", "COMPLETED"].includes(t.status)).length} contrôlé(s)</p></div>{seats.length === 0 ? <div className="mt-5"><EmptyState title="Plan non configuré" text="La capacité et la disposition doivent être renseignées par l’administrateur." /></div> : <div className="mt-5 grid grid-cols-4 gap-2 sm:grid-cols-6 md:grid-cols-8">{seats.map((seat) => { const ticket = ticketBySeat.get(seat.id); const checked = ticket && ["CHECKED", "COMPLETED"].includes(ticket.status); return <div key={seat.id} className={`grid aspect-square place-items-center rounded-xl text-sm font-bold ${checked ? "bg-emerald-600 text-white" : seat.status === "PAID" ? "bg-axis-700 text-white" : seat.status === "HELD" ? "bg-amber-100 text-amber-800" : "bg-axis-50 text-slate-400"}`} title={ticket?.passenger_name}>{seat.number}</div>; })}</div>}<div className="mt-4 flex flex-wrap gap-4 text-xs text-slate-500"><Legend color="bg-axis-50" text="Libre" /><Legend color="bg-amber-100" text="Réservé" /><Legend color="bg-axis-700" text="Vendu" /><Legend color="bg-emerald-600" text="Contrôlé" /></div></section>;
}

function Legend({ color, text }: { color: string; text: string }) { return <span className="flex items-center gap-1.5"><i className={`h-3 w-3 rounded ${color}`} />{text}</span>; }

function extractToken(value: string) {
  try { const parsed = JSON.parse(value) as { qr_token?: string }; if (parsed.qr_token) return parsed.qr_token; } catch { /* raw token */ }
  const parts = value.split("/").filter(Boolean); return parts[parts.length - 1] || value;
}
