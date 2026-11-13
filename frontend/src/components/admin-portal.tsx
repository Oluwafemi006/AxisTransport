"use client";

import { PasswordInput } from "./password-input";
import { FormEvent, useCallback, useEffect, useState } from "react";
import { AccessDenied, EmptyState, Loading, Notice, type NoticeState, SectionHeading, StaffLogin, StaffShell, StaffTitle, StatusBadge, ticketTone, tripTone, useActionFeedback } from "./ui";
import { SoldToday } from "./sold-today";
import { LoginCard } from "./login-card";
import { HeadlineCards, ReportPanel } from "./admin-report";
import type { Headline } from "./admin-report";

// Valeur de repli quand l'API du tableau de bord échoue : zéros, jamais une valeur inventée.
const emptyHeadline: Headline = { tickets_sold: 0, tickets_scanned: 0, tickets_refunded: 0, gross_revenue: 0, parcels: { tracked: 0, cancelled: 0, picked_up: 0 } };
import { BusSeatMap } from "./bus-seat-map";
import { apiFetch, apiList, clearTokens, formatDate, getAccessToken, money } from "@/lib/api";
import { actionErrorText, beninDateKey, holdMinutesConfigured, soldTicketWhatsappHref, upcomingSellableTrips, whatsappHref, type SegmentDirection, type SegmentOffer } from "@/lib/portal-rules";

import type { AgencyProfile, AgencySettingChange, BoardingPoint, Booking, FareRule, FeatureFlag, LineState, LineStopRow, Location, ManualTicketChange, MissingSegmentFare, BusPosition, Tax, Parcel, PaymentIncident, PaymentMethod, RentalBooking, Route, SegmentFare, SegmentFareChange, Seat, SystemSetting, Ticket, Trip, User, Vehicle, WeeklySchedule } from "@/lib/types";

type AdminTab = "dashboard" | "bilan" | "planning" | "guichet" | "billets" | "points" | "colis" | "locations" | "flotte" | "tarifs" | "villes" | "troncons" | "agence" | "paiements" | "equipe";
type Dashboard = {
  today: Headline & { date: string };
  all_time: Headline & { since: string };
  tickets: { sold: number; online: number; counter: number; checked: number; refunded: number; cancelled_or_refunded: number };
  revenue: { total: number; by_payment_method: Array<{ payment_method__label: string; total: number }> };
  parcels: Array<{ status: string; count: number }>;
  trips: Array<{ id: number; label: string; sold: number; checked: number; capacity: number | null; revenue: number }>;
};

const nextParcelStatus: Record<string, string> = {
  REGISTERED: "DEPOSITED", DEPOSITED: "ACCEPTED", ACCEPTED: "ASSIGNED", ASSIGNED: "LOADED",
  LOADED: "IN_TRANSIT", IN_TRANSIT: "ARRIVED", ARRIVED: "READY_FOR_PICKUP", READY_FOR_PICKUP: "PICKED_UP",
};

const tabs: Array<[AdminTab, string]> = [
  ["dashboard", "Tableau de bord"], ["bilan", "Bilan global"], ["planning", "Trajets & planning"], ["guichet", "Vente au guichet"], ["billets", "Billets"], ["points", "Points d’embarquement"], ["colis", "Colis"], ["locations", "Locations"],
  ["flotte", "Flotte"], ["tarifs", "Tarifs & règles"], ["villes", "Villes & ligne"], ["troncons", "Tarifs par tronçon"], ["agence", "Agence et taxes"], ["paiements", "Incidents de paiement"], ["equipe", "Équipe & rôles"],
];

// Erreur de chargement affichée dans un panneau (les actions d'écriture passent par useActionFeedback).
function failure(reason: unknown, fallback: string): NoticeState {
  return { text: actionErrorText(reason, fallback), tone: "error" };
}

export function AdminPortal() {
  const [me, setMe] = useState<User | null>(null);
  const [tab, setTab] = useState<AdminTab>("dashboard");
  const [dashboard, setDashboard] = useState<Dashboard | null>(null);
  const [locations, setLocations] = useState<Location[]>([]);
  const [routes, setRoutes] = useState<Route[]>([]);
  const [trips, setTrips] = useState<Trip[]>([]);
  const [vehicles, setVehicles] = useState<Vehicle[]>([]);
  const [fares, setFares] = useState<FareRule[]>([]);
  const [flags, setFlags] = useState<FeatureFlag[]>([]);
  const [users, setUsers] = useState<User[]>([]);
  const [parcels, setParcels] = useState<Parcel[]>([]);
  const [payments, setPayments] = useState<PaymentMethod[]>([]);
  const [settings, setSettings] = useState<SystemSetting[]>([]);
  const [incidents, setIncidents] = useState<PaymentIncident[]>([]);
  const [weeklySchedules, setWeeklySchedules] = useState<WeeklySchedule[]>([]);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const [accessDenied, setAccessDenied] = useState(false);

  const load = useCallback(async () => {
    if (!getAccessToken()) { setLoading(false); return; }
    setLoading(true); setError(""); setAccessDenied(false);
    try {
      const currentUser = await apiFetch<User>("/auth/me/");
      if (currentUser.role !== "ADMIN") { setMe(currentUser); setAccessDenied(true); return; }
      // Chaque liste est chargée à part : une erreur sur l'une n'empêche pas d'ouvrir les autres onglets.
      const failed: string[] = [];
      const safe = <T,>(label: string, fallback: T, request: Promise<T>) => request.catch(() => { failed.push(label); return fallback; });
      const [dash, allLocations, allRoutes, allTrips, allVehicles, allFares, allFlags, team, allParcels, methods, allSettings, allIncidents, allWeekly] = await Promise.all([
        safe<Dashboard>("tableau de bord", { today: { ...emptyHeadline, date: beninDateKey() }, all_time: { ...emptyHeadline, since: beninDateKey() }, tickets: { sold: 0, checked: 0, online: 0, counter: 0, refunded: 0, cancelled_or_refunded: 0 }, parcels: [], revenue: { total: 0, by_payment_method: [] }, trips: [] }, apiFetch<Dashboard>("/dashboard/")),
        safe<Location[]>("villes", [], apiList<Location>("/locations/?all=true")), safe<Route[]>("parcours", [], apiList<Route>("/routes/?all=true")),
        safe<Trip[]>("départs", [], apiList<Trip>("/trips/?all=true")), safe<Vehicle[]>("flotte", [], apiList<Vehicle>("/vehicles/")), safe<FareRule[]>("règles tarifaires", [], apiList<FareRule>("/fare-rules/?all=true")),
        safe<FeatureFlag[]>("fonctions", [], apiList<FeatureFlag>("/feature-flags/")), safe<User[]>("équipe", [], apiList<User>("/users/")), safe<Parcel[]>("colis", [], apiList<Parcel>("/parcels/")),
        safe<PaymentMethod[]>("moyens de paiement", [], apiList<PaymentMethod>("/payment-methods/?all=true")), safe<SystemSetting[]>("réglages", [], apiList<SystemSetting>("/settings/")),
        safe<PaymentIncident[]>("incidents", [], apiList<PaymentIncident>("/payment-incidents/")), safe<WeeklySchedule[]>("planning", [], apiList<WeeklySchedule>("/weekly-schedules/")),
      ]);
      if (failed.length) setError(`Chargement incomplet : ${failed.join(", ")}. Cliquez sur « Actualiser » pour réessayer.`);
      setMe(currentUser); setDashboard(dash); setLocations(allLocations); setRoutes(allRoutes); setTrips(allTrips); setVehicles(allVehicles);
      setFares(allFares); setFlags(allFlags); setUsers(team); setParcels(allParcels); setPayments(methods); setSettings(allSettings); setIncidents(allIncidents);
      setWeeklySchedules(allWeekly);
    } catch (reason) { setError(reason instanceof Error ? reason.message : "Chargement impossible."); if ((reason as { status?: number }).status === 401) { clearTokens(); setMe(null); } }
    finally { setLoading(false); }
  }, []);

  useEffect(() => { void load(); }, [load]);

  if (accessDenied) return <AccessDenied area="l’administration" />;
  if (!getAccessToken() || (!loading && !me)) {
    return (
      <StaffLogin error={error}>
        <LoginCard title="Administration Axis" onSuccess={() => void load()} />
      </StaffLogin>
    );
  }

  // Les panneaux restent affichés pendant une actualisation : les démonter ferait perdre les saisies en cours.
  return (
    <StaffShell user={me} tabs={tabs} current={tab} onTab={setTab}>
      <StaffTitle
        eyebrow="Back-office"
        title={tabs.find(([key]) => key === tab)?.[1] ?? ""}
        action={<button onClick={() => void load()} className="secondary-button" disabled={loading}>{loading ? "Actualisation…" : "Actualiser"}</button>}
      />
      {error && <Notice notice={{ text: error, tone: "error" }} className="mb-5" />}
      {dashboard && !holdMinutesConfigured(settings) && <Notice notice={{ text: "Aucune réservation possible : la durée de blocage d’un siège n’est pas saisie. Renseignez-la dans l’onglet « Tarifs & règles », bloc « Blocage d’un siège ».", tone: "error" }} className="mb-5" />}
      {!dashboard ? <Loading /> : (
        <>
          {tab === "dashboard" && <><BusPositions /><DashboardPanel data={dashboard} trips={trips} /></>}
          {tab === "bilan" && <ReportPanel />}
          {tab === "planning" && <PlanningPanel routes={routes} vehicles={vehicles.filter((v) => v.category === "BUS")} trips={trips} weeklySchedules={weeklySchedules} onChanged={load} />}
          {tab === "guichet" && <><CounterPanel trips={trips} payments={payments} onChanged={load} /><SoldToday /></>}
          {tab === "billets" && <TicketsPanel settings={settings} onChanged={load} />}
          {tab === "points" && <BoardingPointsPanel locations={locations} onChanged={load} />}
          {tab === "colis" && <ParcelPanel parcels={parcels} trips={trips} onChanged={load} />}
          {tab === "locations" && <RentalPanel />}
          {tab === "flotte" && <FleetPanel locations={locations} vehicles={vehicles} onChanged={load} />}
          {tab === "tarifs" && <PricingPanel routes={routes} fares={fares} flags={flags} payments={payments} settings={settings} onChanged={load} />}
          {tab === "villes" && <LinePanel locations={locations} onChanged={load} />}
          {tab === "troncons" && <SegmentFarePanel />}
          {tab === "agence" && <AgencyPanel />}
          {tab === "paiements" && <div className="space-y-5"><RefundDueBookingsPanel /><IncidentPanel incidents={incidents} onChanged={load} /><ManualTicketChangeLog /></div>}
          {tab === "equipe" && <TeamPanel users={users} onChanged={load} />}
        </>
      )}
    </StaffShell>
  );
}

function BusPositions() {
  const [rows, setRows] = useState<BusPosition[]>([]);
  useEffect(() => {
    const read = () => void apiFetch<BusPosition[]>("/bus-positions/").then(setRows).catch(() => undefined);
    read();
    const timer = window.setInterval(read, 60000);
    return () => window.clearInterval(timer);
  }, []);
  if (rows.length === 0) return null;
  return (
    <section className="card mb-5">
      <SectionHeading eyebrow="Confirmé par les contrôleurs" title="Position des bus" />
      <ul className="space-y-1 text-sm">
        {rows.slice(0, 10).map((row) => (
          <li key={row.id}>{new Date(row.confirmed_at).toLocaleString("fr-FR", { timeZone: "Africa/Porto-Novo", dateStyle: "short", timeStyle: "short" })} : <strong>{row.route}</strong> {row.final ? "arrivé à destination," : "arrivé à"} {row.stop}{row.confirmed_by ? ` (${row.confirmed_by})` : ""}</li>
        ))}
      </ul>
    </section>
  );
}

function DashboardPanel({ data, trips }: { data: Dashboard | null; trips: Trip[] }) {
  if (!data) return null;
  // Les départs d'un itinéraire désactivé ne sont pas listés ici ; ils restent visibles dans « Trajets & planning ».
  const now = Date.now();
  const listed = trips
    .filter((trip) => trip.route_detail.active && trip.status !== "CANCELLED" && trip.status !== "COMPLETED" && new Date(trip.departure_at).getTime() >= now)
    .sort((a, b) => a.departure_at.localeCompare(b.departure_at));
  return (
    <>
      <SectionHeading eyebrow="Heure du Bénin, de minuit à minuit" title={`Aujourd'hui (${new Date(`${data.today.date}T00:00:00`).toLocaleDateString("fr-FR", { weekday: "long", day: "numeric", month: "long" })})`} />
      <HeadlineCards data={data.today} />
      <div className="mt-5">
        <SectionHeading eyebrow={`Depuis le ${new Date(`${data.all_time.since}T00:00:00`).toLocaleDateString("fr-FR")}`} title="Cumul global" />
        <HeadlineCards data={data.all_time} />
      </div>
      <div className="mt-5 grid gap-5 xl:grid-cols-[1.4fr_.6fr]">
        <section className="card">
          <SectionHeading eyebrow="Du plus proche au plus lointain" title="Prochains départs" />
          {listed.length ? (
            <div className="table-scroll">
              <table className="staff-table min-w-[620px]">
                <thead><tr><th>Trajet</th><th>Date</th><th>Places prises (vendues ou retenues)</th><th>Statut</th></tr></thead>
                <tbody>
                  {listed.slice(0, 8).map((trip) => (
                    <tr key={trip.id}>
                      <td className="strong">{trip.route_detail.label}</td>
                      <td>{formatDate(trip.departure_at)}</td>
                      <td>{trip.vehicle_detail.capacity ? `${trip.vehicle_detail.capacity - trip.available_seats} / ${trip.vehicle_detail.capacity}` : "Capacité requise"}</td>
                      <td><StatusBadge tone={tripTone(trip.status)}>{trip.status_display}</StatusBadge></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : <EmptyState title="Aucun trajet" text="Configurez la capacité du bus, puis créez le planning réel." />}
        </section>
        <section className="card">
          <SectionHeading eyebrow="Canaux" title="Répartition des ventes" />
          <div className="space-y-3">
            <Metric label="En ligne" value={data.tickets.online} />
            <Metric label="Guichet" value={data.tickets.counter} />
            <Metric label="Annulés / remboursés" value={data.tickets.cancelled_or_refunded} />
          </div>
        </section>
      </div>
    </>
  );
}

function Metric({ label, value }: { label: string; value: number }) {
  return <div className="metric"><span>{label}</span><b>{value}</b></div>;
}

function PlanningPanel({ routes, vehicles, trips, weeklySchedules, onChanged }: { routes: Route[]; vehicles: Vehicle[]; trips: Trip[]; weeklySchedules: WeeklySchedule[]; onChanged: () => Promise<void> }) {
  const feedback = useActionFeedback();
  const [busy, setBusy] = useState(false);

  // Édition d'un jour du planning hebdomadaire par défaut
  const [editingSchedule, setEditingSchedule] = useState<WeeklySchedule | null>(null);
  const [scheduleForm, setScheduleForm] = useState({ is_active: true, route: "", vehicle: "", departure_time: "08:00", notes: "" });

  function openEditSchedule(sched: WeeklySchedule) {
    setEditingSchedule(sched);
    setScheduleForm({
      is_active: sched.is_active,
      route: sched.route ? String(sched.route) : "",
      vehicle: sched.vehicle ? String(sched.vehicle) : "",
      departure_time: sched.departure_time ? sched.departure_time.slice(0, 5) : "08:00",
      notes: sched.notes || "",
    });
  }

  async function saveSchedule(event: FormEvent) {
    event.preventDefault();
    if (!editingSchedule) return;
    setBusy(true);
    try {
      await apiFetch<WeeklySchedule>(`/weekly-schedules/${editingSchedule.id}/`, {
        method: "PATCH",
        body: JSON.stringify({
          is_active: scheduleForm.is_active,
          route: scheduleForm.is_active && scheduleForm.route ? Number(scheduleForm.route) : null,
          vehicle: scheduleForm.is_active && scheduleForm.vehicle ? Number(scheduleForm.vehicle) : null,
          departure_time: scheduleForm.is_active ? scheduleForm.departure_time : null,
          notes: scheduleForm.notes,
        }),
      });
      feedback.success(`Planning du ${editingSchedule.day_of_week_display} mis à jour.`);
      setEditingSchedule(null);
      await onChanged();
    } catch (reason) {
      feedback.failure(reason, "La modification du planning hebdomadaire a échoué.");
    } finally {
      setBusy(false);
    }
  }

  async function generateFromWeekly() {
    setBusy(true);
    try {
      const result = await apiFetch<{ created: number; trips: Trip[] }>("/weekly-schedules/generate-trips/", {
        method: "POST",
        body: JSON.stringify({ weeks: 4 }),
      });
      if (result.created === 0) {
        feedback.info("Tous les trajets des 4 prochaines semaines existent déjà dans le planning réel.");
      } else {
        feedback.success(`${result.created} trajet(s) réel(s) généré(s) pour les 4 prochaines semaines.`);
      }
      await onChanged();
    } catch (reason) {
      feedback.failure(reason, "La génération des trajets a échoué.");
    } finally {
      setBusy(false);
    }
  }

  // Formulaire d'ajout / modification exceptionnelle d'un trajet réel
  const [editingTripId, setEditingTripId] = useState<number | null>(null);
  const emptyTripForm = {
    route: "",
    vehicle: "",
    departure_date: "",
    departure_time: "",
    arrival_time: "",
    status: "SCHEDULED",
    note: "",
  };
  const [tripForm, setTripForm] = useState(emptyTripForm);

  function resetTripForm() {
    setEditingTripId(null);
    setTripForm(emptyTripForm);
  }

  function startEditTrip(trip: Trip) {
    setEditingTripId(trip.id);
    const depDate = trip.departure_at.slice(0, 10);
    const depTime = trip.departure_at.slice(11, 16);
    const arrTime = trip.arrival_at ? trip.arrival_at.slice(11, 16) : "";
    setTripForm({
      route: String(trip.route),
      vehicle: String(trip.vehicle),
      departure_date: depDate,
      departure_time: depTime,
      arrival_time: arrTime,
      status: trip.status,
      note: trip.note || "",
    });
  }

  function cancelEditTrip() {
    resetTripForm();
  }

  async function submitTrip(event: FormEvent) {
    event.preventDefault();
    if (!tripForm.departure_date || !tripForm.departure_time) {
      feedback.failure(null, "La date et l'heure de départ sont obligatoires.");
      return;
    }

    // Validation stricte : arrivée même jour et strictement postérieure au départ
    if (tripForm.arrival_time && tripForm.arrival_time <= tripForm.departure_time) {
      feedback.failure(
        null,
        `L’heure d’arrivée (${tripForm.arrival_time}) doit être strictement postérieure à l’heure de départ (${tripForm.departure_time}) sur la même journée.`
      );
      return;
    }

    const departure_at = `${tripForm.departure_date}T${tripForm.departure_time}:00`;
    const arrival_at = tripForm.arrival_time ? `${tripForm.departure_date}T${tripForm.arrival_time}:00` : null;

    setBusy(true);
    try {
      if (editingTripId) {
        await apiFetch<Trip>(`/trips/${editingTripId}/`, {
          method: "PATCH",
          body: JSON.stringify({
            route: Number(tripForm.route),
            vehicle: Number(tripForm.vehicle),
            departure_at,
            arrival_at,
            status: tripForm.status,
            note: tripForm.note,
          }),
        });
        resetTripForm();
        feedback.success("Trajet mis à jour avec succès.");
      } else {
        await apiFetch<Trip>("/trips/", {
          method: "POST",
          body: JSON.stringify({
            route: Number(tripForm.route),
            vehicle: Number(tripForm.vehicle),
            departure_at,
            arrival_at,
            status: "SCHEDULED",
            note: tripForm.note,
          }),
        });
        resetTripForm();
        feedback.success("Trajet ajouté au planning.");
      }
      await onChanged();
    } catch (reason) {
      feedback.failure(reason, editingTripId ? "La mise à jour du trajet a échoué." : "Le trajet n’a pas été ajouté.");
    } finally {
      setBusy(false);
    }
  }

  // Planning quotidien sens alterné (outil d'assistance existant)
  const [plan, setPlan] = useState({ route: "", vehicle: "", start_date: "", days: "", departure_time: "09:00" });

  async function generateAlternating(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    try {
      const result = await apiFetch<{ created: number; skipped: Array<{ date: string; reason: string }> }>("/trips/generate/", {
        method: "POST",
        body: JSON.stringify({ ...plan, route: Number(plan.route), vehicle: Number(plan.vehicle), days: Number(plan.days) }),
      });
      const skipped = result.skipped.length ? ` ${result.skipped.length} jour(s) ignoré(s) : ${result.skipped.map((item) => `${item.date} (${item.reason})`).join(", ")}.` : "";
      if (result.created === 0) feedback.info(`Aucun départ créé.${skipped}`);
      else feedback.success(`${result.created} départ(s) créé(s) à ${plan.departure_time}, sens alterné.${skipped}`);
      await onChanged();
    } catch (reason) {
      feedback.failure(reason, "Le planning n’a pas été créé.");
    } finally {
      setBusy(false);
    }
  }

  async function cancel(trip: Trip) {
    if (!window.confirm(`Confirmez-vous l'annulation du départ du ${formatDate(trip.departure_at)} ?`)) return;
    try {
      await apiFetch(`/trips/${trip.id}/`, { method: "PATCH", body: JSON.stringify({ status: "CANCELLED" }) });
      feedback.success(`Trajet du ${formatDate(trip.departure_at)} annulé.`);
      await onChanged();
    } catch (reason) {
      feedback.failure(reason, "Le trajet n’a pas été annulé.");
    }
  }

  // Planning réel : départs à venir d'abord, passés et annulés masqués sauf demande.
  const [showPast, setShowPast] = useState(false);
  const nowMs = Date.now();
  const plannedTrips = [...trips]
    .filter((trip) => showPast || (trip.status !== "CANCELLED" && new Date(trip.departure_at).getTime() >= nowMs - 12 * 3600 * 1000))
    .sort((a, b) => (showPast ? b.departure_at.localeCompare(a.departure_at) : a.departure_at.localeCompare(b.departure_at)));

  // Tri des jours de semaine dans l'ordre Lundi (0) -> Dimanche (6)
  const sortedWeekly = [...weeklySchedules].sort((a, b) => a.day_of_week - b.day_of_week);

  return (
    <div className="space-y-6">
      {/* ── Section 1 : Planning hebdomadaire par défaut ── */}
      <section className="card">
        <SectionHeading
          eyebrow="Horaires réels de référence"
          title="Planning hebdomadaire par défaut"
          action={
            <button onClick={() => void generateFromWeekly()} className="secondary-button" disabled={busy}>
              {busy ? "Génération en cours…" : "Générer les trajets réels (4 prochaines semaines)"}
            </button>
          }
        />
        <p className="mb-4 text-sm text-slate-500">
          Ces horaires de base définissent les départs réguliers de l'agence pour chaque jour de la semaine. Cliquez sur « Générer les trajets réels » pour instancier automatiquement les départs des semaines à venir.
        </p>

        {sortedWeekly.length ? (
          <div className="table-scroll">
            <table className="staff-table min-w-[720px]">
              <thead>
                <tr>
                  <th>Jour</th>
                  <th>Statut</th>
                  <th>Parcours</th>
                  <th>Départ</th>
                  <th>Bus assigné</th>
                  <th>Remarques</th>
                  <th className="text-right">Action</th>
                </tr>
              </thead>
              <tbody>
                {sortedWeekly.map((item) => (
                  <tr key={item.id} className={!item.is_active ? "opacity-60 bg-slate-50/50" : undefined}>
                    <td className="strong">{item.day_of_week_display}</td>
                    <td>
                      <StatusBadge tone={item.is_active ? "green" : "grey"}>
                        {item.is_active ? "Trajet régulier" : "Repos / Aucun"}
                      </StatusBadge>
                    </td>
                    <td>{item.is_active && item.route_detail ? item.route_detail.label : "—"}</td>
                    <td>{item.is_active && item.departure_time_display ? `${item.departure_time_display}` : "—"}</td>
                    <td>{item.is_active && item.vehicle_detail ? item.vehicle_detail.name : (item.is_active ? "Yutong (défaut)" : "—")}</td>
                    <td className="text-sm text-slate-500">{item.notes || "—"}</td>
                    <td className="text-right">
                      <button onClick={() => openEditSchedule(item)} className="text-button">
                        Modifier
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <EmptyState title="Aucun planning hebdomadaire" text="Exécutez le script d'initialisation pour charger la grille par défaut." />
        )}

        {/* Modal/Formulaire d'édition d'un jour du planning de base */}
        {editingSchedule && (
          <div className="mt-5 rounded-lg border border-[var(--brand)] bg-sky-50/30 p-4">
            <div className="mb-3 flex items-center justify-between">
              <h4 className="font-semibold text-slate-800">
                Modifier l’horaire du {editingSchedule.day_of_week_display}
              </h4>
              <button type="button" onClick={() => setEditingSchedule(null)} className="text-sm text-slate-500 hover:text-slate-800">
                Fermer ✕
              </button>
            </div>
            <form onSubmit={saveSchedule} className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
              <label className="block">
                <span className="field-label">Statut du jour</span>
                <select
                  className="field"
                  value={scheduleForm.is_active ? "1" : "0"}
                  onChange={(e) => setScheduleForm({ ...scheduleForm, is_active: e.target.value === "1" })}
                >
                  <option value="1">Trajet régulier assuré</option>
                  <option value="0">Aucun départ (Repos / Maintenance)</option>
                </select>
              </label>

              {scheduleForm.is_active && (
                <>
                  <Select
                    label="Parcours"
                    value={scheduleForm.route}
                    onChange={(value) => setScheduleForm({ ...scheduleForm, route: value })}
                    options={routes.map((r) => [String(r.id), r.label])}
                  />
                  <Input
                    label="Heure de départ"
                    type="time"
                    value={scheduleForm.departure_time}
                    onChange={(value) => setScheduleForm({ ...scheduleForm, departure_time: value })}
                  />
                  <Select
                    label="Bus"
                    value={scheduleForm.vehicle}
                    onChange={(value) => setScheduleForm({ ...scheduleForm, vehicle: value })}
                    options={vehicles.map((v) => [String(v.id), v.name])}
                    required={false}
                  />
                </>
              )}

              <div className={scheduleForm.is_active ? "sm:col-span-2 lg:col-span-3" : "sm:col-span-2"}>
                <Input
                  label="Remarques (ex: Repos/Visite technique)"
                  value={scheduleForm.notes}
                  onChange={(value) => setScheduleForm({ ...scheduleForm, notes: value })}
                  required={false}
                />
              </div>

              <div className="flex items-end gap-2">
                <button className="primary-button w-full" disabled={busy}>
                  Enregistrer
                </button>
                <button type="button" onClick={() => setEditingSchedule(null)} className="secondary-button" disabled={busy}>
                  Annuler
                </button>
              </div>
            </form>
          </div>
        )}
      </section>

      {/* ── Section 2 : Planning réel et Formulaire d'ajustement ── */}
      <div className="grid gap-5 xl:grid-cols-[1.4fr_.6fr]">
        <section className="card">
          <SectionHeading eyebrow="Trajets opérationnels" title="Planning réel" action={<label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={showPast} onChange={(e) => setShowPast(e.target.checked)} />Afficher les départs passés et annulés</label>} />
          {plannedTrips.length ? (
            <div className="table-scroll">
              <table className="staff-table min-w-[720px]">
                <thead>
                  <tr>
                    <th>Date & Départ</th>
                    <th>Arrivée</th>
                    <th>Parcours</th>
                    <th>Bus</th>
                    <th>Places</th>
                    <th>Statut</th>
                    <th>Notes</th>
                    <th className="text-right">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {plannedTrips.map((trip) => (
                    <tr key={trip.id} className={editingTripId === trip.id ? "bg-amber-50/60" : undefined}>
                      <td className="strong">{formatDate(trip.departure_at)}</td>
                      <td>{trip.arrival_at ? formatDate(trip.arrival_at) : "—"}</td>
                      <td className="strong">{trip.route_detail.label}</td>
                      <td>{trip.vehicle_detail.name}</td>
                      <td>{trip.vehicle_detail.capacity ?? "À configurer"}</td>
                      <td>
                        <span className="flex flex-wrap gap-1.5">
                          <StatusBadge tone={tripTone(trip.status)}>{trip.status_display}</StatusBadge>
                          {!trip.route_detail.active && <StatusBadge tone="grey">Itinéraire inactif</StatusBadge>}
                        </span>
                      </td>
                      <td className="text-xs text-slate-500">{trip.note || "—"}</td>
                      <td className="text-right whitespace-nowrap">
                        <button onClick={() => startEditTrip(trip)} className="text-button mr-2">
                          Modifier
                        </button>
                        {trip.status !== "CANCELLED" && (
                          <button onClick={() => void cancel(trip)} className="text-button danger">
                            Annuler
                          </button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <EmptyState
              title="Planning vide"
              text="Cliquez sur « Générer les trajets réels » en haut pour créer les départs selon la grille hebdomadaire."
            />
          )}
        </section>

        <section className="card">
          <div className="flex items-center justify-between">
            <SectionHeading
              eyebrow={editingTripId ? "Ajustement ponctuel" : "Horaire administrable"}
              title={editingTripId ? `Modifier le départ #${editingTripId}` : "Ajouter un trajet"}
            />
            {editingTripId && (
              <button onClick={cancelEditTrip} className="text-xs text-slate-500 hover:text-slate-800 underline">
                Annuler l'édition
              </button>
            )}
          </div>

          {editingTripId && (
            <div className="mb-4 rounded border border-amber-200 bg-amber-50 p-2.5 text-xs text-amber-800">
              Vous modifiez un trajet existant (retard, changement de bus, note d'information).
            </div>
          )}

          <form onSubmit={submitTrip} className="space-y-4">
            <Select
              label="Parcours"
              value={tripForm.route}
              onChange={(value) => setTripForm({ ...tripForm, route: value })}
              options={routes.map((r) => [String(r.id), r.label])}
            />
            <Select
              label="Véhicule"
              value={tripForm.vehicle}
              onChange={(value) => setTripForm({ ...tripForm, vehicle: value })}
              options={vehicles.map((v) => [String(v.id), `${v.name} · ${v.capacity ?? "capacité requise"}`])}
            />

            <div className="grid grid-cols-2 gap-3">
              <Input
                label="Date de départ"
                type="date"
                value={tripForm.departure_date}
                onChange={(value) => setTripForm({ ...tripForm, departure_date: value })}
              />
              <Input
                label="Heure de départ"
                type="time"
                value={tripForm.departure_time}
                onChange={(value) => setTripForm({ ...tripForm, departure_time: value })}
              />
            </div>

            <div>
              <Input
                label="Heure d'arrivée (MÊME JOUR)"
                type="time"
                value={tripForm.arrival_time}
                onChange={(value) => setTripForm({ ...tripForm, arrival_time: value })}
                required={false}
              />
              <p className="mt-1 text-xs text-slate-500">
                La date d'arrivée est automatiquement verrouillée sur la date de départ. Seule l'heure est demandée.
              </p>
            </div>

            {editingTripId && (
              <Select
                label="Statut du trajet"
                value={tripForm.status}
                onChange={(value) => setTripForm({ ...tripForm, status: value })}
                options={[
                  ["SCHEDULED", "Planifié"],
                  ["BOARDING", "Embarquement"],
                  ["IN_PROGRESS", "En cours"],
                  ["COMPLETED", "Terminé"],
                  ["CANCELLED", "Annulé"],
                ]}
              />
            )}

            <Input
              label="Remarque / Motif de modification"
              value={tripForm.note}
              onChange={(value) => setTripForm({ ...tripForm, note: value })}
              required={false}
            />

            <button className="primary-button w-full" disabled={busy}>
              {editingTripId ? "Enregistrer les modifications" : "Ajouter au planning"}
            </button>
            {editingTripId && (
              <button type="button" onClick={cancelEditTrip} className="secondary-button w-full mt-2" disabled={busy}>
                Revenir à l'ajout de trajet
              </button>
            )}
          </form>

          <hr className="my-6 border-[var(--line)]" />
          <SectionHeading eyebrow="Outil auxiliaire" title="Générateur sens alterné" />
          <p className="mb-4 text-xs text-slate-500">
            Alterne entre le parcours choisi et le parcours inverse sur une période libre.
          </p>
          <form onSubmit={generateAlternating} className="space-y-3">
            <Select
              label="Parcours du 1er jour"
              value={plan.route}
              onChange={(value) => setPlan({ ...plan, route: value })}
              options={routes.map((r) => [String(r.id), r.label])}
            />
            <Select
              label="Bus"
              value={plan.vehicle}
              onChange={(value) => setPlan({ ...plan, vehicle: value })}
              options={vehicles.map((v) => [String(v.id), `${v.name} · ${v.capacity ?? "capacité requise"}`])}
            />
            <div className="grid grid-cols-2 gap-3">
              <Input
                label="1er jour"
                type="date"
                value={plan.start_date}
                onChange={(value) => setPlan({ ...plan, start_date: value })}
              />
              <Input
                label="Nombre de jours"
                type="number"
                value={plan.days}
                onChange={(value) => setPlan({ ...plan, days: value })}
              />
            </div>
            <Input
              label="Heure de départ"
              type="time"
              value={plan.departure_time}
              onChange={(value) => setPlan({ ...plan, departure_time: value })}
            />
            <button className="secondary-button w-full" disabled={busy}>
              Lancer l'alternance
            </button>
          </form>
        </section>
      </div>
    </div>
  );
}

// Vente au guichet (/guichet et onglet admin) : même chemin serveur que l'app du personnel (/staff/sales/).
// Le serveur décide de tout : départs vendables, tronçons avec tarif, prix, place tenue, paiement et émission.
type SaleQuote = { payment_method: number; label: string; total: number | string; currency: string; online: boolean };
type SaleSegment = { origin_id: number; origin: string; destination_id: number; destination: string; quotes: SaleQuote[] };
// `departed` : départ du jour dont l'heure est passée, encore vendable (calculé par le serveur).
type SaleTrip = Trip & { segments: SaleSegment[]; departed?: boolean };
type SaleCheckout = { transaction_id: string; payment_url: string | null; payment_method: number; total: number | string; currency: string };
type SaleResult = { booking: Booking; checkout?: SaleCheckout | null; payment_error?: string };

function newSaleKey() {
  return typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID().replace(/-/g, "")
    : `${Date.now()}${Math.random().toString(36).slice(2)}`.slice(0, 40);
}

export function CounterPanel({ onChanged }: { trips?: Trip[]; payments?: PaymentMethod[]; onChanged: () => Promise<void> }) {
  const feedback = useActionFeedback();
  const [saleTrips, setSaleTrips] = useState<SaleTrip[] | null>(null);
  const [routeLabel, setRouteLabel] = useState("");
  const [pairKey, setPairKey] = useState("");
  const [tripId, setTripId] = useState("");
  const [boardingPointId, setBoardingPointId] = useState("");
  const [alightingPointId, setAlightingPointId] = useState("");
  const [seats, setSeats] = useState<Seat[]>([]);
  const [seat, setSeat] = useState("");
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [methodId, setMethodId] = useState<number | null>(null);
  const [result, setResult] = useState<SaleResult | null>(null);
  // Numéro WhatsApp du client, facultatif : prérempli avec son téléphone, sert seulement à lui envoyer son billet.
  const [whatsapp, setWhatsapp] = useState("");
  const [busy, setBusy] = useState(false);
  const [saleKey, setSaleKey] = useState<string | null>(null);

  const loadOptions = useCallback(async () => {
    try {
      const payload = await apiFetch<{ trips: SaleTrip[] }>("/staff/sales/options/");
      // Le serveur ne renvoie que les départs vendables (à venir, ni annulés ni terminés) : tri du plus proche au plus lointain.
      setSaleTrips([...(payload.trips || [])].sort((a, b) => a.departure_at.localeCompare(b.departure_at)));
    } catch (reason) { setSaleTrips([]); feedback.failure(reason, "Les départs à vendre n’ont pas pu être chargés."); }
  }, [feedback]);

  useEffect(() => { void loadOptions(); }, [loadOptions]);

  const pairOf = (item: { origin_id: number; destination_id: number }) => `${item.origin_id}-${item.destination_id}`;
  const trips = saleTrips ?? [];
  const routeLabels = Array.from(new Set(trips.map((trip) => trip.route_detail.label)));
  const currentRoute = routeLabel || routeLabels[0] || "";
  const routeTrips = trips.filter((trip) => trip.route_detail.label === currentRoute);
  // Tronçons avec tarif, dans l'ordre du bus, sans doublon d'un départ à l'autre.
  const pairs: SaleSegment[] = [];
  for (const trip of routeTrips) for (const segment of trip.segments || []) if (!pairs.some((item) => pairOf(item) === pairOf(segment))) pairs.push(segment);
  const pair = pairs.find((item) => pairOf(item) === pairKey) || null;
  const pairTrips = pair ? routeTrips.filter((trip) => (trip.segments || []).some((segment) => pairOf(segment) === pairKey)) : [];
  const selectedTrip = pairTrips.find((trip) => String(trip.id) === tripId) || null;
  const quotes = selectedTrip?.segments.find((segment) => pairOf(segment) === pairKey)?.quotes || pair?.quotes || [];
  const quote = quotes.find((item) => item.payment_method === methodId) || null;
  const price = quotes[0] ? money(quotes[0].total, quotes[0].currency) : "";

  const pointsOf = (locationId: number | undefined) => {
    const stop = selectedTrip?.route_detail.stops?.find((item) => item.id === locationId);
    return (stop?.boarding_points || []).filter((point) => point.active);
  };
  const boardingPoints = pointsOf(pair?.origin_id);
  const alightingPoints = pointsOf(pair?.destination_id);

  useEffect(() => {
    if (boardingPoints.length === 1) setBoardingPointId(String(boardingPoints[0].id));
    else if (!boardingPoints.some((point) => String(point.id) === boardingPointId)) setBoardingPointId("");
  }, [boardingPoints, boardingPointId]);
  useEffect(() => {
    if (alightingPoints.length === 1) setAlightingPointId(String(alightingPoints[0].id));
    else if (!alightingPoints.some((point) => String(point.id) === alightingPointId)) setAlightingPointId("");
  }, [alightingPoints, alightingPointId]);

  const loadSeats = useCallback(async (id: string) => {
    if (!id) { setSeats([]); return; }
    try { setSeats(await apiList<Seat>(`/seats/?trip=${id}`)); } catch (reason) { setSeats([]); feedback.failure(reason, "Chargement des sièges impossible."); }
  }, [feedback]);
  useEffect(() => { void loadSeats(tripId); }, [tripId, loadSeats]);

  function chooseRoute(label: string) { setRouteLabel(label); setPairKey(""); setTripId(""); setSeat(""); setMethodId(null); }
  function choosePair(key: string) { setPairKey(key); setTripId(""); setSeat(""); setMethodId(null); }

  function clearForm() {
    setSeat(""); setName(""); setPhone(""); setMethodId(null); setSaleKey(null);
    setBoardingPointId(""); setAlightingPointId("");
  }

  async function refreshAfterSale() {
    await Promise.all([loadSeats(tripId), loadOptions(), onChanged()]);
  }

  async function sell(event: FormEvent) {
    event.preventDefault();
    if (busy || !selectedTrip || !pair || !quote) return;
    if (!seat) { feedback.failure(null, "Choisissez un siège libre."); return; }
    if (!name.trim()) { feedback.failure(null, "Saisissez le nom du passager."); return; }
    if (!phone.trim()) { feedback.failure(null, "Saisissez le téléphone du passager."); return; }
    if (boardingPoints.length > 1 && !boardingPointId) { feedback.failure(null, "Choisissez le point d’embarquement."); return; }
    if (alightingPoints.length > 1 && !alightingPointId) { feedback.failure(null, "Choisissez le point de débarquement."); return; }
    const amount = money(quote.total, quote.currency);
    if (!quote.online && !window.confirm(`Espèces reçues ? Confirmez avoir reçu ${amount} du passager.`)) return;
    const key = saleKey ?? newSaleKey();
    setSaleKey(key);
    setBusy(true);
    try {
      const payload = await apiFetch<SaleResult>("/staff/sales/sell/", {
        method: "POST",
        body: JSON.stringify({
          idempotency_key: key,
          trip: selectedTrip.id,
          seat: Number(seat),
          passenger_name: name.trim(),
          passenger_phone: phone.trim(),
          payment_method: quote.payment_method,
          origin: String(pair.origin_id),
          destination: String(pair.destination_id),
          boarding_point_id: boardingPointId ? Number(boardingPointId) : undefined,
          alighting_point_id: alightingPointId ? Number(alightingPointId) : undefined,
        }),
      });
      setResult(payload);
      if (payload.payment_error) feedback.failure(null, `Le paiement n’a pas pu démarrer : ${payload.payment_error}`);
      else if (payload.booking.status === "CONFIRMED") { feedback.success(`Billet ${payload.booking.tickets[0]?.reference ?? ""} émis.`); setWhatsapp(phone.trim()); clearForm(); }
      // Pas d'ouverture automatique : après un appel au serveur, Safari et Chrome mobile la bloquent.
      // L'agent ouvre la page par le bouton « Ouvrir la page de paiement » de la vente en cours.
      else if (payload.checkout?.payment_url) feedback.info("Paiement demandé : cliquez sur « Ouvrir la page de paiement », puis sur « Vérifier le paiement ».");
      await refreshAfterSale();
    } catch (reason) {
      // Refus net du serveur (4xx) : rien n'a été réservé, nouvelle clé. Erreur réseau ou 5xx : la vente a pu
      // passer côté serveur, on garde la même clé pour qu'un nouvel essai la reprenne sans doublon.
      const status = (reason as { status?: number }).status;
      if (status && status >= 400 && status < 500) setSaleKey(null);
      feedback.failure(reason, "La vente n’a pas été enregistrée.");
    } finally { setBusy(false); }
  }

  async function verify() {
    if (busy || !result?.checkout) return;
    setBusy(true);
    try {
      const payload = await apiFetch<SaleResult>(`/staff/sales/${result.booking.id}/verify/`, {
        method: "POST",
        body: JSON.stringify({ payment_method: result.checkout.payment_method, external_reference: result.checkout.transaction_id }),
      });
      setResult({ ...payload, checkout: payload.booking.status === "CONFIRMED" ? null : result.checkout });
      if (payload.booking.status === "CONFIRMED") { feedback.success(`Paiement reçu : billet ${payload.booking.tickets[0]?.reference ?? ""} émis.`); setWhatsapp(phone.trim()); clearForm(); await refreshAfterSale(); }
    } catch (reason) { feedback.failure(reason, "Paiement pas encore reçu. Aucun billet n’est émis tant qu’il n’est pas confirmé."); }
    finally { setBusy(false); }
  }

  async function cancelSale() {
    if (busy || !result) return;
    setBusy(true);
    try {
      await apiFetch(`/staff/sales/${result.booking.id}/cancel/`, { method: "POST", body: "{}" });
      feedback.success("Vente annulée. La place est libérée.");
      setResult(null); clearForm();
      await refreshAfterSale();
    } catch (reason) { feedback.failure(reason, "La vente n’a pas été annulée."); }
    finally { setBusy(false); }
  }

  const booking = result?.booking;
  const issued = booking?.status === "CONFIRMED";
  const pending = booking?.status === "HELD";
  const ticket = booking?.tickets?.[0];

  if (saleTrips === null) return <Loading />;
  return (
    <div className="grid min-w-0 gap-5 lg:grid-cols-2">
      <section className="card min-w-0 lg:col-span-2">
        <SectionHeading eyebrow="À vendre" title="Trajet du passager" />
        {routeLabels.length === 0 ? <EmptyState title="Aucun départ à vendre" text="Créez les départs dans l’onglet « Trajets & planning »." /> : (
          <>
            <div role="tablist" className="mb-4 flex flex-wrap gap-2">
              {routeLabels.map((label) => (
                <button key={label} type="button" role="tab" aria-selected={currentRoute === label} className={currentRoute === label ? "primary-button" : "secondary-button"} onClick={() => chooseRoute(label)}>{label}</button>
              ))}
            </div>
            {pairs.length === 0 ? <EmptyState title="Aucun trajet avec tarif" text="Aucun tronçon de ce sens n’a de prix." /> : (
              <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
                {pairs.map((item) => (
                  <button key={pairOf(item)} type="button" onClick={() => choosePair(pairOf(item))} className={`min-w-0 rounded-[14px] border p-4 text-left ${pairOf(item) === pairKey ? "border-[var(--blue)] bg-[var(--tint)]" : "border-[var(--line)] bg-white"}`}>
                    <span className="block font-bold text-axis-900">{item.origin} → {item.destination}</span>
                    <span className="mt-1 block text-lg font-extrabold">{item.quotes[0] ? money(item.quotes[0].total, item.quotes[0].currency) : "Prix indisponible"}</span>
                  </button>
                ))}
              </div>
            )}
          </>
        )}
      </section>

      <section className="card min-w-0">
        <SectionHeading eyebrow="Vente" title="Vendre un billet" />
        {!pair ? <p className="text-sm text-slate-500">Choisissez d’abord un trajet ci-dessus.</p> : (
          <form onSubmit={sell} className="space-y-4">
            <p className="rounded-[10px] bg-[var(--tint)] p-3 text-sm"><b>{pair.origin} → {pair.destination}</b> · prix du billet : <b>{price}</b></p>
            <label className="block">
              <span className="field-label">Départ</span>
              <select className="field" value={tripId} onChange={(e) => { setTripId(e.target.value); setSeat(""); setMethodId(null); }} required>
                <option value="">Choisir un départ</option>
                {pairTrips.map((trip) => <option key={trip.id} value={trip.id} disabled={trip.available_seats === 0}>{trip.departed ? "Déjà parti · " : ""}{formatDate(trip.departure_at)} · {trip.available_seats} place(s) libre(s)</option>)}
              </select>
            </label>
            {selectedTrip?.departed && <p className="notice notice-error mt-2" role="alert">Ce départ est déjà parti. Vérifiez que le passager monte à un arrêt que le bus n’a pas encore passé.</p>}
            {selectedTrip && (boardingPoints.length > 0 || alightingPoints.length > 0) && (
              <div className="grid gap-3 sm:grid-cols-2">
                {boardingPoints.length > 0 && <Select label={`Embarquement (${pair.origin})`} value={boardingPointId} onChange={setBoardingPointId} options={boardingPoints.map((point) => [String(point.id), point.name])} required={boardingPoints.length > 1} />}
                {alightingPoints.length > 0 && <Select label={`Débarquement (${pair.destination})`} value={alightingPointId} onChange={setAlightingPointId} options={alightingPoints.map((point) => [String(point.id), point.name])} required={alightingPoints.length > 1} />}
              </div>
            )}
            {selectedTrip && (
              <div>
                <span className="field-label">Siège (Libre · Retenu · Occupé)</span>
                {seats.length === 0 ? <p className="text-sm text-slate-500">Chargement des sièges…</p> : (
                  <div className="overflow-x-auto"><BusSeatMap seats={seats} selectedSeatIds={seat ? [Number(seat)] : []} onToggleSeat={(item) => setSeat(String(item.id))} maxSeats={1} /></div>
                )}
              </div>
            )}
            <Input label="Nom du passager" value={name} onChange={setName} />
            <Input label="Téléphone du passager" type="tel" value={phone} onChange={setPhone} />
            {quotes.length > 0 && (
              <div>
                <span className="field-label">Paiement</span>
                <div className="flex flex-wrap gap-2">
                  {quotes.map((item) => (
                    <button key={item.payment_method} type="button" className={methodId === item.payment_method ? "primary-button" : "secondary-button"} onClick={() => setMethodId(item.payment_method)}>{item.label}</button>
                  ))}
                </div>
                {quote && <p className="mt-2 text-xs text-slate-500">{quote.online ? "Une demande de paiement s’ouvre pour le téléphone du passager ; le billet est émis dès la confirmation." : "Encaissez le montant exact avant de valider."}</p>}
              </div>
            )}
            <button className="primary-button w-full" disabled={busy || pending || !selectedTrip || !quote}>
              {busy ? "Patientez…" : quote ? `${quote.online ? "Demander le paiement de" : "Encaisser"} ${money(quote.total, quote.currency)}` : "Choisissez un moyen de paiement"}
            </button>
          </form>
        )}
      </section>

      <section className="card min-w-0">
        <SectionHeading eyebrow="Encaissement" title="Vente en cours" action={booking && <StatusBadge tone={issued ? "green" : pending ? "amber" : "grey"}>{booking.client_status_display || booking.status_display}</StatusBadge>} />
        {!booking ? <EmptyState title="Aucune vente en cours" text="Le billet s’affiche ici après l’encaissement." /> : (
          <div>
            <p className="text-lg font-extrabold text-axis-900">{ticket?.reference ?? booking.reference}</p>
            <p className="text-sm font-semibold text-slate-700">{booking.segment_label}</p>
            <p className="field-label mt-4">Prix du billet</p>
            <p className="price">{money(booking.amount, booking.currency)}</p>
            {pending && result?.checkout && (
              <div className="mt-4 flex flex-wrap gap-2">
                {result.checkout.payment_url && <a className="secondary-button" href={result.checkout.payment_url} target="_blank" rel="noreferrer">Ouvrir la page de paiement</a>}
                <button type="button" className="primary-button" disabled={busy} onClick={() => void verify()}>Vérifier le paiement</button>
              </div>
            )}
            {pending && <button type="button" className="text-button mt-3" disabled={busy} onClick={() => void cancelSale()}>Annuler la vente</button>}
            {issued && ticket && (
              <div className="mt-5 flex flex-wrap gap-2">
                <a className="primary-button" href={`/t/${encodeURIComponent(ticket.reference)}`} target="_blank" rel="noreferrer">Afficher / imprimer le billet</a>
                <button type="button" className="secondary-button" onClick={() => { setResult(null); setWhatsapp(""); }}>Nouvelle vente</button>
              </div>
            )}
            {issued && ticket && (
              <div className="mt-4 rounded-lg border border-slate-200 p-3">
                <label className="block"><span className="field-label">WhatsApp du client (facultatif)</span>
                  <input className="field" inputMode="tel" value={whatsapp} onChange={(e) => setWhatsapp(e.target.value)} placeholder="Format international, ex. : +229 …" />
                </label>
                {whatsapp && !whatsappHref(whatsapp) && <p className="mt-1 text-xs text-amber-700">Numéro au format international (+ et indicatif) pour l’ouvrir directement ; sinon WhatsApp vous laissera choisir le contact.</p>}
                <a className="primary-button mt-2 inline-flex" target="_blank" rel="noopener noreferrer"
                  href={soldTicketWhatsappHref({ reference: ticket.reference, passenger_name: ticket.passenger_name ?? "", passenger_phone: whatsapp }, `${window.location.origin}/t/${encodeURIComponent(ticket.reference)}`)}>
                  Envoyer le billet par WhatsApp
                </a>
              </div>
            )}
          </div>
        )}
      </section>
    </div>
  );
}

// Billets : recherche (référence, nom, téléphone), annulation avec motif, délai de report des billets non scannés.
function TicketsPanel({ settings, onChanged }: { settings: SystemSetting[]; onChanged: () => Promise<void> }) {
  const feedback = useActionFeedback();
  const [query, setQuery] = useState("");
  const [rows, setRows] = useState<Ticket[] | null>(null);
  const [busy, setBusy] = useState(false);
  const report = settings.find((item) => item.key === "ticket_report_days");
  const [days, setDays] = useState(report ? String(report.value) : "");
  useEffect(() => { setDays(report ? String(report.value) : ""); }, [report]);

  async function search(event?: FormEvent) {
    event?.preventDefault();
    const term = query.trim();
    if (!term) return;
    setBusy(true);
    try { setRows(await apiList<Ticket>(`/tickets/?q=${encodeURIComponent(term)}`)); }
    catch (reason) { feedback.failure(reason, "La recherche n’a pas abouti."); }
    finally { setBusy(false); }
  }

  async function cancel(ticket: Ticket) {
    const note = window.prompt(`Annuler le billet ${ticket.reference} (${ticket.passenger_name}) ? La place sera libérée. Indiquez le motif :`)?.trim();
    if (!note) return;
    setBusy(true);
    try {
      await apiFetch(`/tickets/${ticket.id}/transition/`, { method: "POST", body: JSON.stringify({ status: "CANCELLED", note }) });
      feedback.success(`Billet ${ticket.reference} annulé.`);
      await search();
    } catch (reason) { feedback.failure(reason, "Le billet n’a pas été annulé."); }
    finally { setBusy(false); }
  }

  async function saveDays() {
    const value = Number(days);
    if (!days.trim() || !Number.isInteger(value) || value < 0) {
      feedback.failure(null, "Délai de report : saisissez un nombre entier de jours (0 = aucun report).");
      return;
    }
    try {
      await apiFetch(report ? `/settings/${report.id}/` : "/settings/", { method: report ? "PATCH" : "POST", body: JSON.stringify({ key: "ticket_report_days", value, description: "Jours de report d’un billet non scanné" }) });
      feedback.success("Délai de report enregistré.");
      await onChanged();
    } catch (reason) { feedback.failure(reason, "Délai de report : non enregistré."); }
  }

  return (
    <div className="space-y-5">
      <section className="card">
        <SectionHeading eyebrow="Billet non scanné le jour prévu" title="Délai de report" />
        <div className="grid gap-2 sm:grid-cols-[1fr_auto] sm:items-end">
          <label className="block"><span className="field-label">Nombre de jours après le départ prévu</span>
            <input className="field" inputMode="numeric" value={days} onChange={(e) => setDays(e.target.value)} placeholder="À renseigner" />
          </label>
          <button className="primary-button" onClick={() => void saveDays()}>Enregistrer</button>
        </div>
        <p className="mt-2 text-sm text-slate-500">Tant que ce délai n’est pas saisi, un billet ne se scanne que le jour de son départ. Un billet reporté se scanne une seule fois, sur un départ du même parcours.</p>
      </section>
      <section className="card">
        <SectionHeading eyebrow="Référence, nom ou téléphone" title="Rechercher un billet" />
        <form onSubmit={search} className="mb-4 grid gap-2 sm:grid-cols-[1fr_auto]">
          <input className="field" type="search" value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Ex. : AX-…, nom du passager, téléphone" />
          <button className="primary-button" disabled={busy || !query.trim()}>{busy ? "Recherche…" : "Rechercher"}</button>
        </form>
        {rows === null ? null : rows.length === 0 ? <EmptyState title="Aucun billet" text="Aucun billet ne correspond à la recherche." /> : (
          <ul className="space-y-2">
            {rows.map((ticket) => (
              <li key={ticket.id} className="flex flex-wrap items-center gap-2 rounded-lg border border-slate-200 p-3 text-sm">
                <div className="min-w-0 flex-1">
                  <p className="font-semibold">{ticket.reference} · {ticket.passenger_name}</p>
                  <p className="text-slate-500">{ticket.trip_detail ? `${ticket.trip_detail.route_detail.label} · ${formatDate(ticket.trip_detail.departure_at)}` : ""}{ticket.passenger_phone ? ` · ${ticket.passenger_phone}` : ""}</p>
                </div>
                <StatusBadge tone={ticketTone(ticket.status)}>{ticket.status_display}</StatusBadge>
                <a className="secondary-button" href={`/t/${encodeURIComponent(ticket.reference)}`} target="_blank" rel="noreferrer">Voir</a>
                {["HELD", "PAID", "ISSUED"].includes(ticket.status) && <button className="secondary-button" disabled={busy} onClick={() => void cancel(ticket)}>Annuler</button>}
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}

function ParcelPanel({ parcels, trips, onChanged }: { parcels: Parcel[]; trips: Trip[]; onChanged: () => Promise<void> }) {
  const feedback = useActionFeedback();
  const [assignments, setAssignments] = useState<Record<number, string>>({});
  const [proofs, setProofs] = useState<Record<number, string>>({});
  const [query, setQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState("");

  // Départs qui desservent le départ puis la destination du colis, dans le sens du bus, à venir et non annulés.
  function tripsFor(parcel: Parcel) {
    const now = Date.now();
    return trips
      .filter((trip) => {
        if (trip.status === "CANCELLED" || trip.status === "COMPLETED" || new Date(trip.departure_at).getTime() < now - 12 * 3600 * 1000) return false;
        const ids = (trip.route_detail.stops || []).map((stop) => stop.id);
        const from = ids.indexOf(parcel.origin);
        const to = ids.indexOf(parcel.destination);
        return from !== -1 && to !== -1 && from < to;
      })
      .sort((a, b) => a.departure_at.localeCompare(b.departure_at));
  }

  const term = query.trim().toLowerCase();
  const shown = parcels.filter((parcel) =>
    (!statusFilter || parcel.status === statusFilter) &&
    (!term || [parcel.tracking_number, parcel.sender_name, parcel.recipient_name, parcel.origin_detail.name, parcel.destination_detail.name].some((value) => (value || "").toLowerCase().includes(term))),
  );
  const statuses = Array.from(new Map(parcels.map((parcel) => [parcel.status, parcel.status_display])).entries());

  async function cancel(parcel: Parcel) {
    const note = window.prompt(`Annuler le colis ${parcel.tracking_number} ? Indiquez le motif :`)?.trim();
    if (!note) return;
    try {
      await apiFetch(`/parcels/${parcel.id}/transition/`, { method: "POST", body: JSON.stringify({ status: "CANCELLED", note }) });
      feedback.success(`Colis ${parcel.tracking_number} annulé.`);
      await onChanged();
    } catch (reason) { feedback.failure(reason, "Le colis n’a pas été annulé."); }
  }

  async function edit(parcel: Parcel) {
    const recipient_name = window.prompt("Nom du destinataire :", parcel.recipient_name)?.trim();
    if (!recipient_name) return;
    const recipient_phone = window.prompt("Téléphone du destinataire :", parcel.recipient_phone)?.trim();
    if (!recipient_phone) return;
    const description = window.prompt("Description du colis :", parcel.description)?.trim();
    if (description === undefined) return;
    try {
      await apiFetch(`/parcels/${parcel.id}/`, { method: "PATCH", body: JSON.stringify({ recipient_name, recipient_phone, description }) });
      feedback.success(`Colis ${parcel.tracking_number} modifié.`);
      await onChanged();
    } catch (reason) { feedback.failure(reason, "Le colis n’a pas été modifié."); }
  }

  async function advance(parcel: Parcel) {
    const next = nextParcelStatus[parcel.status];
    if (!next) return;
    const body: Record<string, unknown> = { status: next };
    if (next === "ASSIGNED") body.trip = Number(assignments[parcel.id]);
    if (next === "PICKED_UP") body.pickup_recipient_identity = proofs[parcel.id];
    try {
      await apiFetch(`/parcels/${parcel.id}/transition/`, { method: "POST", body: JSON.stringify(body) });
      feedback.success(`Colis ${parcel.tracking_number} : statut mis à jour.`);
      await onChanged();
    } catch (reason) { feedback.failure(reason, "Le statut du colis n’a pas été changé."); }
  }

  return (
    <section className="card">
      <SectionHeading eyebrow="Cycle audité" title="Exploitation des colis" />
      <div className="mb-4 grid gap-3 sm:grid-cols-[1fr_auto]">
        <input className="field" type="search" placeholder="Rechercher : numéro, expéditeur, destinataire, ville" value={query} onChange={(e) => setQuery(e.target.value)} />
        <select className="field" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} aria-label="Filtrer par statut">
          <option value="">Tous les statuts</option>
          {statuses.map(([key, label]) => <option key={key} value={key}>{label}</option>)}
        </select>
      </div>
      {shown.length === 0 ? <EmptyState title="Aucun colis" text={parcels.length ? "Aucun colis ne correspond à la recherche." : "Les colis en ligne et au guichet apparaîtront dans la même liste."} /> : (
        <div className="table-scroll">
          <table className="staff-table min-w-[820px]">
            <thead><tr><th>Référence</th><th>Photos</th><th>Trajet</th><th>Destinataire</th><th>Statut</th><th>Étape suivante</th></tr></thead>
            <tbody>
              {shown.map((parcel) => (
                <tr key={parcel.id}>
                  <td className="strong">{parcel.tracking_number}</td>
                  <td>
                    <span className="flex gap-1">
                      {(parcel.photo_urls || []).map((url) => <a key={url} href={url} target="_blank" rel="noreferrer"><img src={url} alt={`Colis ${parcel.tracking_number}`} className="h-10 w-10 rounded object-cover" /></a>)}
                      {(parcel.photo_urls || []).length === 0 && "—"}
                    </span>
                  </td>
                  <td>{parcel.origin_detail.name} → {parcel.destination_detail.name}</td>
                  <td>{parcel.recipient_name}</td>
                  <td><StatusBadge tone={parcel.status === "PICKED_UP" ? "green" : parcel.status === "CANCELLED" ? "grey" : "blue"}>{parcel.status_display}</StatusBadge></td>
                  <td>
                    <span className="flex flex-wrap items-center gap-2">
                      {nextParcelStatus[parcel.status] === "ASSIGNED" && (
                        <select className="field max-w-56" value={assignments[parcel.id] || ""} onChange={(e) => setAssignments({ ...assignments, [parcel.id]: e.target.value })}>
                          <option value="">Affecter un trajet</option>
                          {tripsFor(parcel).map((trip) => <option key={trip.id} value={trip.id}>{formatDate(trip.departure_at)} · {trip.route_detail.label}</option>)}
                        </select>
                      )}
                      {nextParcelStatus[parcel.status] === "PICKED_UP" && <input className="field max-w-56" placeholder="Identité / code de retrait" value={proofs[parcel.id] || ""} onChange={(e) => setProofs({ ...proofs, [parcel.id]: e.target.value })} />}
                      {nextParcelStatus[parcel.status] && <button className="secondary-button" onClick={() => void advance(parcel)}>Valider</button>}
                      {!["PICKED_UP", "CANCELLED"].includes(parcel.status) && <button className="secondary-button" onClick={() => void edit(parcel)}>Modifier</button>}
                      {["REGISTERED", "DEPOSITED", "ACCEPTED", "ASSIGNED"].includes(parcel.status) && <button className="secondary-button" onClick={() => void cancel(parcel)}>Annuler</button>}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

// Locations : l'admin confirme, démarre, termine ou annule une demande et saisit montant et caution (journalisés).
const rentalNext: Record<string, Array<[string, string]>> = {
  REQUESTED: [["CONFIRMED", "Confirmer"], ["CANCELLED", "Annuler"]],
  CONFIRMED: [["ACTIVE", "Démarrer"], ["CANCELLED", "Annuler"]],
  ACTIVE: [["COMPLETED", "Terminer"]],
};

function RentalPanel() {
  const feedback = useActionFeedback();
  const [rentals, setRentals] = useState<RentalBooking[] | null>(null);
  const [log, setLog] = useState<Array<{ id: number; created_at: string; detail: string; actor_name: string }>>([]);
  const [amounts, setAmounts] = useState<Record<number, { total: string; deposit: string }>>({});
  const [busy, setBusy] = useState<number | null>(null);
  const [notice, setNotice] = useState<NoticeState>(null);

  const load = useCallback(async () => {
    try {
      const [rows, changes] = await Promise.all([apiList<RentalBooking>("/rentals/"), apiFetch<typeof log>("/rentals/changes/")]);
      setRentals(rows);
      setLog(changes);
      setAmounts(Object.fromEntries(rows.map((r) => [r.id, { total: r.total_amount ? String(Math.round(Number(r.total_amount))) : "", deposit: r.deposit_amount ? String(Math.round(Number(r.deposit_amount))) : "" }])));
    } catch (reason) { setNotice(failure(reason, "Les locations n’ont pas pu être chargées. Réessayez.")); }
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function manage(rental: RentalBooking, body: Record<string, unknown>, success: string) {
    setBusy(rental.id);
    try {
      await apiFetch(`/rentals/${rental.id}/manage/`, { method: "POST", body: JSON.stringify(body) });
      feedback.success(success);
      await load();
    } catch (reason) { feedback.failure(reason, "La location n’a pas été modifiée."); }
    finally { setBusy(null); }
  }

  function changeStatus(rental: RentalBooking, status: string, label: string) {
    let note = "";
    if (status === "CANCELLED") {
      note = window.prompt(`Annuler la location ${rental.reference} ? Indiquez le motif :`)?.trim() || "";
      if (!note) return;
    } else if (!window.confirm(`${label} la location ${rental.reference} ?`)) return;
    void manage(rental, { status, note }, `Location ${rental.reference} : ${label.toLowerCase()} — enregistré.`);
  }

  function saveAmounts(rental: RentalBooking) {
    const draft = amounts[rental.id] || { total: "", deposit: "" };
    const body: Record<string, unknown> = {};
    for (const [key, value] of [["total_amount", draft.total], ["deposit_amount", draft.deposit]] as const) {
      const typed = value.replace(/[\s\u202f\u00a0]/g, "");
      if (!typed) continue;
      if (!/^\d+$/.test(typed) || Number(typed) <= 0) { feedback.failure(null, "Montants : nombres entiers de francs CFA, supérieurs à zéro."); return; }
      body[key] = Number(typed);
    }
    if (Object.keys(body).length === 0) return;
    void manage(rental, body, `Montants de ${rental.reference} enregistrés.`);
  }

  return (
    <div className="space-y-5">
      <section className="card">
        <SectionHeading eyebrow="Demandes des clients" title="Locations" />
        {rentals === null ? <Loading /> : rentals.length === 0 ? <EmptyState title="Aucune location" text="Les demandes de location des clients apparaîtront ici." /> : (
          <ul className="space-y-3">
            {rentals.map((rental) => {
              const draft = amounts[rental.id] || { total: "", deposit: "" };
              const open = !["COMPLETED", "CANCELLED"].includes(rental.status);
              return (
                <li key={rental.id} className="rounded-lg border border-slate-200 p-3 text-sm">
                  <div className="flex flex-wrap items-center gap-2">
                    <p className="min-w-0 flex-1 font-semibold">{rental.reference} · {rental.vehicle_detail?.name}</p>
                    <StatusBadge tone={rental.status === "CANCELLED" ? "grey" : rental.status === "COMPLETED" ? "green" : "blue"}>{rental.status_display}</StatusBadge>
                  </div>
                  <p className="mt-1 text-slate-500">
                    Du {formatDate(rental.starts_at)} au {formatDate(rental.ends_at)}{rental.with_driver ? " · avec chauffeur" : ""}
                    {rental.customer_detail ? ` · ${[rental.customer_detail.first_name, rental.customer_detail.last_name].filter(Boolean).join(" ") || rental.customer_detail.username}${rental.customer_detail.phone ? ` · ${rental.customer_detail.phone}` : ""}` : ""}
                  </p>
                  {open && (
                    <div className="mt-2 grid gap-2 sm:grid-cols-[1fr_1fr_auto] sm:items-end">
                      <label className="block"><span className="field-label">Montant (FCFA)</span><input className="field" inputMode="numeric" value={draft.total} placeholder="À renseigner" onChange={(e) => setAmounts({ ...amounts, [rental.id]: { ...draft, total: e.target.value } })} /></label>
                      <label className="block"><span className="field-label">Caution (FCFA)</span><input className="field" inputMode="numeric" value={draft.deposit} placeholder="À renseigner" onChange={(e) => setAmounts({ ...amounts, [rental.id]: { ...draft, deposit: e.target.value } })} /></label>
                      <button className="secondary-button" disabled={busy !== null} onClick={() => saveAmounts(rental)}>Enregistrer</button>
                    </div>
                  )}
                  {!open && <p className="mt-1">Montant : {rental.total_amount ? money(rental.total_amount) : "—"} · Caution : {rental.deposit_amount ? money(rental.deposit_amount) : "—"}</p>}
                  <div className="mt-2 flex flex-wrap gap-2">
                    {(rentalNext[rental.status] || []).map(([status, label]) => (
                      <button key={status} className={status === "CANCELLED" ? "secondary-button" : "primary-button"} disabled={busy !== null} onClick={() => changeStatus(rental, status, label)}>{label}</button>
                    ))}
                  </div>
                </li>
              );
            })}
          </ul>
        )}
        <Notice notice={notice} />
      </section>
      <section className="card">
        <SectionHeading eyebrow="Lecture seule" title="Historique des locations" />
        {log.length === 0 ? <EmptyState title="Aucune modification" text="Chaque changement apparaîtra ici." /> : (
          <ul className="space-y-2 text-sm">
            {log.map((row) => <li key={row.id}><span className="text-slate-500">{formatDate(row.created_at)} · {row.actor_name}</span><br />{row.detail}</li>)}
          </ul>
        )}
      </section>
    </div>
  );
}

function FleetPanel({ locations, vehicles, onChanged }: { locations: Location[]; vehicles: Vehicle[]; onChanged: () => Promise<void> }) {
  const feedback = useActionFeedback();
  const emptyVehicle = { category: "BUS", name: "", registration_number: "", capacity: "", base_location: "", state: "ACTIVE", seat_configuration: "", ...emptyRentalFields };
  const [showArchived, setShowArchived] = useState(false);
  const [form, setForm] = useState(emptyVehicle);
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    try {
      const seatConfiguration = form.seat_configuration.trim() ? JSON.parse(form.seat_configuration) : [];
      await apiFetch("/vehicles/", { method: "POST", body: JSON.stringify({ ...form, ...rentalPayload(form), seat_configuration: seatConfiguration, capacity: form.capacity ? Number(form.capacity) : null, base_location: form.base_location ? Number(form.base_location) : null, registration_number: form.registration_number || null }) });
      feedback.success("Véhicule ajouté.");
      setForm(emptyVehicle);
      await onChanged();
    } catch (reason) { feedback.failure(reason, "Le véhicule n’a pas été ajouté (vérifiez notamment le plan de sièges)."); }
    finally { setBusy(false); }
  }

  return (
    <div className="grid gap-5 xl:grid-cols-[1.35fr_.65fr]">
      <section className="grid content-start gap-4 md:grid-cols-2">
        <label className="flex items-center gap-2 text-sm md:col-span-2"><input type="checkbox" checked={showArchived} onChange={(e) => setShowArchived(e.target.checked)} />Afficher les véhicules archivés</label>
        {vehicles.filter((vehicle) => showArchived || !vehicle.archived).map((vehicle) => <VehicleEditor key={vehicle.id} vehicle={vehicle} locations={locations} onChanged={onChanged} />)}
      </section>
      <section className="card self-start">
        <SectionHeading eyebrow="Flotte extensible" title="Ajouter un véhicule" />
        <form onSubmit={submit} className="space-y-4">
          <Select label="Catégorie" value={form.category} onChange={(value) => setForm({ ...form, category: value })} options={[["BUS", "Bus"], ["RENTAL", "Location"]]} />
          <Input label="Nom / modèle" value={form.name} onChange={(value) => setForm({ ...form, name: value })} />
          <Input label="Immatriculation" value={form.registration_number} onChange={(value) => setForm({ ...form, registration_number: value })} required={false} />
          <Input label="Capacité" type="number" value={form.capacity} onChange={(value) => setForm({ ...form, capacity: value })} required={false} />
          <Select label="Agence de base" value={form.base_location} onChange={(value) => setForm({ ...form, base_location: value })} options={locations.map((l) => [String(l.id), l.name])} required={false} />
          {form.category === "BUS" && (
            <label className="block">
              <span className="field-label">Plan de sièges JSON (optionnel)</span>
              <textarea className="field min-h-24" placeholder={'[{"label":"1A","row":1,"column":1}]'} value={form.seat_configuration} onChange={(e) => setForm({ ...form, seat_configuration: e.target.value })} />
            </label>
          )}
          {form.category === "RENTAL" && <RentalFields form={form} onChange={(patch) => setForm({ ...form, ...patch })} />}
          {form.category === "RENTAL" && <p className="text-sm text-slate-500">La photo s’ajoute ensuite, sur la fiche du véhicule.</p>}
          <button className="primary-button w-full" disabled={busy}>{busy ? "Ajout…" : "Ajouter"}</button>
        </form>
      </section>
    </div>
  );
}

// Champs propres à la location : partagés par l'ajout et la modification d'un véhicule.
const emptyRentalFields = { rental_daily_rate: "", rental_daily_rate_with_driver: "", driver_available: false, driver_required: false, brand: "", model_name: "", transmission: "", fuel: "" };
type RentalForm = typeof emptyRentalFields;

function rentalFieldsOf(v: Vehicle): RentalForm {
  return {
    rental_daily_rate: v.rental_daily_rate || "", rental_daily_rate_with_driver: v.rental_daily_rate_with_driver || "",
    driver_available: v.driver_available, driver_required: Boolean(v.driver_required), brand: v.brand || "", model_name: v.model_name || "",
    transmission: v.transmission || "", fuel: v.fuel || "",
  };
}

function rentalPayload(form: RentalForm) {
  return {
    rental_daily_rate: form.rental_daily_rate || null, rental_daily_rate_with_driver: form.rental_daily_rate_with_driver || null,
    driver_available: form.driver_available || form.driver_required, driver_required: form.driver_required,
    brand: form.brand, model_name: form.model_name, transmission: form.transmission, fuel: form.fuel,
  };
}

function RentalFields({ form, onChange }: { form: RentalForm; onChange: (patch: Partial<RentalForm>) => void }) {
  return (
    <div className="space-y-3">
      <div className="grid gap-3 sm:grid-cols-2">
        <Input label="Marque" value={form.brand} onChange={(value) => onChange({ brand: value })} required={false} />
        <Input label="Modèle" value={form.model_name} onChange={(value) => onChange({ model_name: value })} required={false} />
        <Select label="Boîte" value={form.transmission} onChange={(value) => onChange({ transmission: value })} options={[["MANUAL", "Manuelle"], ["AUTOMATIC", "Automatique"]]} required={false} />
        <Select label="Carburant" value={form.fuel} onChange={(value) => onChange({ fuel: value })} options={[["PETROL", "Essence"], ["DIESEL", "Diesel"], ["HYBRID", "Hybride"], ["ELECTRIC", "Électrique"]]} required={false} />
      </div>
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={form.driver_required} onChange={(e) => onChange({ driver_required: e.target.checked, driver_available: e.target.checked || form.driver_available })} />Avec chauffeur uniquement</label>
      {!form.driver_required && <Input label="Tarif journalier sans chauffeur (FCFA)" type="number" value={form.rental_daily_rate} onChange={(value) => onChange({ rental_daily_rate: value })} required={false} />}
      {!form.driver_required && <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={form.driver_available} onChange={(e) => onChange({ driver_available: e.target.checked })} />Chauffeur disponible en option</label>}
      {(form.driver_available || form.driver_required) && <Input label="Tarif journalier avec chauffeur (FCFA)" type="number" value={form.rental_daily_rate_with_driver} onChange={(value) => onChange({ rental_daily_rate_with_driver: value })} required={false} />}
    </div>
  );
}

// Photo du véhicule, ou image de secours (pictogramme) si elle manque.
function VehiclePhoto({ vehicle }: { vehicle: Vehicle }) {
  return vehicle.photo_url
    ? <img src={vehicle.photo_url} alt={vehicle.name} className="mb-4 h-40 w-full rounded-lg object-cover" />
    : <div className="mb-4 flex h-40 w-full items-center justify-center rounded-lg bg-slate-100 text-slate-400" aria-label="Pas de photo">Pas de photo</div>;
}

function VehicleEditor({ vehicle, locations, onChanged }: { vehicle: Vehicle; locations: Location[]; onChanged: () => Promise<void> }) {
  const feedback = useActionFeedback();
  const [editing, setEditing] = useState(false);
  const formOf = (v: Vehicle) => ({ registration_number: v.registration_number || "", capacity: v.capacity ? String(v.capacity) : "", base_location: v.base_location ? String(v.base_location) : "", state: v.state, seat_configuration: JSON.stringify(v.seat_configuration || [], null, 2), ...rentalFieldsOf(v) });
  const [form, setForm] = useState(formOf(vehicle));
  const [uploading, setUploading] = useState(false);

  useEffect(() => { setForm(formOf(vehicle)); }, [vehicle]);

  async function uploadPhoto(file: File | undefined) {
    if (!file) return;
    if (file.size > 5 * 1024 * 1024) { feedback.failure(null, "Photo trop lourde (5 Mo maximum)."); return; }
    const body = new FormData();
    body.append("photo", file);
    setUploading(true);
    try {
      await apiFetch(`/vehicles/${vehicle.id}/photo/`, { method: "POST", body });
      feedback.success(`Photo de ${vehicle.name} enregistrée.`);
      await onChanged();
    } catch (reason) { feedback.failure(reason, "La photo n’a pas été enregistrée (JPG, PNG ou WebP, 5 Mo maximum)."); }
    finally { setUploading(false); }
  }

  async function toggleArchive() {
    const archive = !vehicle.archived;
    if (!window.confirm(archive ? `Archiver ${vehicle.name} ? Il disparaîtra du site et de l’application, son historique est gardé.` : `Remettre ${vehicle.name} dans la liste ?`)) return;
    try {
      await apiFetch(`/vehicles/${vehicle.id}/`, { method: "PATCH", body: JSON.stringify({ archived: archive }) });
      feedback.success(archive ? `${vehicle.name} archivé.` : `${vehicle.name} remis dans la liste.`);
      await onChanged();
    } catch (reason) { feedback.failure(reason, "Le véhicule n’a pas été modifié."); }
  }

  async function save() {
    try {
      await apiFetch(`/vehicles/${vehicle.id}/`, { method: "PATCH", body: JSON.stringify({ registration_number: form.registration_number || null, capacity: form.capacity ? Number(form.capacity) : null, base_location: form.base_location ? Number(form.base_location) : null, state: form.state, seat_configuration: form.seat_configuration.trim() ? JSON.parse(form.seat_configuration) : [], ...(vehicle.category === "RENTAL" ? rentalPayload(form) : {}) }) });
      setEditing(false);
      feedback.success(`Véhicule ${vehicle.name} enregistré.`);
      await onChanged();
    } catch (reason) { feedback.failure(reason, `Le véhicule ${vehicle.name} n’a pas été enregistré (vérifiez notamment le plan de sièges).`); }
  }

  async function syncSeats() {
    try {
      const result = await apiFetch<{ synced_trips: number }>(`/vehicles/${vehicle.id}/sync-future-seats/`, { method: "POST" });
      feedback.success(`${result.synced_trips} trajet(s) futur(s) sans billet synchronisé(s).`);
      await onChanged();
    } catch (reason) { feedback.failure(reason, "Les places n’ont pas été synchronisées."); }
  }

  return (
    <article className={`card ${vehicle.archived ? "opacity-60" : ""}`}>
      {vehicle.category === "RENTAL" && <VehiclePhoto vehicle={vehicle} />}
      <div className="flex justify-between gap-3">
        <div>
          <p className="eyebrow">{vehicle.category_display}{vehicle.archived ? " · Archivé" : ""}</p>
          <h3 className="mt-1 text-lg font-bold text-axis-900">{vehicle.name}</h3>
        </div>
        <span><StatusBadge tone={vehicle.state === "ACTIVE" ? "green" : "amber"}>{vehicle.state_display}</StatusBadge></span>
      </div>
      {editing ? (
        <div className="mt-5 space-y-3">
          <Input label="Immatriculation" value={form.registration_number} onChange={(value) => setForm({ ...form, registration_number: value })} required={false} />
          <Input label="Capacité" type="number" value={form.capacity} onChange={(value) => setForm({ ...form, capacity: value })} required={false} />
          <Select label="Agence de base" value={form.base_location} onChange={(value) => setForm({ ...form, base_location: value })} options={locations.map((l) => [String(l.id), l.name])} required={false} />
          <Select label="État" value={form.state} onChange={(value) => setForm({ ...form, state: value as Vehicle["state"] })} options={[["ACTIVE", "Actif"], ["MAINTENANCE", "Maintenance"], ["UNAVAILABLE", "Indisponible"]]} />
          {vehicle.category === "BUS" && (
            <label className="block">
              <span className="field-label">Plan de sièges JSON</span>
              <textarea className="field min-h-28 font-mono text-xs" value={form.seat_configuration} onChange={(e) => setForm({ ...form, seat_configuration: e.target.value })} />
            </label>
          )}
          {vehicle.category === "RENTAL" && <RentalFields form={form} onChange={(patch) => setForm({ ...form, ...patch })} />}
          <div className="flex gap-2">
            <button className="primary-button flex-1" onClick={() => void save()}>Enregistrer</button>
            <button className="secondary-button" onClick={() => setEditing(false)}>Annuler</button>
          </div>
        </div>
      ) : (
        <>
          <dl className="mt-5 grid grid-cols-2 gap-3 text-sm">
            <div><dt className="field-label">Immatriculation</dt><dd>{vehicle.registration_number || "À renseigner"}</dd></div>
            <div><dt className="field-label">Capacité</dt><dd>{vehicle.capacity ?? "À confirmer"}</dd></div>
            <div><dt className="field-label">Base</dt><dd>{vehicle.base_location_detail?.name || "À renseigner"}</dd></div>
            <div><dt className="field-label">Tarif location</dt><dd>{vehicle.category === "RENTAL" ? (vehicle.driver_required ? "Avec chauffeur uniquement" : vehicle.rental_daily_rate ? money(vehicle.rental_daily_rate) : "À renseigner") : "—"}</dd></div>
            {vehicle.category === "RENTAL" && <div><dt className="field-label">Avec chauffeur</dt><dd>{vehicle.rental_daily_rate_with_driver ? money(vehicle.rental_daily_rate_with_driver) : "Non proposé"}</dd></div>}
            {vehicle.category === "RENTAL" && (vehicle.brand || vehicle.model_name) && <div><dt className="field-label">Marque / modèle</dt><dd>{[vehicle.brand, vehicle.model_name].filter(Boolean).join(" ")}</dd></div>}
            {vehicle.category === "RENTAL" && (vehicle.transmission_display || vehicle.fuel_display) && <div><dt className="field-label">Boîte / carburant</dt><dd>{[vehicle.transmission_display, vehicle.fuel_display].filter(Boolean).join(" · ")}</dd></div>}
          </dl>
          <div className="mt-5 grid gap-3">
            <button className="secondary-button w-full" onClick={() => setEditing(true)}>Configurer</button>
            {vehicle.category === "RENTAL" && (
              <label className="secondary-button w-full cursor-pointer text-center">
                {uploading ? "Envoi de la photo…" : vehicle.photo_url ? "Changer la photo" : "Ajouter une photo"}
                <input type="file" accept="image/jpeg,image/png,image/webp" className="sr-only" disabled={uploading} onChange={(e) => { void uploadPhoto(e.target.files?.[0]); e.target.value = ""; }} />
              </label>
            )}
            {vehicle.category === "RENTAL" && <button className="text-button" onClick={() => void toggleArchive()}>{vehicle.archived ? "Remettre dans la liste" : "Archiver"}</button>}
            {vehicle.category === "BUS" && vehicle.capacity && <button className="text-button" onClick={() => void syncSeats()}>Synchroniser les sièges des trajets futurs</button>}
          </div>
        </>
      )}
    </article>
  );
}

function PricingPanel({ routes, fares, flags, payments, settings, onChanged }: { routes: Route[]; fares: FareRule[]; flags: FeatureFlag[]; payments: PaymentMethod[]; settings: SystemSetting[]; onChanged: () => Promise<void> }) {
  const feedback = useActionFeedback();
  const [fare, setFare] = useState({ route: "", name: "", rule_type: "STANDARD", amount: "", advance_days: "" });
  const [setting, setSetting] = useState("");
  const [boardingLead, setBoardingLead] = useState("");
  const [method, setMethod] = useState("");
  const [policies, setPolicies] = useState<Record<string, string>>({});

  useEffect(() => {
    setPolicies(Object.fromEntries(settings.map((item) => [item.key, typeof item.value === "string" ? item.value : JSON.stringify(item.value)])));
    const hold = settings.find((item) => item.key === "ticket_hold_minutes");
    if (hold) setSetting(String(hold.value));
    const lead = settings.find((item) => item.key === "boarding_lead_minutes");
    if (lead) setBoardingLead(String(lead.value));
  }, [settings]);

  async function addFare(event: FormEvent) {
    event.preventDefault();
    try {
      await apiFetch("/fare-rules/", { method: "POST", body: JSON.stringify({ ...fare, route: Number(fare.route), amount: fare.amount, advance_days: fare.advance_days ? Number(fare.advance_days) : null, currency: "XOF", active: true }) });
      feedback.success("Règle tarifaire enregistrée.");
      setFare({ route: "", name: "", rule_type: "STANDARD", amount: "", advance_days: "" });
      await onChanged();
    } catch (reason) { feedback.failure(reason, "La règle tarifaire n’a pas été enregistrée."); }
  }

  async function toggle(flag: FeatureFlag) {
    try {
      await apiFetch(`/feature-flags/${flag.id}/`, { method: "PATCH", body: JSON.stringify({ enabled: !flag.enabled }) });
      feedback.success(`« ${flag.label} » ${flag.enabled ? "désactivée" : "activée"}.`);
      await onChanged();
    } catch (reason) { feedback.failure(reason, `« ${flag.label} » n’a pas été modifiée.`); }
  }

  // `label` : nom affiché à l'administrateur dans le message de retour.
  async function saveSetting(key: string, value: unknown, description: string, label: string = description) {
    try {
      const current = settings.find((item) => item.key === key);
      await apiFetch(current ? `/settings/${current.id}/` : "/settings/", { method: current ? "PATCH" : "POST", body: JSON.stringify({ key, value, description }) });
      feedback.success(`${label} : enregistré.`);
      await onChanged();
    } catch (reason) { feedback.failure(reason, `${label} : non enregistré.`); }
  }

  async function saveHold() {
    const minutes = Number(setting);
    if (!setting.trim() || !Number.isInteger(minutes) || minutes <= 0) {
      feedback.failure(null, "Blocage d’un siège : non enregistré. Saisissez un nombre entier de minutes, supérieur à zéro.");
      return;
    }
    await saveSetting("ticket_hold_minutes", minutes, "Délai administrable de réservation temporaire", "Blocage d’un siège");
  }

  async function saveBoardingLead() {
    const minutes = Number(boardingLead);
    if (!boardingLead.trim() || !Number.isInteger(minutes) || minutes < 0) {
      feedback.failure(null, "Avance sur l’heure de départ : non enregistrée. Saisissez un nombre entier de minutes.");
      return;
    }
    await saveSetting("boarding_lead_minutes", minutes, "Minutes entre l'embarquement et le départ", "Avance sur l’heure de départ");
  }

  const [methodDrafts, setMethodDrafts] = useState<Record<number, { label: string; active: boolean }>>({});
  async function saveMethod(item: PaymentMethod) {
    const draft = methodDrafts[item.id];
    if (!draft) { feedback.info(`« ${item.label} » : rien à enregistrer.`); return; }
    if (!draft.active && item.active && !window.confirm(`Désactiver « ${item.label} » ? Il ne sera plus proposé aux clients ni au personnel.`)) return;
    try {
      await apiFetch(`/payment-methods/${item.id}/`, { method: "PATCH", body: JSON.stringify({ label: draft.label.trim(), active: draft.active }) });
      feedback.success(`Moyen de paiement « ${draft.label.trim()} » enregistré.`);
      const next = { ...methodDrafts }; delete next[item.id]; setMethodDrafts(next);
      await onChanged();
    } catch (reason) { feedback.failure(reason, `« ${item.label} » n’a pas été modifié.`); }
  }

  async function addMethod() {
    const label = method.trim();
    if (!label) { feedback.failure(null, "Moyen de paiement : non ajouté. Saisissez son libellé."); return; }
    if (!window.confirm(`Ajouter « ${label} » ? Il sera proposé tout de suite aux clients et au personnel.`)) return;
    try {
      await apiFetch("/payment-methods/", { method: "POST", body: JSON.stringify({ code: label.toLowerCase().replace(/[^a-z0-9]+/g, "-"), label, active: true }) });
      feedback.success(`Moyen de paiement « ${label} » ajouté et actif.`);
      setMethod("");
      await onChanged();
    } catch (reason) { feedback.failure(reason, `Le moyen de paiement « ${label} » n’a pas été ajouté.`); }
  }

  const openPolicies = [["contact_phone", "Téléphone de contact (affiché aux clients)"], ["contact_whatsapp", "Numéro WhatsApp (affiché aux clients, format international)"], ["ticket_cancellation_policy", "Annulation et report"], ["baggage_policy", "Bagages et suppléments"], ["parcel_pricing_policy", "Tarification des colis"], ["rental_conditions", "Caution et conditions de location"]];

  return (
    <div className="space-y-5">
      <section className="grid gap-5 xl:grid-cols-[1.2fr_.8fr]">
        <div className="card">
          <SectionHeading eyebrow="Aucune valeur en dur" title="Grille tarifaire" />
          {fares.length ? (
            <div className="table-scroll">
              <table className="staff-table min-w-[560px]">
                <thead><tr><th>Parcours</th><th>Règle</th><th>Montant</th><th>État</th></tr></thead>
                <tbody>
                  {fares.map((item) => (
                    <tr key={item.id}>
                      <td>{item.route_detail.label}</td>
                      <td>{item.name}</td>
                      <td className="strong">{money(item.amount, item.currency)}</td>
                      <td><StatusBadge tone={item.active ? "green" : "red"}>{item.active ? "Actif" : "Inactif"}</StatusBadge></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : <EmptyState title="Aucune règle par parcours" text="Normal : le prix d’un billet vient uniquement de l’onglet « Tarifs par tronçon ». Les règles ajoutées ici ne changent pas le prix de vente." />}
        </div>
        <form onSubmit={addFare} className="card space-y-4">
          <SectionHeading eyebrow="Paramètre commercial" title="Ajouter un tarif" />
          <p className="text-sm text-slate-500">Ce tarif ne change pas le prix de vente d’un billet : ce prix vient uniquement de l’onglet « Tarifs par tronçon ».</p>
          <Select label="Parcours" value={fare.route} onChange={(value) => setFare({ ...fare, route: value })} options={routes.map((r) => [String(r.id), r.label])} />
          <Input label="Nom" value={fare.name} onChange={(value) => setFare({ ...fare, name: value })} />
          <Select label="Type" value={fare.rule_type} onChange={(value) => setFare({ ...fare, rule_type: value })} options={[["STANDARD", "Standard"], ["ADVANCE", "Anticipé"], ["SAME_DAY", "Jour du départ"], ["PROMOTION", "Promotion"]]} />
          <Input label="Montant FCFA" type="number" value={fare.amount} onChange={(value) => setFare({ ...fare, amount: value })} />
          {fare.rule_type === "ADVANCE" && <Input label="Délai en jours" type="number" value={fare.advance_days} onChange={(value) => setFare({ ...fare, advance_days: value })} />}
          <button className="primary-button w-full">Enregistrer</button>
        </form>
      </section>
      <section className="grid gap-5 lg:grid-cols-2">
        <div className="card">
          <SectionHeading eyebrow="Désactivées par défaut" title="Fonctions à valider" />
          <div className="space-y-2">
            {flags.map((flag) => (
              <button key={flag.id} onClick={() => void toggle(flag)} role="switch" aria-checked={flag.enabled} className="flex w-full items-center justify-between gap-3 rounded-[10px] border border-[var(--line)] p-3 text-left">
                <span className="text-sm font-semibold">{flag.label}</span>
                <span className={`h-6 w-11 shrink-0 rounded-full p-1 transition ${flag.enabled ? "bg-[var(--blue)]" : "bg-slate-200"}`}>
                  <span className={`block h-4 w-4 rounded-full bg-white transition ${flag.enabled ? "translate-x-5" : ""}`} />
                </span>
              </button>
            ))}
          </div>
        </div>
        <div className="space-y-5">
          <div className="card">
            <SectionHeading eyebrow="Expiration" title="Blocage d’un siège" />
            {!holdMinutesConfigured(settings) && <p className="mb-3 text-sm font-semibold text-red-700">À saisir : sans cette durée, ni les clients ni le guichet ne peuvent réserver.</p>}
            <div className="flex gap-2">
              <input className="field" type="number" min="1" placeholder="Durée en minutes" value={setting} onChange={(e) => setSetting(e.target.value)} />
              <button onClick={() => void saveHold()} className="primary-button">Enregistrer</button>
            </div>
          </div>
          <div className="card">
            <SectionHeading eyebrow="Embarquement" title="Avance sur l’heure de départ" />
            <div className="flex gap-2">
              <input className="field" type="number" min="0" placeholder="Durée en minutes" value={boardingLead} onChange={(e) => setBoardingLead(e.target.value)} />
              <button onClick={() => void saveBoardingLead()} className="primary-button">Enregistrer</button>
            </div>
          </div>
          <div className="card">
            <SectionHeading eyebrow="Canaux administrables" title="Moyens de paiement" />
            <p className="mb-3 text-xs text-slate-500">Le libellé est ce que voient clients et personnel (ex. « Mobile Money », « Espèces »). Le code ne se modifie pas.</p>
            <div className="mb-4 space-y-2">
              {payments.map((p) => {
                const draft = methodDrafts[p.id] ?? { label: p.label, active: p.active };
                return (
                  <div key={p.id} className="flex flex-wrap items-center gap-2">
                    <input className="field min-w-0 flex-1" aria-label={`Libellé ${p.code}`} value={draft.label} onChange={(e) => setMethodDrafts({ ...methodDrafts, [p.id]: { ...draft, label: e.target.value } })} />
                    <label className="flex items-center gap-1 text-sm"><input type="checkbox" checked={draft.active} onChange={(e) => setMethodDrafts({ ...methodDrafts, [p.id]: { ...draft, active: e.target.checked } })} />Actif</label>
                    <span className="text-xs text-slate-400">{p.code}</span>
                    <button type="button" className="secondary-button" onClick={() => void saveMethod(p)}>Enregistrer</button>
                  </div>
                );
              })}
            </div>
            <div className="flex gap-2">
              <input className="field" placeholder="Ex. Espèces au guichet" value={method} onChange={(e) => setMethod(e.target.value)} />
              <button onClick={() => void addMethod()} className="primary-button">Ajouter</button>
            </div>
          </div>
        </div>
      </section>
      <section className="card">
        <SectionHeading eyebrow="À valider avant activation" title="Politiques commerciales ouvertes" />
        <div className="grid gap-4 md:grid-cols-2">
          {openPolicies.map(([key, label]) => (
            <div key={key}>
              <label className="field-label" htmlFor={`policy-${key}`}>{label}</label>
              <textarea id={`policy-${key}`} className="field min-h-24" placeholder="Non configuré" value={policies[key] || ""} onChange={(e) => setPolicies({ ...policies, [key]: e.target.value })} />
              <button className="text-button mt-2" onClick={() => void saveSetting(key, policies[key] || "", label, label)}>Enregistrer cette règle</button>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}

const agencyFields: Array<[keyof AgencyProfile, string]> = [
  ["legal_name", "Raison sociale"], ["ifu", "IFU"], ["rccm", "RCCM"], ["capital", "Capital"], ["address", "Adresse"],
  ["phones", "Téléphones"], ["email", "E-mail"], ["bank_accounts", "Comptes bancaires (jamais imprimés)"],
];

function describeChange(value: Record<string, unknown> | null) {
  if (!value) return "—";
  const labels = Object.fromEntries(agencyFields) as Record<string, string>;
  return Object.entries(value).map(([key, item]) => `${labels[key] ?? key} : ${item === "" || item === null ? "À renseigner" : String(item)}`).join(" · ");
}

// Informations légales de l'agence (imprimées en bas du billet) et taxes comprises dans le prix. Rien n'est prérempli.
function AgencyPanel() {
  const feedback = useActionFeedback();
  const [profile, setProfile] = useState<AgencyProfile | null>(null);
  const [draft, setDraft] = useState<Record<string, string>>({});
  const [taxes, setTaxes] = useState<Tax[]>([]);
  const [taxDrafts, setTaxDrafts] = useState<Record<number, { rate: string; active: boolean; included: boolean }>>({});
  const [newTax, setNewTax] = useState({ name: "", rate: "" });
  const [log, setLog] = useState<AgencySettingChange[]>([]);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<NoticeState>(null);

  const load = useCallback(async () => {
    try {
      const [agency, rows, changes] = await Promise.all([
        apiFetch<AgencyProfile>("/agency-profile/"), apiList<Tax>("/taxes/"), apiList<AgencySettingChange>("/agency-changes/"),
      ]);
      setProfile(agency);
      setDraft(Object.fromEntries(agencyFields.map(([key]) => [key, String(agency[key] ?? "")])));
      setTaxes(rows);
      setTaxDrafts(Object.fromEntries(rows.map((tax) => [tax.id, { rate: tax.rate, active: tax.active, included: tax.included }])));
      setLog(changes);
    } catch (reason) { setNotice(failure(reason, "Les informations n’ont pas pu être chargées. Réessayez.")); }
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function saveAgency(event: FormEvent) {
    event.preventDefault();
    if (!window.confirm("Enregistrer les informations de l’agence ? Elles seront imprimées sur les billets.")) return;
    setBusy(true);
    try {
      await apiFetch("/agency-profile/", { method: "PATCH", body: JSON.stringify(draft) });
      feedback.success("Informations de l’agence enregistrées.");
      await load();
    } catch (reason) { feedback.failure(reason, "Les informations de l’agence n’ont pas été enregistrées."); }
    finally { setBusy(false); }
  }

  async function saveTax(tax: Tax) {
    const change = taxDrafts[tax.id];
    if (!change) return;
    if (!window.confirm(`Enregistrer la taxe ${tax.name} : ${change.rate} %, ${change.active ? "active" : "inactive"}, ${change.included ? "incluse dans le prix" : "non incluse"} ? Les billets déjà vendus gardent leur taux.`)) return;
    setBusy(true);
    try {
      await apiFetch(`/taxes/${tax.id}/`, { method: "PATCH", body: JSON.stringify(change) });
      feedback.success(`Taxe ${tax.name} enregistrée.`);
      await load();
    } catch (reason) { feedback.failure(reason, `La taxe ${tax.name} n’a pas été enregistrée.`); }
    finally { setBusy(false); }
  }

  async function addTax(event: FormEvent) {
    event.preventDefault();
    if (!window.confirm(`Ajouter la taxe ${newTax.name} à ${newTax.rate} %, incluse dans le prix ?`)) return;
    setBusy(true);
    try {
      await apiFetch("/taxes/", { method: "POST", body: JSON.stringify({ name: newTax.name, rate: newTax.rate, active: true, included: true }) });
      setNewTax({ name: "", rate: "" });
      feedback.success("Taxe ajoutée.");
      await load();
    } catch (reason) { feedback.failure(reason, "La taxe n’a pas été ajoutée."); }
    finally { setBusy(false); }
  }

  if (!profile) return <section className="card">{notice ? <Notice notice={notice} /> : <Loading />}</section>;
  return (
    <div className="space-y-5">
      <section className="card">
        <SectionHeading eyebrow="Imprimé en bas du billet" title="Informations de l’agence" />
        <p className="mb-4 text-sm text-slate-500">Un champ vide n’apparaît pas sur le billet. Les comptes bancaires ne sont jamais imprimés.</p>
        <form onSubmit={saveAgency} className="grid gap-3 md:grid-cols-2">
          {agencyFields.map(([key, label]) => (
            <label key={key} className={key === "bank_accounts" || key === "address" ? "md:col-span-2" : ""}>
              <span className="mb-1 block text-sm font-semibold">{label}</span>
              {key === "bank_accounts"
                ? <textarea className="field min-h-24" value={draft[key] ?? ""} placeholder="À renseigner" onChange={(e) => setDraft({ ...draft, [key]: e.target.value })} />
                : <input className="field" value={draft[key] ?? ""} placeholder="À renseigner" onChange={(e) => setDraft({ ...draft, [key]: e.target.value })} />}
            </label>
          ))}
          <div className="md:col-span-2"><button className="primary-button" disabled={busy}>{busy ? "Enregistrement…" : "Enregistrer"}</button></div>
        </form>
        {profile.updated_by_name && <p className="mt-3 text-sm text-slate-500">Dernière modification : {formatDate(profile.updated_at)} par {profile.updated_by_name}.</p>}
      </section>
      <section className="card">
        <SectionHeading eyebrow="Comprises dans le prix affiché" title="Taxes" />
        <p className="mb-4 text-sm text-slate-500">Taux modifiable : la valeur de 18 % a été transmise et n’est pas vérifiée pour le transport de voyageurs. Un billet déjà vendu garde son taux.</p>
        <div className="table-scroll">
          <table className="staff-table min-w-[620px]">
            <thead><tr><th>Taxe</th><th>Taux (%)</th><th>Active</th><th>Incluse dans le prix</th><th /></tr></thead>
            <tbody>
              {taxes.map((tax) => {
                const change = taxDrafts[tax.id] ?? { rate: tax.rate, active: tax.active, included: tax.included };
                return (
                  <tr key={tax.id}>
                    <td className="strong">{tax.name}</td>
                    <td><input className="field max-w-28" inputMode="decimal" aria-label={`Taux ${tax.name}`} value={change.rate} onChange={(e) => setTaxDrafts({ ...taxDrafts, [tax.id]: { ...change, rate: e.target.value } })} /></td>
                    <td><input type="checkbox" aria-label={`${tax.name} active`} checked={change.active} onChange={(e) => setTaxDrafts({ ...taxDrafts, [tax.id]: { ...change, active: e.target.checked } })} /></td>
                    <td><input type="checkbox" aria-label={`${tax.name} incluse`} checked={change.included} onChange={(e) => setTaxDrafts({ ...taxDrafts, [tax.id]: { ...change, included: e.target.checked } })} /></td>
                    <td className="text-right"><button className="secondary-button" disabled={busy} onClick={() => void saveTax(tax)}>Enregistrer</button></td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <form onSubmit={addTax} className="mt-4 flex flex-wrap items-end gap-3">
          <label><span className="mb-1 block text-sm font-semibold">Nouvelle taxe</span><input className="field" value={newTax.name} required onChange={(e) => setNewTax({ ...newTax, name: e.target.value })} /></label>
          <label><span className="mb-1 block text-sm font-semibold">Taux (%)</span><input className="field max-w-28" inputMode="decimal" required value={newTax.rate} onChange={(e) => setNewTax({ ...newTax, rate: e.target.value })} /></label>
          <button className="secondary-button" disabled={busy}>Ajouter</button>
        </form>
        <Notice notice={notice} />
      </section>
      <section className="card">
        <SectionHeading eyebrow="Lecture seule" title="Journal des modifications" />
        {log.length === 0 ? <EmptyState title="Aucune modification" text="Chaque changement apparaîtra ici." /> : (
          <div className="table-scroll">
            <table className="staff-table min-w-[720px]">
              <thead><tr><th>Date</th><th>Élément</th><th>Avant</th><th>Après</th><th>Par</th></tr></thead>
              <tbody>
                {log.map((entry) => (
                  <tr key={entry.id}>
                    <td className="whitespace-nowrap">{formatDate(entry.changed_at)}</td>
                    <td className="strong">{entry.label}</td>
                    <td className="text-sm">{describeChange(entry.old_value)}</td>
                    <td className="text-sm">{describeChange(entry.new_value)}</td>
                    <td>{entry.changed_by_name}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}

function BoardingPointsPanel({ locations, onChanged }: { locations: Location[]; onChanged: () => Promise<void> }) {
  const feedback = useActionFeedback();
  const [points, setPoints] = useState<BoardingPoint[] | null>(null);
  const [notice, setNotice] = useState<NoticeState>(null);
  const [busy, setBusy] = useState(false);
  const [newPoint, setNewPoint] = useState({ location: "", name: "", order: "1" });
  const [drafts, setDrafts] = useState<Record<number, { name: string; order: string; active: boolean }>>({});

  const load = useCallback(async () => {
    try {
      const rows = await apiList<BoardingPoint>("/boarding-points/?all=true");
      setPoints(rows);
      setDrafts(Object.fromEntries(rows.map((pt) => [pt.id, { name: pt.name, order: String(pt.order), active: pt.active }])));
    } catch (reason) {
      setNotice(failure(reason, "Les points d’embarquement n’ont pas pu être chargés."));
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function addPoint(event: FormEvent) {
    event.preventDefault();
    if (!newPoint.location || !newPoint.name.trim()) return;
    setBusy(true);
    try {
      await apiFetch("/boarding-points/", {
        method: "POST",
        body: JSON.stringify({
          location: Number(newPoint.location),
          name: newPoint.name.trim(),
          order: Number(newPoint.order) || 1,
          active: true,
        }),
      });
      setNewPoint({ location: "", name: "", order: "1" });
      feedback.success("Point d’embarquement ajouté.");
      await Promise.all([load(), onChanged()]);
    } catch (reason) {
      feedback.failure(reason, "Le point d’embarquement n’a pas été ajouté.");
    } finally {
      setBusy(false);
    }
  }

  async function savePoint(pt: BoardingPoint) {
    const draft = drafts[pt.id];
    if (!draft) return;
    setBusy(true);
    try {
      await apiFetch(`/boarding-points/${pt.id}/`, {
        method: "PATCH",
        body: JSON.stringify({
          name: draft.name.trim(),
          order: Number(draft.order) || 1,
          active: draft.active,
        }),
      });
      feedback.success(`Point « ${draft.name.trim()} » mis à jour.`);
      await Promise.all([load(), onChanged()]);
    } catch (reason) {
      feedback.failure(reason, "Le point d’embarquement n’a pas été modifié.");
    } finally {
      setBusy(false);
    }
  }

  async function removePoint(pt: BoardingPoint) {
    if (pt.is_used) return;
    if (!window.confirm(`Supprimer le point « ${pt.name} » (${pt.location_name}) ?`)) return;
    setBusy(true);
    try {
      await apiFetch(`/boarding-points/${pt.id}/`, { method: "DELETE" });
      feedback.success(`Point « ${pt.name} » supprimé.`);
      await Promise.all([load(), onChanged()]);
    } catch (reason) {
      feedback.failure(reason, "Le point d’embarquement n’a pas pu être supprimé.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="grid gap-5 xl:grid-cols-[1.35fr_.65fr]">
      <section className="card">
        <SectionHeading eyebrow="Embarquement & débarquement" title="Points d’embarquement par ville" />
        <p className="mb-4 text-sm text-slate-500">
          Un même point sert à l’embarquement et au débarquement d’une ville. Un billet déjà émis conserve le nom du point tel qu’il était au moment de la vente.
          Un point ayant déjà servi ne peut pas être supprimé (désactivez-le).
        </p>
        {points === null ? <Loading /> : points.length === 0 ? (
          <EmptyState title="Aucun point configuré" text="Ajoutez un point d’embarquement pour une ville dans le formulaire ci-contre." />
        ) : (
          <div className="table-scroll">
            <table className="staff-table min-w-[680px]">
              <thead>
                <tr>
                  <th>Ville</th>
                  <th>Nom du point</th>
                  <th>Ordre</th>
                  <th>Actif</th>
                  <th className="text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {points.map((pt) => {
                  const draft = drafts[pt.id] ?? { name: pt.name, order: String(pt.order), active: pt.active };
                  return (
                    <tr key={pt.id}>
                      <td className="strong">{pt.location_name}</td>
                      <td>
                        <input
                          className="field"
                          aria-label={`Nom ${pt.name}`}
                          value={draft.name}
                          onChange={(e) => setDrafts({ ...drafts, [pt.id]: { ...draft, name: e.target.value } })}
                        />
                      </td>
                      <td>
                        <input
                          className="field max-w-20"
                          type="number"
                          min={1}
                          aria-label={`Ordre ${pt.name}`}
                          value={draft.order}
                          onChange={(e) => setDrafts({ ...drafts, [pt.id]: { ...draft, order: e.target.value } })}
                        />
                      </td>
                      <td>
                        <input
                          type="checkbox"
                          aria-label={`${pt.name} actif`}
                          checked={draft.active}
                          onChange={(e) => setDrafts({ ...drafts, [pt.id]: { ...draft, active: e.target.checked } })}
                        />
                      </td>
                      <td className="text-right whitespace-nowrap space-x-2">
                        <button type="button" className="secondary-button" disabled={busy} onClick={() => void savePoint(pt)}>
                          Enregistrer
                        </button>
                        {!pt.is_used && (
                          <button type="button" className="text-button text-red-700" disabled={busy} onClick={() => void removePoint(pt)}>
                            Supprimer
                          </button>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
        <Notice notice={notice} />
      </section>

      <section className="card self-start">
        <SectionHeading eyebrow="Administration" title="Ajouter un point" />
        <form onSubmit={addPoint} className="space-y-4">
          <Select
            label="Ville"
            value={newPoint.location}
            onChange={(val) => setNewPoint({ ...newPoint, location: val })}
            options={locations.map((loc) => [String(loc.id), `${loc.name}${loc.active ? "" : " (ville inactive)"}`])}
          />
          <Input
            label="Nom du point d’embarquement"
            value={newPoint.name}
            onChange={(val) => setNewPoint({ ...newPoint, name: val })}
          />
          <Input
            label="Ordre d’affichage"
            type="number"
            value={newPoint.order}
            onChange={(val) => setNewPoint({ ...newPoint, order: val })}
          />
          <button className="primary-button w-full" disabled={busy}>
            Ajouter le point
          </button>
        </form>
      </section>
    </div>
  );
}

// Prix des tronçons de la ligne (mêmes prix dans les deux sens), relus au serveur à l'ouverture et après chaque modification.
// Villes (ajout, nom, activation) et ordre des arrêts de la ligne : tout est journalisé côté serveur.
function LinePanel({ locations, onChanged }: { locations: Location[]; onChanged: () => Promise<void> }) {
  const feedback = useActionFeedback();
  const [line, setLine] = useState<LineState | null>(null);
  const [order, setOrder] = useState<LineStopRow[]>([]);
  const [names, setNames] = useState<Record<number, string>>({});
  const [newCity, setNewCity] = useState("");
  const [toAdd, setToAdd] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<NoticeState>(null);

  const load = useCallback(async () => {
    try {
      const state = await apiFetch<LineState>("/line/");
      setLine(state);
      setOrder(state.stops);
    } catch (reason) { setNotice(failure(reason, "La ligne n’a pas pu être chargée. Réessayez.")); }
  }, []);

  useEffect(() => { void load(); }, [load]);
  useEffect(() => { setNames(Object.fromEntries(locations.map((l) => [l.id, l.name]))); }, [locations]);

  const dirty = line !== null && order.map((s) => s.location_id).join(",") !== line.stops.map((s) => s.location_id).join(",");

  function move(index: number, delta: number) {
    const next = [...order];
    const [row] = next.splice(index, 1);
    next.splice(index + delta, 0, row);
    setOrder(next);
  }

  async function run(action: () => Promise<unknown>, success: string, fallback: string) {
    setBusy(true);
    try {
      await action();
      feedback.success(success);
      await Promise.all([load(), onChanged()]);
    } catch (reason) {
      feedback.failure(reason, fallback);
    } finally { setBusy(false); }
  }

  function saveOrder() {
    if (!window.confirm(`Enregistrer l’ordre : ${order.map((s) => s.name).join(" → ")} ? Le retour suit l’ordre inverse.`)) return;
    void run(() => apiFetch("/line/", { method: "PUT", body: JSON.stringify({ location_ids: order.map((s) => s.location_id) }) }),
      "Ordre de la ligne enregistré.", "L’ordre de la ligne n’a pas été enregistré.");
  }

  function addCity(event: FormEvent) {
    event.preventDefault();
    const name = newCity.trim();
    if (!name) return;
    void run(async () => { await apiFetch("/locations/", { method: "POST", body: JSON.stringify({ name }) }); setNewCity(""); },
      `Ville ajoutée : ${name}. Ajoutez-la à la ligne pour la desservir.`, "La ville n’a pas été ajoutée.");
  }

  function rename(location: Location) {
    const name = (names[location.id] ?? "").trim();
    if (!name || name === location.name) return;
    if (!window.confirm(`Renommer ${location.name} en ${name} ? Le nouveau nom apparaîtra partout, y compris sur les billets.`)) return;
    void run(() => apiFetch(`/locations/${location.id}/`, { method: "PATCH", body: JSON.stringify({ name }) }),
      `Ville renommée : ${name}.`, "Le nom n’a pas été enregistré.");
  }

  function toggleCity(location: Location) {
    if (!window.confirm(location.active ? `Désactiver ${location.name} ? Elle ne sera plus proposée aux clients.` : `Réactiver ${location.name} ?`)) return;
    void run(() => apiFetch(`/locations/${location.id}/`, { method: "PATCH", body: JSON.stringify({ active: !location.active }) }),
      location.active ? `${location.name} désactivée.` : `${location.name} réactivée.`, "La modification n’a pas été enregistrée.");
  }

  const available = (line?.available ?? []).filter((row) => !order.some((s) => s.location_id === row.location_id));

  return (
    <div className="space-y-5">
      <section className="card">
        <SectionHeading eyebrow="Sens aller, le retour suit l’ordre inverse" title="Ordre des arrêts de la ligne" />
        {line === null ? <Loading /> : (
          <>
            <ol className="space-y-2">
              {order.map((stop, index) => (
                <li key={stop.location_id} className="flex flex-wrap items-center gap-2 rounded-lg border border-slate-200 p-2">
                  <span className="w-6 text-right font-semibold">{index + 1}.</span>
                  <span className="min-w-0 flex-1 font-medium">{stop.name}{(index === 0 || index === order.length - 1) && <span className="ml-2"><StatusBadge tone="grey">Terminus</StatusBadge></span>}</span>
                  <button type="button" className="secondary-button" aria-label={`Monter ${stop.name}`} disabled={busy || index <= 1 || index === order.length - 1} onClick={() => move(index, -1)}>↑</button>
                  <button type="button" className="secondary-button" aria-label={`Descendre ${stop.name}`} disabled={busy || index === 0 || index >= order.length - 2} onClick={() => move(index, 1)}>↓</button>
                  <button type="button" className="secondary-button" disabled={busy || index === 0 || index === order.length - 1} onClick={() => setOrder(order.filter((_, i) => i !== index))}>Retirer</button>
                </li>
              ))}
            </ol>
            <div className="mt-3 grid gap-2 sm:grid-cols-[1fr_auto] sm:items-end">
              <Select label="Ajouter une ville à la ligne (avant le terminus d’arrivée)" value={toAdd} onChange={setToAdd} options={available.map((row) => [String(row.location_id), row.name])} required={false} />
              <button type="button" className="secondary-button" disabled={busy || !toAdd} onClick={() => {
                const row = available.find((r) => String(r.location_id) === toAdd);
                if (!row) return;
                setOrder([...order.slice(0, -1), row, ...order.slice(-1)]);
                setToAdd("");
              }}>Ajouter</button>
            </div>
            <div className="mt-4 flex flex-wrap gap-2">
              <button className="primary-button" disabled={busy || !dirty} onClick={saveOrder}>{busy ? "Enregistrement…" : "Enregistrer l’ordre"}</button>
              {dirty && <button className="secondary-button" disabled={busy} onClick={() => setOrder(line.stops)}>Annuler</button>}
            </div>
            <p className="mt-2 text-sm text-slate-500">Les terminus ne changent pas ici. Un arrêt qui a encore des billets à venir ne peut pas être retiré. Un arrêt retiré perd ses tarifs vendables ; pensez aux tarifs d’un nouvel arrêt dans « Tarifs par tronçon ».</p>
          </>
        )}
        <Notice notice={notice} />
      </section>
      <section className="card">
        <SectionHeading eyebrow="Jamais supprimées : billets et tarifs gardent leur historique" title="Villes" />
        <form onSubmit={addCity} className="mb-4 grid gap-2 sm:grid-cols-[1fr_auto] sm:items-end">
          <label className="block"><span className="field-label">Nouvelle ville</span><input className="field" value={newCity} onChange={(e) => setNewCity(e.target.value)} maxLength={120} /></label>
          <button className="primary-button" disabled={busy || !newCity.trim()}>Ajouter la ville</button>
        </form>
        <ul className="space-y-2">
          {locations.map((location) => (
            <li key={location.id} className={`flex flex-wrap items-center gap-2 rounded-lg border border-slate-200 p-2 ${location.active ? "" : "opacity-60"}`}>
              <input className="field min-w-0 flex-1" aria-label={`Nom de ${location.name}`} value={names[location.id] ?? ""} onChange={(e) => setNames({ ...names, [location.id]: e.target.value })} maxLength={120} />
              {!location.active && <StatusBadge tone="grey">Inactive</StatusBadge>}
              <button className="secondary-button" disabled={busy || (names[location.id] ?? "").trim() === location.name} onClick={() => rename(location)}>Renommer</button>
              <button className="secondary-button" disabled={busy} onClick={() => toggleCity(location)}>{location.active ? "Désactiver" : "Réactiver"}</button>
            </li>
          ))}
        </ul>
      </section>
      <section className="card">
        <SectionHeading eyebrow="Lecture seule" title="Historique des villes et de la ligne" />
        {!line || line.log.length === 0 ? <EmptyState title="Aucune modification" text="Chaque changement apparaîtra ici." /> : (
          <ul className="space-y-2 text-sm">
            {line.log.map((row) => <li key={row.id}><span className="text-slate-500">{formatDate(row.created_at)} · {row.actor_name}</span><br />{row.detail}</li>)}
          </ul>
        )}
      </section>
    </div>
  );
}

function SegmentFarePanel() {
  const feedback = useActionFeedback();
  const [fares, setFares] = useState<SegmentFare[] | null>(null);
  const [missing, setMissing] = useState<MissingSegmentFare[]>([]);
  const [changes, setChanges] = useState<SegmentFareChange[]>([]);
  const [drafts, setDrafts] = useState<Record<number, string>>({});
  const [busy, setBusy] = useState<number | null>(null);
  const [notice, setNotice] = useState<NoticeState>(null);
  // Tarifs des villes retirées de la ligne (rang au-delà de 100) et tarifs retirés : gardés, masqués par défaut.
  const [showRetired, setShowRetired] = useState(false);
  const [lineStops, setLineStops] = useState<LineStopRow[]>([]);
  const [newFare, setNewFare] = useState({ origin: "", destination: "", amount: "" });

  const load = useCallback(async () => {
    try {
      const [rows, log, withoutFare, line] = await Promise.all([
        apiList<SegmentFare>("/segment-fares/"),
        apiList<SegmentFareChange>("/segment-fare-changes/"),
        apiFetch<MissingSegmentFare[]>("/segment-fares/missing/"),
        apiFetch<LineState>("/line/"),
      ]);
      setLineStops(line.stops);
      setFares(rows);
      setMissing(withoutFare);
      setChanges(log);
      setDrafts(Object.fromEntries(rows.map((row) => [row.id, String(row.amount)])));
    } catch (reason) { setNotice(failure(reason, "Les tarifs n’ont pas pu être chargés. Réessayez.")); }
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function save(fare: SegmentFare) {
    const typed = (drafts[fare.id] ?? "").replace(/[\s\u202f\u00a0]/g, "");
    if (!/^\d+$/.test(typed) || Number(typed) <= 0) {
      feedback.failure(null, `Prix de ${fare.label} : non enregistré. Saisissez un nombre entier de francs CFA, supérieur à zéro.`);
      return;
    }
    const amount = Number(typed);
    if (amount === fare.amount) { feedback.info(`Le prix de ${fare.label} est déjà de ${money(amount, fare.currency)} : rien à enregistrer.`); return; }
    if (!window.confirm(`Changer le prix de ${fare.label} : ${money(fare.amount, fare.currency)} → ${money(amount, fare.currency)} ?`)) return;
    setBusy(fare.id);
    try {
      await apiFetch(`/segment-fares/${fare.id}/`, { method: "PATCH", body: JSON.stringify({ amount }) });
      feedback.success(`Prix enregistré : ${fare.label} à ${money(amount, fare.currency)}.`);
      await load();
    } catch (reason) {
      feedback.failure(reason, `Le prix de ${fare.label} n’a pas été enregistré.`);
    } finally { setBusy(null); }
  }

  async function create(event: FormEvent) {
    event.preventDefault();
    const typed = newFare.amount.replace(/[\s\u202f\u00a0]/g, "");
    if (!newFare.origin || !newFare.destination || newFare.origin === newFare.destination) {
      feedback.failure(null, "Choisissez deux villes différentes de la ligne.");
      return;
    }
    if (!/^\d+$/.test(typed) || Number(typed) <= 0) {
      feedback.failure(null, "Saisissez un prix en nombre entier de francs CFA, supérieur à zéro.");
      return;
    }
    setBusy(-1);
    try {
      const fare = await apiFetch<SegmentFare>("/segment-fares/", {
        method: "POST",
        body: JSON.stringify({ origin_id: Number(newFare.origin), destination_id: Number(newFare.destination), amount: Number(typed) }),
      });
      feedback.success(`Tarif ajouté : ${fare.label} à ${money(fare.amount, fare.currency)}.`);
      setNewFare({ origin: "", destination: "", amount: "" });
      await load();
    } catch (reason) {
      feedback.failure(reason, "Le tarif n’a pas été ajouté.");
    } finally { setBusy(null); }
  }

  async function toggle(fare: SegmentFare) {
    const retire = fare.active;
    if (!window.confirm(retire
      ? `Retirer le tarif ${fare.label} ? Ce trajet ne sera plus vendable. Les billets déjà vendus ne changent pas.`
      : `Rétablir le tarif ${fare.label} à ${money(fare.amount, fare.currency)} ?`)) return;
    setBusy(fare.id);
    try {
      await apiFetch(`/segment-fares/${fare.id}/${retire ? "retire" : "restore"}/`, { method: "POST" });
      feedback.success(retire ? `Tarif retiré : ${fare.label}.` : `Tarif rétabli : ${fare.label}.`);
      await load();
    } catch (reason) {
      feedback.failure(reason, "La modification n’a pas été enregistrée.");
    } finally { setBusy(null); }
  }

  const stopOptions = lineStops.map((stop): [string, string] => [String(stop.location_id), stop.name]);

  return (
    <div className="space-y-5">
      <section className="card">
        <SectionHeading eyebrow="Nouveau tronçon" title="Ajouter un tarif" />
        <form onSubmit={create} className="grid gap-3 sm:grid-cols-4 sm:items-end">
          <Select label="De" value={newFare.origin} onChange={(value) => setNewFare({ ...newFare, origin: value })} options={stopOptions} />
          <Select label="À" value={newFare.destination} onChange={(value) => setNewFare({ ...newFare, destination: value })} options={stopOptions} />
          <label className="block"><span className="field-label">Prix (FCFA)</span>
            <input className="field" inputMode="numeric" value={newFare.amount} onChange={(e) => setNewFare({ ...newFare, amount: e.target.value })} required />
          </label>
          <button className="primary-button" disabled={busy !== null}>{busy === -1 ? "Ajout…" : "Ajouter"}</button>
        </form>
        <p className="mt-2 text-sm text-slate-500">Même prix dans les deux sens. Un tarif retiré peut être rétabli ici avec un nouveau prix.</p>
      </section>
      <section className="card">
        <SectionHeading eyebrow="Mêmes prix dans les deux sens" title="Tarifs par tronçon" />
        {missing.length > 0 && (
          <div className="mb-4 rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900" role="alert">
            <p className="font-semibold">Tronçons sans tarif : non vendables (aucun prix décidé pour ces trajets).</p>
            <ul className="mt-1 list-disc pl-5">
              {missing.map((row) => <li key={`${row.origin_id}-${row.destination_id}`}>{row.origin} ↔ {row.destination}</li>)}
            </ul>
          </div>
        )}
        <p className="mb-4 text-sm text-slate-500">Prix en francs CFA. Un billet déjà vendu ou une réservation en cours garde le prix du moment de la vente.</p>
        <label className="mb-3 flex items-center gap-2 text-sm"><input type="checkbox" checked={showRetired} onChange={(e) => setShowRetired(e.target.checked)} />Afficher les tarifs retirés et ceux des villes retirées de la ligne</label>
        {fares === null ? <Loading /> : fares.length === 0 ? <EmptyState title="Aucun tronçon" text="La grille des prix n’est pas encore chargée." /> : (
          <div className="table-scroll">
            <table className="staff-table min-w-[620px]">
              <thead><tr><th>Tronçon</th><th>Prix actuel</th><th>Nouveau prix</th><th /></tr></thead>
              <tbody>
                {fares.filter((fare) => showRetired || (fare.active && fare.start_position <= 100 && fare.end_position <= 100)).map((fare) => (
                  <tr key={fare.id} className={!fare.active || fare.start_position > 100 || fare.end_position > 100 ? "opacity-60" : undefined}>
                    <td className="strong">{fare.label}
                      {(fare.start_position > 100 || fare.end_position > 100) && <span className="ml-2"><StatusBadge tone="grey">Ville retirée</StatusBadge></span>}
                      {!fare.active && <span className="ml-2"><StatusBadge tone="grey">Tarif retiré</StatusBadge></span>}
                    </td>
                    <td className="whitespace-nowrap">{money(fare.amount, fare.currency)}</td>
                    <td>
                      <input className="field max-w-40" inputMode="numeric" aria-label={`Nouveau prix ${fare.label}`} value={drafts[fare.id] ?? ""} onChange={(e) => setDrafts({ ...drafts, [fare.id]: e.target.value })} />
                    </td>
                    <td className="text-right">
                      <div className="flex flex-wrap justify-end gap-2">
                        {fare.active && <button className="secondary-button" disabled={busy !== null} onClick={() => void save(fare)}>{busy === fare.id ? "Enregistrement…" : "Enregistrer"}</button>}
                        {(fare.active || (fare.start_position <= 100 && fare.end_position <= 100)) && (
                          <button className="secondary-button" disabled={busy !== null} onClick={() => void toggle(fare)}>{fare.active ? "Retirer" : "Rétablir"}</button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <Notice notice={notice} />
      </section>
      <section className="card">
        <SectionHeading eyebrow="Lecture seule" title="Historique des prix" />
        {changes.length === 0 ? <EmptyState title="Aucune modification" text="Chaque changement de prix apparaîtra ici." /> : (
          <div className="table-scroll">
            <table className="staff-table min-w-[620px]">
              <thead><tr><th>Date</th><th>Tronçon</th><th>Ancien prix</th><th>Nouveau prix</th><th>Action</th><th>Par</th></tr></thead>
              <tbody>
                {changes.map((change) => (
                  <tr key={change.id}>
                    <td className="whitespace-nowrap">{formatDate(change.created_at)}</td>
                    <td className="strong">{change.label}</td>
                    <td>{change.old_amount === null ? "—" : money(change.old_amount)}</td>
                    <td>{money(change.new_amount)}</td>
                    <td>{change.note || "Prix modifié"}</td>
                    <td>{change.changed_by_name}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}

// Paiements signalés par le prestataire que le serveur a refusé de transformer en billet : lecture seule, sauf « traité ».
// Statuts de billet forcés à la main par un administrateur (action « transition ») : journal en lecture seule.
function ManualTicketChangeLog() {
  const [changes, setChanges] = useState<ManualTicketChange[] | null>(null);
  const [notice, setNotice] = useState<NoticeState>(null);

  useEffect(() => {
    apiList<ManualTicketChange>("/ticket-manual-changes/")
      .then(setChanges)
      .catch((reason) => { setChanges([]); setNotice(failure(reason, "Le journal n’a pas pu être chargé. Réessayez.")); });
  }, []);

  return (
    <section className="card">
      <SectionHeading eyebrow="Lecture seule" title="Statuts de billets changés à la main" />
      <p className="mb-4 text-sm text-slate-500">Changements faits par un administrateur hors paiement, scan ou annulation par le client.</p>
      {changes === null ? <Loading /> : changes.length === 0 ? <EmptyState title="Aucun changement manuel" text="Chaque statut forcé à la main apparaîtra ici." /> : (
        <div className="table-scroll">
          <table className="staff-table min-w-[620px]">
            <thead><tr><th>Date</th><th>Billet</th><th>Ancien statut</th><th>Nouveau statut</th><th>Par</th><th>Note</th></tr></thead>
            <tbody>
              {changes.map((change) => (
                <tr key={change.id}>
                  <td className="whitespace-nowrap">{formatDate(change.changed_at)}</td>
                  <td className="strong">{change.reference}</td>
                  <td>{change.from_status_display || "—"}</td>
                  <td>{change.to_status_display}</td>
                  <td>{change.changed_by_name}</td>
                  <td>{change.note || "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <Notice notice={notice} />
    </section>
  );
}

function RefundDueBookingsPanel() {
  const [bookings, setBookings] = useState<Booking[] | null>(null);
  const [notice, setNotice] = useState<NoticeState>(null);

  useEffect(() => {
    apiList<Booking>("/bookings/?status=REFUND_DUE")
      .then(setBookings)
      .catch((reason) => {
        setBookings([]);
        setNotice(failure(reason, "Les réservations payées sans places disponibles n’ont pas pu être chargées."));
      });
  }, []);

  return (
    <section className="card">
      <SectionHeading
        eyebrow="Traitement manuel requis"
        title="Réservations payées · places indisponibles"
        action={
          bookings && (
            <StatusBadge tone={bookings.length > 0 ? "red" : "green"}>
              {bookings.length} réservation(s)
            </StatusBadge>
          )
        }
      />
      <p className="mb-4 text-sm text-slate-500">
        Paiements confirmés après l’expiration de la retenue alors qu’il ne restait plus assez de places libres sur le voyage. Aucun remboursement automatique n’est effectué.
      </p>
      {bookings === null ? (
        <Loading />
      ) : bookings.length === 0 ? (
        <EmptyState
          title="Aucune réservation en attente de traitement"
          text="Les réservations payées tardivement sans places disponibles apparaîtront ici."
        />
      ) : (
        <div className="table-scroll">
          <table className="staff-table min-w-[760px]">
            <thead>
              <tr>
                <th>Référence</th>
                <th>Trajet</th>
                <th>Départ</th>
                <th>Client / Passagers</th>
                <th>Montant payé</th>
                <th>Statut</th>
              </tr>
            </thead>
            <tbody>
              {bookings.map((b) => (
                <tr key={b.id}>
                  <td className="strong">{b.reference}</td>
                  <td>{b.segment_label || b.trip_detail.route_detail.label}</td>
                  <td className="whitespace-nowrap">{formatDate(b.effective_departure_at || b.trip_detail.departure_at)}</td>
                  <td>
                    {b.passengers.map((p) => p.full_name).join(", ") || "—"}
                    {b.contact_phone ? ` (${b.contact_phone})` : ""}
                  </td>
                  <td className="strong whitespace-nowrap">{money(b.amount, b.currency)}</td>
                  <td>
                    <StatusBadge tone="red">
                      {b.client_status_display || "Payée, places indisponibles"}
                    </StatusBadge>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <Notice notice={notice} />
    </section>
  );
}

function IncidentPanel({ incidents, onChanged }: { incidents: PaymentIncident[]; onChanged: () => Promise<void> }) {
  const feedback = useActionFeedback();

  async function setHandled(incident: PaymentIncident, handled: boolean) {
    try {
      await apiFetch(`/payment-incidents/${incident.id}/`, { method: "PATCH", body: JSON.stringify({ handled }) });
      feedback.success(handled ? "Incident marqué comme traité." : "Incident remis à traiter.");
      await onChanged();
    } catch (reason) { feedback.failure(reason, "L’incident n’a pas été mis à jour."); }
  }

  return (
    <section className="card">
      <SectionHeading eyebrow="À traiter à la main" title="Incidents de paiement" action={<StatusBadge tone={incidents.some((item) => !item.handled) ? "red" : "green"}>{incidents.filter((item) => !item.handled).length} non traité(s)</StatusBadge>} />
      {incidents.length === 0 ? <EmptyState title="Aucun incident" text="Les paiements refusés par le serveur apparaîtront ici." /> : (
        <div className="table-scroll">
          <table className="staff-table min-w-[860px]">
            <thead><tr><th>Date</th><th>Motif</th><th>Transaction</th><th>Montant</th><th>Réservation</th><th>Traité</th></tr></thead>
            <tbody>
              {incidents.map((incident) => (
                <tr key={incident.id}>
                  <td className="whitespace-nowrap">{formatDate(incident.created_at)}</td>
                  <td>{incident.reason}</td>
                  <td className="strong">{incident.external_id || "—"}</td>
                  <td className="whitespace-nowrap">
                    {incident.amount === null ? "—" : money(incident.amount, incident.currency || "XOF")}
                    {incident.amount !== null && !incident.amount_verified && <span className="ml-2"><StatusBadge tone="amber">non vérifié</StatusBadge></span>}
                  </td>
                  <td>{incident.booking_reference || "—"}</td>
                  <td>
                    <label className="flex items-center gap-2">
                      <input type="checkbox" checked={incident.handled} onChange={(e) => void setHandled(incident, e.target.checked)} />
                      <span>{incident.handled ? "Traité" : "À traiter"}</span>
                    </label>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

type TeamInvitation = { id: number; email: string; first_name: string; last_name: string; role: string; role_display: string; state: "PENDING" | "USED" | "EXPIRED"; state_display: string; expires_at: string; activation_url: string | null; email_sent?: boolean; email_error?: string };
type AccountChangeRow = { id: number; created_at: string; action_display: string; detail: string; target: string; actor: string };
const staffRoles: string[][] = [["COUNTER", "Guichetier"], ["CONTROLLER", "Contrôleur"], ["ADMIN", "Administrateur"]];
const emptyMember = { username: "", password: "", first_name: "", last_name: "", phone: "", role: "COUNTER" };
const emptyInvite = { first_name: "", last_name: "", email: "", role: "COUNTER" };

function TeamPanel({ users: initialUsers, onChanged }: { users: User[]; onChanged: () => Promise<void> }) {
  const feedback = useActionFeedback();
  const [users, setUsers] = useState<User[]>(initialUsers);
  const [search, setSearch] = useState("");
  const [form, setForm] = useState(emptyMember);
  const [invite, setInvite] = useState(emptyInvite);
  const [invitations, setInvitations] = useState<TeamInvitation[]>([]);
  const [changes, setChanges] = useState<AccountChangeRow[]>([]);
  const [busy, setBusy] = useState(false);
  const [resetTarget, setResetTarget] = useState<User | null>(null);
  const [resetPassword, setResetPassword] = useState("");
  const [lastLink, setLastLink] = useState<string | null>(null);
  const [resetLink, setResetLink] = useState<{ username: string; url: string } | null>(null);
  const [editTarget, setEditTarget] = useState<User | null>(null);
  const [editForm, setEditForm] = useState({ first_name: "", last_name: "", phone: "", email: "" });

  function openEdit(user: User) {
    setEditTarget(user);
    setEditForm({ first_name: user.first_name || "", last_name: user.last_name || "", phone: user.phone || "", email: user.email || "" });
  }

  async function submitEdit(event: FormEvent) {
    event.preventDefault();
    if (!editTarget || busy) return;
    setBusy(true);
    try {
      await apiFetch(`/users/${editTarget.id}/`, { method: "PATCH", body: JSON.stringify(editForm) });
      feedback.success(`Coordonnées de ${editTarget.username} enregistrées.`);
      setEditTarget(null);
      await reload();
    } catch (reason) { feedback.failure(reason, "Les coordonnées n’ont pas été modifiées."); }
    finally { setBusy(false); }
  }

  const reload = useCallback(async (query = search) => {
    try {
      const [rows, pending, log] = await Promise.all([
        apiList<User>(`/users/${query.trim() ? `?search=${encodeURIComponent(query.trim())}` : ""}`),
        apiFetch<TeamInvitation[]>("/staff-invitations/"),
        apiFetch<AccountChangeRow[]>("/users/changes/"),
      ]);
      setUsers(rows); setInvitations(pending); setChanges(log);
    } catch (reason) { feedback.failure(reason, "L’équipe n’a pas pu être chargée."); }
  }, [feedback, search]);

  useEffect(() => { void reload(""); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { const timer = window.setTimeout(() => void reload(search), 300); return () => window.clearTimeout(timer); }, [search]); // eslint-disable-line react-hooks/exhaustive-deps

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    try {
      await apiFetch("/users/", { method: "POST", body: JSON.stringify(form) });
      feedback.success(`Membre ${form.username} ajouté.`);
      setForm(emptyMember);
      setSearch("");
      await Promise.all([reload(""), onChanged()]);
    } catch (reason) { feedback.failure(reason, "Le membre n’a pas été ajouté."); }
    finally { setBusy(false); }
  }

  async function sendInvite(event: FormEvent) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    try {
      const created = await apiFetch<TeamInvitation>("/staff-invitations/", { method: "POST", body: JSON.stringify(invite) });
      if (created.email_sent) feedback.success(`Invitation envoyée à ${created.email}.`);
      else feedback.failure(null, `Invitation créée, mais ${created.email_error || "l’e-mail n’a pas été envoyé."}${created.activation_url ? " Copiez le lien et transmettez-le à la personne." : " Configurez la messagerie, puis cliquez sur « Renvoyer »."}`);
      setLastLink(created.activation_url);
      setInvite(emptyInvite);
      await reload();
    } catch (reason) { feedback.failure(reason, "L’invitation n’a pas été créée."); }
    finally { setBusy(false); }
  }

  async function resend(item: TeamInvitation) {
    try {
      const updated = await apiFetch<TeamInvitation>(`/staff-invitations/${item.id}/resend/`, { method: "POST", body: "{}" });
      if (updated.email_sent) feedback.success(`Invitation renvoyée à ${updated.email}.`);
      else feedback.failure(null, `Invitation prolongée de 48 h, mais ${updated.email_error || "l’e-mail n’a pas été envoyé."}`);
      await reload();
    } catch (reason) { feedback.failure(reason, "L’invitation n’a pas été renvoyée."); }
  }

  async function copyLink(url: string) {
    try { await navigator.clipboard.writeText(url); feedback.success("Lien d’activation copié. Transmettez-le uniquement à la personne invitée."); }
    catch { window.prompt("Copiez ce lien :", url); }
  }

  async function toggleActive(user: User) {
    const active = user.is_active !== false;
    if (active && !window.confirm(`Désactiver ${user.username} ? Il ne pourra plus se connecter et ses sessions seront fermées. Son historique est conservé.`)) return;
    try {
      await apiFetch(`/users/${user.id}/${active ? "deactivate" : "activate"}/`, { method: "POST", body: "{}" });
      feedback.success(`${user.username} ${active ? "désactivé" : "réactivé"}.`);
      await reload();
    } catch (reason) { feedback.failure(reason, "Le compte n’a pas été modifié."); }
  }

  // Client : il choisit lui-même son mot de passe par un lien ; l'admin ne le voit jamais.
  async function sendResetLink(user: User) {
    if (!window.confirm(`Envoyer à ${user.username} un lien pour choisir un nouveau mot de passe ?`)) return;
    setResetLink(null);
    try {
      const result = await apiFetch<{ email_sent: boolean; link: string; detail: string }>(`/users/${user.id}/reset-link/`, { method: "POST", body: "{}" });
      if (result.email_sent) feedback.success(result.detail);
      else { feedback.failure(null, result.detail); setResetLink({ username: user.username, url: result.link }); }
      await reload();
    } catch (reason) { feedback.failure(reason, "Le lien de réinitialisation n’a pas été créé."); }
  }

  async function copyResetLink(url: string) {
    try { await navigator.clipboard.writeText(url); feedback.success("Lien copié. Transmettez-le uniquement au client, il ne sert qu’une fois."); }
    catch { window.prompt("Copiez ce lien :", url); }
  }

  async function submitReset(event: FormEvent) {
    event.preventDefault();
    if (!resetTarget) return;
    try {
      await apiFetch(`/users/${resetTarget.id}/reset-password/`, { method: "POST", body: JSON.stringify({ password: resetPassword }) });
      feedback.success(`Mot de passe provisoire de ${resetTarget.username} enregistré. Ses sessions sont fermées ; il devra le changer à sa prochaine connexion.`);
      setResetTarget(null);
      setResetPassword("");
    } catch (reason) { feedback.failure(reason, "Le mot de passe n’a pas été modifié."); }
  }

  const pendingInvitations = invitations.filter((item) => item.state !== "USED");

  return (
    <div className="grid min-w-0 gap-5 xl:grid-cols-[1.25fr_.75fr]">
      <div className="min-w-0 space-y-5">
        <section className="card min-w-0">
          <SectionHeading eyebrow="Personnel d’abord, puis clients" title="Équipe Axis" />
          <input className="field mb-4" type="search" placeholder="Rechercher par nom, identifiant, e-mail ou téléphone" value={search} onChange={(e) => setSearch(e.target.value)} />
          <div className="table-scroll">
            <table className="staff-table min-w-[760px]">
              <thead><tr><th>Nom</th><th>Identifiant</th><th>Rôle</th><th>Contact</th><th>État</th><th>Actions</th></tr></thead>
              <tbody>
                {users.map((user) => (
                  <tr key={user.id} className={user.is_active === false ? "opacity-60" : undefined}>
                    <td className="strong">{[user.first_name, user.last_name].filter(Boolean).join(" ") || "—"}</td>
                    <td>{user.username}</td>
                    {/* Rôle en lecture seule : fixé à la création du compte, jamais changé depuis cette liste. */}
                    <td><StatusBadge tone={user.role === "ADMIN" ? "amber" : user.role === "CLIENT" ? "grey" : "blue"}>{user.role_display}</StatusBadge></td>
                    <td>{user.phone || user.email || "—"}</td>
                    <td><StatusBadge tone={user.is_active === false ? "grey" : "green"}>{user.is_active === false ? "Désactivé" : "Actif"}</StatusBadge></td>
                    <td className="whitespace-nowrap">
                      <button type="button" className="text-button mr-2" onClick={() => openEdit(user)}>Modifier</button>
                      {user.role === "CLIENT"
                        ? <button type="button" className="text-button mr-2" onClick={() => void sendResetLink(user)}>Lien de réinitialisation</button>
                        : <button type="button" className="text-button mr-2" onClick={() => { setResetTarget(user); setResetPassword(""); }}>Mot de passe provisoire</button>}
                      <button type="button" className="text-button danger" onClick={() => void toggleActive(user)}>{user.is_active === false ? "Réactiver" : "Désactiver"}</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {users.length === 0 && <EmptyState title="Aucun compte" text="Aucun compte ne correspond à la recherche." />}
        </section>
        <section className="card min-w-0">
          <SectionHeading eyebrow="Envoyées par e-mail, valables 48 h" title="Invitations" />
          {pendingInvitations.length === 0 ? <EmptyState title="Aucune invitation en cours" text="Les invitations envoyées apparaîtront ici." /> : (
            <div className="table-scroll">
              <table className="staff-table min-w-[620px]">
                <thead><tr><th>Personne</th><th>Rôle</th><th>État</th><th>Expire</th><th /></tr></thead>
                <tbody>
                  {pendingInvitations.map((item) => (
                    <tr key={item.id}>
                      <td><b>{[item.first_name, item.last_name].filter(Boolean).join(" ") || "—"}</b><br /><span className="text-xs text-slate-500">{item.email}</span></td>
                      <td>{item.role_display}</td>
                      <td><StatusBadge tone={item.state === "PENDING" ? "amber" : "grey"}>{item.state_display}</StatusBadge></td>
                      <td className="whitespace-nowrap">{formatDate(item.expires_at)}</td>
                      <td className="whitespace-nowrap text-right">
                        {item.activation_url && <button type="button" className="text-button mr-2" onClick={() => void copyLink(item.activation_url!)}>Copier le lien</button>}
                        <button type="button" className="text-button" onClick={() => void resend(item)}>Renvoyer</button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>
        <section className="card min-w-0">
          <SectionHeading eyebrow="Lecture seule" title="Journal des comptes" />
          {changes.length === 0 ? <EmptyState title="Aucune action" text="Créations, invitations, rôles et désactivations apparaîtront ici." /> : (
            <div className="table-scroll">
              <table className="staff-table min-w-[620px]">
                <thead><tr><th>Date</th><th>Action</th><th>Compte</th><th>Détail</th><th>Par</th></tr></thead>
                <tbody>
                  {changes.map((row) => (
                    <tr key={row.id}><td className="whitespace-nowrap">{formatDate(row.created_at)}</td><td>{row.action_display}</td><td>{row.target || "—"}</td><td>{row.detail || "—"}</td><td>{row.actor || "—"}</td></tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>
      </div>
      <div className="min-w-0 space-y-5 self-start">
        {editTarget && (
          <form onSubmit={submitEdit} className="card space-y-4">
            <SectionHeading eyebrow="Coordonnées" title={`Modifier ${editTarget.username}`} />
            <Input label="Prénom" value={editForm.first_name} onChange={(value) => setEditForm({ ...editForm, first_name: value })} required={false} />
            <Input label="Nom" value={editForm.last_name} onChange={(value) => setEditForm({ ...editForm, last_name: value })} required={false} />
            <Input label="Téléphone" type="tel" value={editForm.phone} onChange={(value) => setEditForm({ ...editForm, phone: value })} required={false} />
            <Input label="E-mail" type="email" value={editForm.email} onChange={(value) => setEditForm({ ...editForm, email: value })} required={false} />
            <button className="primary-button w-full" disabled={busy}>{busy ? "Enregistrement…" : "Enregistrer"}</button>
            <button type="button" className="text-button w-full" onClick={() => setEditTarget(null)}>Annuler</button>
          </form>
        )}
        {resetLink && (
          <div className="card space-y-3">
            <SectionHeading eyebrow="Lien de réinitialisation" title={resetLink.username} />
            <p className="text-sm text-slate-500">L’e-mail n’est pas parti : copiez ce lien et transmettez-le au client. Il ne sert qu’une fois.</p>
            <button type="button" className="primary-button w-full" onClick={() => void copyResetLink(resetLink.url)}>Copier le lien</button>
            <button type="button" className="text-button w-full" onClick={() => setResetLink(null)}>Fermer</button>
          </div>
        )}
        {resetTarget && (
          <form onSubmit={submitReset} className="card space-y-4">
            <SectionHeading eyebrow="Mot de passe provisoire" title={`Réinitialiser ${resetTarget.username}`} />
            <p className="text-sm text-slate-500">Communiquez-le à la personne en main propre. Toutes ses sessions seront fermées et elle devra le remplacer à sa prochaine connexion.</p>
            <Input label="Nouveau mot de passe" type="password" value={resetPassword} onChange={setResetPassword} />
            <button className="primary-button w-full">Enregistrer</button>
            <button type="button" className="text-button w-full" onClick={() => setResetTarget(null)}>Annuler</button>
          </form>
        )}
        <form onSubmit={sendInvite} className="card space-y-4">
          <SectionHeading eyebrow="Par e-mail" title="Inviter un membre" />
          <p className="text-sm text-slate-500">La personne reçoit un lien pour choisir elle-même son mot de passe. Son identifiant sera son e-mail.</p>
          <Input label="Prénom" value={invite.first_name} onChange={(value) => setInvite({ ...invite, first_name: value })} />
          <Input label="Nom" value={invite.last_name} onChange={(value) => setInvite({ ...invite, last_name: value })} />
          <Input label="E-mail" type="email" value={invite.email} onChange={(value) => setInvite({ ...invite, email: value })} />
          <Select label="Rôle" value={invite.role} onChange={(value) => setInvite({ ...invite, role: value })} options={staffRoles} />
          <button className="primary-button w-full" disabled={busy}>{busy ? "Envoi…" : "Envoyer l’invitation"}</button>
          {lastLink && <button type="button" className="secondary-button w-full" onClick={() => void copyLink(lastLink)}>Copier le lien d’activation</button>}
        </form>
        <form onSubmit={submit} className="card space-y-4">
          <SectionHeading eyebrow="Sans e-mail" title="Créer un compte" />
          <Input label="Identifiant" value={form.username} onChange={(value) => setForm({ ...form, username: value })} />
          <Input label="Mot de passe initial" type="password" value={form.password} onChange={(value) => setForm({ ...form, password: value })} />
          <Input label="Prénom" value={form.first_name} onChange={(value) => setForm({ ...form, first_name: value })} required={false} />
          <Input label="Nom" value={form.last_name} onChange={(value) => setForm({ ...form, last_name: value })} required={false} />
          <Input label="Téléphone" value={form.phone} onChange={(value) => setForm({ ...form, phone: value })} required={false} />
          <Select label="Rôle" value={form.role} onChange={(value) => setForm({ ...form, role: value })} options={[...staffRoles, ["CLIENT", "Client"]]} />
          <button className="primary-button w-full" disabled={busy}>{busy ? "Création…" : "Créer le compte"}</button>
        </form>
      </div>
    </div>
  );
}

function Input({ label, value, onChange, type = "text", required = true }: { label: string; value: string; onChange: (value: string) => void; type?: string; required?: boolean }) {
  return (
    <label className="block">
      <span className="field-label">{label}</span>
      {type === "password"
        ? <PasswordInput value={value} onChange={(e) => onChange(e.target.value)} required={required} autoComplete="new-password" />
        : <input className="field" type={type} value={value} onChange={(e) => onChange(e.target.value)} required={required} />}
    </label>
  );
}

function Select({ label, value, onChange, options, required = true }: { label: string; value: string; onChange: (value: string) => void; options: string[][]; required?: boolean }) {
  return (
    <label className="block">
      <span className="field-label">{label}</span>
      <select className="field" value={value} onChange={(e) => onChange(e.target.value)} required={required}>
        <option value="">Choisir</option>
        {options.map(([key, name]) => <option key={key} value={key}>{name}</option>)}
      </select>
    </label>
  );
}
