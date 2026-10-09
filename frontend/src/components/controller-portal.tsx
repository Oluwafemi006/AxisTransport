"use client";

import { FormEvent, useCallback, useEffect, useRef, useState } from "react";
import { LoginCard } from "./login-card";
import { AccessDenied, EmptyState, Loading, Notice, SectionHeading, StaffLogin, StaffShell, StaffTitle, StatusBadge } from "./ui";
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
      // Les départs d'un itinéraire désactivé ne sont pas proposés.
      setUser(me); setTrips(allTrips.filter((trip) => trip.route_detail.active && !["COMPLETED", "CANCELLED"].includes(trip.status)));
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
  if (!getAccessToken() || (!loading && !user)) {
    return (
      <StaffLogin error={message}>
        <LoginCard title="Interface contrôleur" onSuccess={() => void load()} />
      </StaffLogin>
    );
  }

  return (
    <StaffShell user={user}>
      <StaffTitle eyebrow="Contrôle embarquement / à bord" title="Vérifier un billet" />
      {!user ? <Loading /> : (
        <>
          <section className="card">
            <label className="field-label" htmlFor="controlledTrip">Voyage contrôlé</label>
            <select id="controlledTrip" className="field" value={tripId} onChange={(e) => setTripId(e.target.value)}>
              <option value="">Choisir le voyage</option>
              {trips.map((trip) => <option key={trip.id} value={trip.id}>{trip.route_detail.label} · {formatDate(trip.departure_at)}</option>)}
            </select>
          </section>
          <div className="mt-5 grid gap-5 md:grid-cols-2">
            <Scanner disabled={!tripId} onValue={(value) => void validate(extractToken(value), "QR")} />
            <ManualValidation disabled={!tripId} onSubmit={(value) => void validate(value, "MANUAL")} />
          </div>
          {message && <Notice notice={{ text: message, tone: result ? "ok" : "error" }} className="mt-5" />}
          {result && (
            <article className="card mt-5">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="eyebrow">{result.ticket.reference}</p>
                  <h2 className="mt-1">{result.ticket.passenger_name}</h2>
                  <p className="text-sm text-slate-500">Siège {result.ticket.seat_detail.number} · {result.ticket.trip_detail.route_detail.label}</p>
                  <p className="text-sm text-slate-500">
                    {result.ticket.trip_detail.boarding_at && <>Embarquement : {formatDate(result.ticket.trip_detail.boarding_at)} · </>}
                    Départ : {formatDate(result.ticket.trip_detail.departure_at)}
                  </p>
                </div>
                <StatusBadge tone="green">Contrôlé</StatusBadge>
              </div>
            </article>
          )}
          <SeatOverview seats={seats} tickets={tickets} enabled={Boolean(tripId)} />
        </>
      )}
    </StaffShell>
  );
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
  return (
    <section className="card">
      <SectionHeading title="Scan QR" />
      <div className="relative aspect-[4/3] overflow-hidden rounded-xl bg-axis-950">
        <video ref={video} className="h-full w-full object-cover" muted playsInline />
        {!active && <div className="absolute inset-0 grid place-items-center px-6 text-center text-sm text-axis-200">Cadrez le QR code du ticket dans la caméra.</div>}
      </div>
      <button disabled={disabled} onClick={active ? stop : () => void start()} className="primary-button mt-4 w-full">{active ? "Arrêter la caméra" : "Démarrer le scan"}</button>
      {error && <Notice notice={{ text: error, tone: "error" }} className="mt-3" />}
    </section>
  );
}

function ManualValidation({ disabled, onSubmit }: { disabled: boolean; onSubmit: (value: string) => void }) {
  const [value, setValue] = useState("");
  function submit(event: FormEvent) { event.preventDefault(); if (value.trim()) onSubmit(value.trim()); }
  return (
    <form onSubmit={submit} className="card">
      <SectionHeading eyebrow="Validation manuelle" title="Référence ou jeton" />
      <p className="text-sm leading-6 text-slate-500">À utiliser en cas de caméra indisponible. Le serveur applique les mêmes contrôles anti-fraude.</p>
      <label className="field-label mt-5" htmlFor="manualReference">Référence du ticket</label>
      <input id="manualReference" className="field" placeholder="AX-… ou UUID" value={value} onChange={(e) => setValue(e.target.value)} required />
      <button disabled={disabled} className="primary-button mt-4 w-full">Valider manuellement</button>
    </form>
  );
}

function SeatOverview({ seats, tickets, enabled }: { seats: Seat[]; tickets: Ticket[]; enabled: boolean }) {
  if (!enabled) return null;
  const ticketBySeat = new Map(tickets.map((ticket) => [ticket.seat, ticket]));
  return (
    <section className="card mt-5">
      <SectionHeading
        eyebrow="Vue consolidée"
        title="Sièges du voyage"
        action={<StatusBadge tone="green">{tickets.filter((t) => ["CHECKED", "COMPLETED"].includes(t.status)).length} contrôlé(s)</StatusBadge>}
      />
      {seats.length === 0 ? (
        <EmptyState title="Plan non configuré" text="La capacité et la disposition doivent être renseignées par l’administrateur." />
      ) : (
        <div className="grid grid-cols-4 gap-2 sm:grid-cols-6 md:grid-cols-8 lg:grid-cols-12">
          {seats.map((seat) => {
            const ticket = ticketBySeat.get(seat.id);
            const checked = ticket && ["CHECKED", "COMPLETED"].includes(ticket.status);
            return (
              <div key={seat.id} className={`grid aspect-square place-items-center rounded-[10px] text-sm font-bold ${checked ? "bg-[var(--ok)] text-white" : seat.status === "PAID" ? "bg-[var(--navy)] text-white" : seat.status === "HELD" ? "bg-[var(--warnbg)] text-[var(--warn)]" : "border border-[var(--line)] bg-[var(--bg)] text-slate-400"}`} title={ticket?.passenger_name}>
                {seat.number}
              </div>
            );
          })}
        </div>
      )}
      <div className="mt-4 flex flex-wrap gap-4 text-xs text-slate-500">
        <Legend color="border border-[var(--line)] bg-[var(--bg)]" text="Libre" />
        <Legend color="bg-[var(--warnbg)]" text="Réservé" />
        <Legend color="bg-[var(--navy)]" text="Vendu" />
        <Legend color="bg-[var(--ok)]" text="Contrôlé" />
      </div>
    </section>
  );
}

function Legend({ color, text }: { color: string; text: string }) { return <span className="flex items-center gap-1.5"><i className={`h-3 w-3 rounded ${color}`} />{text}</span>; }

function extractToken(value: string) {
  try { const parsed = JSON.parse(value) as { qr_token?: string }; if (parsed.qr_token) return parsed.qr_token; } catch { /* raw token */ }
  const parts = value.split("/").filter(Boolean); return parts[parts.length - 1] || value;
}
