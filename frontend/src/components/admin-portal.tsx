"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import { AccessDenied, EmptyState, Loading, Notice, type NoticeState, SectionHeading, StaffLogin, StaffShell, StaffTitle, StatusBadge, ticketTone, tripTone, useActionFeedback } from "./ui";
import { SoldToday } from "./sold-today";
import { LoginCard } from "./login-card";
import { BusSeatMap } from "./bus-seat-map";
import { apiFetch, apiList, clearTokens, formatDate, getAccessToken, money } from "@/lib/api";
import { actionErrorText, counterTripLabel, holdMinutesConfigured, soldTicketWhatsappHref, upcomingSellableTrips, whatsappHref } from "@/lib/portal-rules";

import type { AgencyProfile, AgencySettingChange, BoardingPoint, Booking, FareRule, FeatureFlag, Location, ManualTicketChange, MissingSegmentFare, BusPosition, Tax, Parcel, PaymentIncident, PaymentMethod, Route, SegmentFare, SegmentFareChange, Seat, SystemSetting, Ticket, Trip, User, Vehicle, WeeklySchedule } from "@/lib/types";

type AdminTab = "dashboard" | "planning" | "guichet" | "points" | "colis" | "flotte" | "tarifs" | "troncons" | "agence" | "paiements" | "equipe";
type Dashboard = {
  tickets: { sold: number; online: number; counter: number; checked: number; cancelled_or_refunded: number };
  revenue: { total: number; by_payment_method: Array<{ payment_method__label: string; total: number }> };
  parcels: Array<{ status: string; count: number }>;
  trips: Array<{ id: number; label: string; sold: number; checked: number; capacity: number | null; revenue: number }>;
};

const nextParcelStatus: Record<string, string> = {
  REGISTERED: "DEPOSITED", DEPOSITED: "ACCEPTED", ACCEPTED: "ASSIGNED", ASSIGNED: "LOADED",
  LOADED: "IN_TRANSIT", IN_TRANSIT: "ARRIVED", ARRIVED: "READY_FOR_PICKUP", READY_FOR_PICKUP: "PICKED_UP",
};

const tabs: Array<[AdminTab, string]> = [
  ["dashboard", "Tableau de bord"], ["planning", "Trajets & planning"], ["guichet", "Vente au guichet"], ["points", "Points d’embarquement"], ["colis", "Colis"],
  ["flotte", "Flotte"], ["tarifs", "Tarifs & règles"], ["troncons", "Tarifs par tronçon"], ["agence", "Agence et taxes"], ["paiements", "Incidents de paiement"], ["equipe", "Équipe & rôles"],
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
        safe<Dashboard>("tableau de bord", { tickets: { sold: 0, checked: 0, online: 0, counter: 0, cancelled_or_refunded: 0 }, parcels: [], revenue: { total: "0" } } as unknown as Dashboard, apiFetch<Dashboard>("/dashboard/")),
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
          {tab === "planning" && <PlanningPanel routes={routes} vehicles={vehicles.filter((v) => v.category === "BUS")} trips={trips} weeklySchedules={weeklySchedules} onChanged={load} />}
          {tab === "guichet" && <><CounterPanel trips={trips} payments={payments} onChanged={load} /><SoldToday /></>}
          {tab === "points" && <BoardingPointsPanel locations={locations} onChanged={load} />}
          {tab === "colis" && <ParcelPanel parcels={parcels} trips={trips} onChanged={load} />}
          {tab === "flotte" && <FleetPanel locations={locations} vehicles={vehicles} onChanged={load} />}
          {tab === "tarifs" && <PricingPanel routes={routes} fares={fares} flags={flags} payments={payments} settings={settings} onChanged={load} />}
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
  const cards = [[data.tickets.sold, "Billets vendus"], [data.tickets.checked, "Passagers contrôlés"], [data.parcels.reduce((sum, item) => sum + item.count, 0), "Colis suivis"], [money(data.revenue.total), "Encaissements"]];
  // Les départs d'un itinéraire désactivé ne sont pas listés ici ; ils restent visibles dans « Trajets & planning ».
  const now = Date.now();
  const listed = trips
    .filter((trip) => trip.route_detail.active && trip.status !== "CANCELLED" && trip.status !== "COMPLETED" && new Date(trip.departure_at).getTime() >= now)
    .sort((a, b) => a.departure_at.localeCompare(b.departure_at));
  return (
    <>
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {cards.map(([value, label]) => (
          <div key={label} className="card">
            <p className="field-label">{label}</p>
            <p className="stat-value">{value}</p>
          </div>
        ))}
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

export function CounterPanel({ trips, payments, onChanged }: { trips: Trip[]; payments: PaymentMethod[]; onChanged: () => Promise<void> }) {
  const feedback = useActionFeedback();
  const [tripId, setTripId] = useState("");
  const [originId, setOriginId] = useState("");
  const [destinationId, setDestinationId] = useState("");
  const [boardingPointId, setBoardingPointId] = useState("");
  const [alightingPointId, setAlightingPointId] = useState("");
  const [seats, setSeats] = useState<Seat[]>([]);
  const [seat, setSeat] = useState("");
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  // Numéro WhatsApp du client, facultatif : sert seulement à lui envoyer le lien de son billet.
  const [whatsapp, setWhatsapp] = useState("");
  const [ticket, setTicket] = useState<Ticket | null>(null);
  const [notice, setNotice] = useState<NoticeState>(null);
  const [busy, setBusy] = useState(false);

  const selectedTrip = trips.find((t) => String(t.id) === tripId);
  const routeStops = selectedTrip?.route_detail?.stops || [];
  const effectiveOriginId = originId || (selectedTrip ? String(selectedTrip.route_detail.origin) : "");
  const effectiveDestId = destinationId || (selectedTrip ? String(selectedTrip.route_detail.destination) : "");

  const getPointsForCity = useCallback((cityIdStr: string) => {
    if (!cityIdStr || !selectedTrip) return [];
    const numId = Number(cityIdStr);
    const fromStop = selectedTrip.route_detail?.stops?.find((s) => s.id === numId || s.location_id === numId);
    if (fromStop?.boarding_points) return fromStop.boarding_points.filter((p) => p.active);
    if (selectedTrip.route_detail?.origin === numId && selectedTrip.route_detail.origin_detail?.boarding_points) {
      return selectedTrip.route_detail.origin_detail.boarding_points.filter((p) => p.active);
    }
    if (selectedTrip.route_detail?.destination === numId && selectedTrip.route_detail.destination_detail?.boarding_points) {
      return selectedTrip.route_detail.destination_detail.boarding_points.filter((p) => p.active);
    }
    return [];
  }, [selectedTrip]);

  const activeBoardingPoints = getPointsForCity(effectiveOriginId);
  const activeAlightingPoints = getPointsForCity(effectiveDestId);

  useEffect(() => {
    if (activeBoardingPoints.length === 1) {
      setBoardingPointId(String(activeBoardingPoints[0].id));
    } else if (activeBoardingPoints.length === 0) {
      setBoardingPointId("");
    } else if (!activeBoardingPoints.some((p) => String(p.id) === boardingPointId)) {
      setBoardingPointId("");
    }
  }, [effectiveOriginId, activeBoardingPoints, boardingPointId]);

  useEffect(() => {
    if (activeAlightingPoints.length === 1) {
      setAlightingPointId(String(activeAlightingPoints[0].id));
    } else if (activeAlightingPoints.length === 0) {
      setAlightingPointId("");
    } else if (!activeAlightingPoints.some((p) => String(p.id) === alightingPointId)) {
      setAlightingPointId("");
    }
  }, [effectiveDestId, activeAlightingPoints, alightingPointId]);

  const loadSeats = useCallback(async (id: string) => {
    if (!id) { setSeats([]); return; }
    try { setSeats(await apiList<Seat>(`/seats/?trip=${id}`)); } catch (reason) { setSeats([]); setNotice(failure(reason, "Chargement des sièges impossible.")); }
  }, []);

  useEffect(() => { void loadSeats(tripId); }, [tripId, loadSeats]);

  async function sell(event: FormEvent) {
    event.preventDefault();
    if (activeBoardingPoints.length > 1 && !boardingPointId) {
      feedback.failure(null, "Veuillez choisir un point d’embarquement.");
      return;
    }
    if (activeAlightingPoints.length > 1 && !alightingPointId) {
      feedback.failure(null, "Veuillez choisir un point de débarquement.");
      return;
    }
    setBusy(true);
    try {
      const created = await apiFetch<Ticket>("/tickets/", {
        method: "POST",
        body: JSON.stringify({
          trip: Number(tripId),
          seat: Number(seat),
          passenger_name: name,
          passenger_phone: phone,
          channel: "COUNTER",
          origin: originId || undefined,
          destination: destinationId || undefined,
          boarding_point_id: boardingPointId ? Number(boardingPointId) : undefined,
          alighting_point_id: alightingPointId ? Number(alightingPointId) : undefined,
        }),
      });
      setTicket(created);
      feedback.success("Siège bloqué. Enregistrez maintenant l’encaissement.");
      setSeat("");
      await Promise.all([onChanged(), loadSeats(tripId)]);
    } catch (reason) { feedback.failure(reason, "La vente n’a pas été enregistrée."); }
    finally { setBusy(false); }
  }

  async function pay(method: PaymentMethod) {
    if (!ticket) return;
    setBusy(true);
    try {
      const result = await apiFetch<{ ticket: Ticket }>(`/tickets/${ticket.id}/pay/`, { method: "POST", body: JSON.stringify({ payment_method: method.id }) });
      setTicket(result.ticket);
      feedback.success(`Billet ${result.ticket.reference} émis.`);
      await Promise.all([onChanged(), loadSeats(tripId)]);
    } catch (reason) { feedback.failure(reason, "L’encaissement n’a pas été enregistré."); }
    finally { setBusy(false); }
  }

  function reset() {
    setTicket(null); setNotice(null); setSeat(""); setName(""); setPhone("");
    setOriginId(""); setDestinationId(""); setBoardingPointId(""); setAlightingPointId("");
  }

  // Départs à venir et vendables (itinéraire actif, pas encore partis), du plus proche au plus lointain.
  const sellable = upcomingSellableTrips(trips);
  const activeMethods = payments.filter((p) => p.active);
  const held = ticket?.status === "HELD";

  return (
    <div className="grid gap-5 lg:grid-cols-2">
      <section className="card lg:col-span-2">
        <SectionHeading eyebrow="À vendre" title="Prochains départs" />
        {sellable.length === 0 ? <EmptyState title="Aucun départ à venir" text="Créez les départs dans l’onglet « Trajets & planning »." /> : (
          <div className="table-scroll">
            <table className="staff-table min-w-[640px]">
              <thead><tr><th>Départ</th><th>Parcours</th><th>Prix</th><th>Places libres</th><th /></tr></thead>
              <tbody>
                {sellable.map((trip) => (
                  <tr key={trip.id} className={String(trip.id) === tripId ? "bg-[var(--tint)]" : undefined}>
                    <td className="whitespace-nowrap">{formatDate(trip.departure_at)}</td>
                    <td className="strong">{trip.route_detail.label}</td>
                    <td className="whitespace-nowrap">{trip.current_fare ? money(trip.current_fare.amount, trip.current_fare.currency) : "sans prix (non vendable)"}</td>
                    <td>{trip.available_seats}</td>
                    <td className="text-right">
                      <button
                        type="button"
                        className="secondary-button"
                        disabled={!trip.current_fare || trip.available_seats === 0}
                        onClick={() => {
                          setTripId(String(trip.id));
                          setSeat("");
                          const stops = trip.route_detail?.stops || [];
                          if (stops.length >= 2) {
                            setOriginId(String(stops[0].id));
                            setDestinationId(String(stops[stops.length - 1].id));
                          } else {
                            setOriginId(String(trip.route_detail.origin));
                            setDestinationId(String(trip.route_detail.destination));
                          }
                        }}
                      >
                        {String(trip.id) === tripId ? "Sélectionné" : "Vendre"}
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
      <section className="card">
        <SectionHeading eyebrow="Base commune" title="Vendre un billet" />
        <form onSubmit={sell} className="space-y-4">
          <Select
            label="Voyage"
            value={tripId}
            onChange={(value) => {
              setTripId(value);
              setSeat("");
              const t = trips.find((item) => String(item.id) === value);
              const stops = t?.route_detail?.stops || [];
              if (stops.length >= 2) {
                setOriginId(String(stops[0].id));
                setDestinationId(String(stops[stops.length - 1].id));
              } else if (t) {
                setOriginId(String(t.route_detail.origin));
                setDestinationId(String(t.route_detail.destination));
              }
            }}
            options={sellable.map((trip) => [String(trip.id), counterTripLabel(trip.route_detail.label, formatDate(trip.departure_at), trip.current_fare ? money(trip.current_fare.amount, trip.current_fare.currency) : null)])}
          />
          {routeStops.length > 2 && (
            <div className="grid grid-cols-2 gap-3">
              <Select
                label="Arrêt de départ (montée)"
                value={originId}
                onChange={(val) => {
                  setOriginId(val);
                  const origIdx = routeStops.findIndex((s) => String(s.id) === val);
                  const destIdx = routeStops.findIndex((s) => String(s.id) === destinationId);
                  if (destIdx <= origIdx && origIdx < routeStops.length - 1) {
                    setDestinationId(String(routeStops[origIdx + 1].id));
                  }
                }}
                options={routeStops.slice(0, -1).map((s) => [String(s.id), s.name])}
              />
              <Select
                label="Arrêt d'arrivée (descente)"
                value={destinationId}
                onChange={setDestinationId}
                options={(() => {
                  const origIdx = routeStops.findIndex((s) => String(s.id) === originId);
                  const validStops = origIdx >= 0 ? routeStops.slice(origIdx + 1) : routeStops.slice(1);
                  return validStops.map((s) => [String(s.id), s.name]);
                })()}
              />
            </div>
          )}
          {selectedTrip && (activeBoardingPoints.length > 0 || activeAlightingPoints.length > 0) && (
            <div className="grid grid-cols-2 gap-3">
              {activeBoardingPoints.length > 0 && (
                <Select
                  label="Point d’embarquement"
                  value={boardingPointId}
                  onChange={setBoardingPointId}
                  options={activeBoardingPoints.map((pt) => [String(pt.id), pt.name])}
                  required={activeBoardingPoints.length > 1}
                />
              )}
              {activeAlightingPoints.length > 0 && (
                <Select
                  label="Point de débarquement"
                  value={alightingPointId}
                  onChange={setAlightingPointId}
                  options={activeAlightingPoints.map((pt) => [String(pt.id), pt.name])}
                  required={activeAlightingPoints.length > 1}
                />
              )}
            </div>
          )}
          <Select label="Siège libre" value={seat} onChange={setSeat} options={seats.filter((item) => item.status === "AVAILABLE").map((item) => [String(item.id), item.number])} />
          {seats.length > 0 && (
            <div>
              <span className="field-label">Plan des sièges (Libre · Retenu · Occupé)</span>
              <BusSeatMap
                seats={seats}
                selectedSeatIds={seat ? [Number(seat)] : []}
                onToggleSeat={(s) => setSeat(String(s.id))}
                maxSeats={1}
              />
            </div>
          )}
          <Input label="Nom du passager" value={name} onChange={setName} />
          <Input label="Téléphone" value={phone} onChange={setPhone} required={false} />
          <button className="primary-button w-full" disabled={busy || held}>Réserver au guichet</button>
        </form>
      </section>
      <section className="card">
        <SectionHeading eyebrow="Encaissement" title="Finaliser la vente" action={ticket && <StatusBadge tone={ticketTone(ticket.status)}>{ticket.status_display}</StatusBadge>} />
        {ticket ? (
          <div>
            <p className="text-lg font-extrabold text-axis-900">{ticket.reference}</p>
            <p className="mt-1 text-sm text-slate-500">{ticket.passenger_name} · siège {ticket.seat_detail.number}</p>
            <p className="text-sm font-semibold text-slate-700">{ticket.segment_label || ticket.trip_detail.route_detail.label}</p>
            {ticket.boarding_display && <p className="text-xs text-slate-600 mt-1">Embarquement : {ticket.boarding_display}</p>}
            {ticket.alighting_display && <p className="text-xs text-slate-600">Débarquement : {ticket.alighting_display}</p>}
            <dl className="mt-4 grid grid-cols-2 gap-3 text-sm">
              <div><dt className="field-label">Embarquement</dt><dd>{ticket.trip_detail.boarding_at ? formatDate(ticket.trip_detail.boarding_at) : "à confirmer"}</dd></div>
              <div><dt className="field-label">{ticket.departure_label || "Départ"}</dt><dd>{formatDate(ticket.effective_departure_at || ticket.trip_detail.departure_at)}</dd></div>
            </dl>
            <p className="field-label mt-4">Prix du billet</p>
            <p className="price">{money(ticket.amount, ticket.currency)}</p>
            {held && (
              <>
                <p className="field-label mt-5">Moyen de paiement</p>
                <div className="flex flex-wrap gap-2">
                  {activeMethods.map((method) => <button key={method.id} disabled={busy} onClick={() => void pay(method)} className="secondary-button">{method.label}</button>)}
                </div>
                {activeMethods.length === 0 && <Notice notice={{ text: "Configurez au moins un moyen de paiement actif.", tone: "error" }} />}
              </>
            )}
            {!held && (
              <div className="mt-5 flex flex-wrap gap-2">
                {ticket.status === "ISSUED" && <a className="primary-button" href={`/t/${encodeURIComponent(ticket.reference)}`} target="_blank" rel="noreferrer">Afficher / imprimer le billet</a>}
                <button className="secondary-button" onClick={() => { setWhatsapp(""); reset(); }}>Nouvelle vente</button>
              </div>
            )}
            {!held && ticket.status === "ISSUED" && (
              <div className="mt-4 rounded-lg border border-slate-200 p-3">
                <label className="block"><span className="field-label">WhatsApp du client (facultatif)</span>
                  <input className="field" inputMode="tel" value={whatsapp || phone} onChange={(e) => setWhatsapp(e.target.value)} placeholder="Format international, ex. : +229 …" />
                </label>
                {(whatsapp || phone) && !whatsappHref(whatsapp || phone) && <p className="mt-1 text-xs text-amber-700">Numéro au format international (+ et indicatif) pour l’ouvrir directement ; sinon WhatsApp vous laissera choisir le contact.</p>}
                <a className="primary-button mt-2 inline-flex" target="_blank" rel="noopener noreferrer"
                  href={soldTicketWhatsappHref({ reference: ticket.reference, passenger_name: ticket.passenger_name, passenger_phone: whatsapp || phone }, `${window.location.origin}/t/${encodeURIComponent(ticket.reference)}`)}>
                  Envoyer le billet par WhatsApp
                </a>
              </div>
            )}
          </div>
        ) : <EmptyState title="Aucune vente en cours" text="Sélectionnez un voyage et un siège dans la vue consolidée." />}
        <Notice notice={notice} />
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
                  <td><StatusBadge tone={parcel.status === "PICKED_UP" ? "green" : "blue"}>{parcel.status_display}</StatusBadge></td>
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

function FleetPanel({ locations, vehicles, onChanged }: { locations: Location[]; vehicles: Vehicle[]; onChanged: () => Promise<void> }) {
  const feedback = useActionFeedback();
  const emptyVehicle = { category: "BUS", name: "", registration_number: "", capacity: "", base_location: "", rental_daily_rate: "", driver_available: false, state: "ACTIVE", seat_configuration: "" };
  const [form, setForm] = useState(emptyVehicle);
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    try {
      const seatConfiguration = form.seat_configuration.trim() ? JSON.parse(form.seat_configuration) : [];
      await apiFetch("/vehicles/", { method: "POST", body: JSON.stringify({ ...form, seat_configuration: seatConfiguration, capacity: form.capacity ? Number(form.capacity) : null, base_location: form.base_location ? Number(form.base_location) : null, rental_daily_rate: form.rental_daily_rate || null, registration_number: form.registration_number || null }) });
      feedback.success("Véhicule ajouté.");
      setForm(emptyVehicle);
      await onChanged();
    } catch (reason) { feedback.failure(reason, "Le véhicule n’a pas été ajouté (vérifiez notamment le plan de sièges)."); }
    finally { setBusy(false); }
  }

  return (
    <div className="grid gap-5 xl:grid-cols-[1.35fr_.65fr]">
      <section className="grid content-start gap-4 md:grid-cols-2">
        {vehicles.map((vehicle) => <VehicleEditor key={vehicle.id} vehicle={vehicle} locations={locations} onChanged={onChanged} />)}
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
          {form.category === "RENTAL" && <Input label="Tarif journalier" type="number" value={form.rental_daily_rate} onChange={(value) => setForm({ ...form, rental_daily_rate: value })} required={false} />}
          <button className="primary-button w-full" disabled={busy}>{busy ? "Ajout…" : "Ajouter"}</button>
        </form>
      </section>
    </div>
  );
}

function VehicleEditor({ vehicle, locations, onChanged }: { vehicle: Vehicle; locations: Location[]; onChanged: () => Promise<void> }) {
  const feedback = useActionFeedback();
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState({ registration_number: vehicle.registration_number || "", capacity: vehicle.capacity ? String(vehicle.capacity) : "", base_location: vehicle.base_location ? String(vehicle.base_location) : "", rental_daily_rate: vehicle.rental_daily_rate || "", state: vehicle.state, seat_configuration: JSON.stringify(vehicle.seat_configuration || [], null, 2) });

  useEffect(() => { setForm({ registration_number: vehicle.registration_number || "", capacity: vehicle.capacity ? String(vehicle.capacity) : "", base_location: vehicle.base_location ? String(vehicle.base_location) : "", rental_daily_rate: vehicle.rental_daily_rate || "", state: vehicle.state, seat_configuration: JSON.stringify(vehicle.seat_configuration || [], null, 2) }); }, [vehicle]);

  async function save() {
    try {
      await apiFetch(`/vehicles/${vehicle.id}/`, { method: "PATCH", body: JSON.stringify({ registration_number: form.registration_number || null, capacity: form.capacity ? Number(form.capacity) : null, base_location: form.base_location ? Number(form.base_location) : null, rental_daily_rate: form.rental_daily_rate || null, state: form.state, seat_configuration: form.seat_configuration.trim() ? JSON.parse(form.seat_configuration) : [] }) });
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
    <article className="card">
      <div className="flex justify-between gap-3">
        <div>
          <p className="eyebrow">{vehicle.category_display}</p>
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
          {vehicle.category === "RENTAL" && <Input label="Tarif journalier" type="number" value={form.rental_daily_rate} onChange={(value) => setForm({ ...form, rental_daily_rate: value })} required={false} />}
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
            <div><dt className="field-label">Tarif location</dt><dd>{vehicle.category === "RENTAL" ? money(vehicle.rental_daily_rate) : "—"}</dd></div>
          </dl>
          <div className="mt-5 grid gap-3">
            <button className="secondary-button w-full" onClick={() => setEditing(true)}>Configurer</button>
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

  async function addMethod() {
    try {
      await apiFetch("/payment-methods/", { method: "POST", body: JSON.stringify({ code: method.toLowerCase().replace(/[^a-z0-9]+/g, "-"), label: method, active: true }) });
      feedback.success(`Moyen de paiement « ${method} » ajouté.`);
      setMethod("");
      await onChanged();
    } catch (reason) { feedback.failure(reason, `Le moyen de paiement « ${method} » n’a pas été ajouté.`); }
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
            <div className="mb-3 flex flex-wrap gap-2">
              {payments.map((p) => <StatusBadge key={p.id} tone={p.active ? "green" : "red"}>{p.label}</StatusBadge>)}
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
function SegmentFarePanel() {
  const feedback = useActionFeedback();
  const [fares, setFares] = useState<SegmentFare[] | null>(null);
  const [missing, setMissing] = useState<MissingSegmentFare[]>([]);
  const [changes, setChanges] = useState<SegmentFareChange[]>([]);
  const [drafts, setDrafts] = useState<Record<number, string>>({});
  const [busy, setBusy] = useState<number | null>(null);
  const [notice, setNotice] = useState<NoticeState>(null);
  // Tarifs des villes retirées de la ligne (rang au-delà de 100) : gardés, masqués par défaut.
  const [showRetired, setShowRetired] = useState(false);

  const load = useCallback(async () => {
    try {
      const [rows, log, withoutFare] = await Promise.all([
        apiList<SegmentFare>("/segment-fares/"),
        apiList<SegmentFareChange>("/segment-fare-changes/"),
        apiFetch<MissingSegmentFare[]>("/segment-fares/missing/"),
      ]);
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

  return (
    <div className="space-y-5">
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
        <label className="mb-3 flex items-center gap-2 text-sm"><input type="checkbox" checked={showRetired} onChange={(e) => setShowRetired(e.target.checked)} />Afficher les tarifs des villes retirées (Kétou, Porto-Novo…)</label>
        {fares === null ? <Loading /> : fares.length === 0 ? <EmptyState title="Aucun tronçon" text="La grille des prix n’est pas encore chargée." /> : (
          <div className="table-scroll">
            <table className="staff-table min-w-[620px]">
              <thead><tr><th>Tronçon</th><th>Prix actuel</th><th>Nouveau prix</th><th /></tr></thead>
              <tbody>
                {fares.filter((fare) => showRetired || (fare.start_position <= 100 && fare.end_position <= 100)).map((fare) => (
                  <tr key={fare.id} className={fare.start_position > 100 || fare.end_position > 100 ? "opacity-60" : undefined}>
                    <td className="strong">{fare.label}{(fare.start_position > 100 || fare.end_position > 100) && <span className="ml-2"><StatusBadge tone="grey">Ville retirée</StatusBadge></span>}</td>
                    <td className="whitespace-nowrap">{money(fare.amount, fare.currency)}</td>
                    <td>
                      <input className="field max-w-40" inputMode="numeric" aria-label={`Nouveau prix ${fare.label}`} value={drafts[fare.id] ?? ""} onChange={(e) => setDrafts({ ...drafts, [fare.id]: e.target.value })} />
                    </td>
                    <td className="text-right"><button className="secondary-button" disabled={busy !== null} onClick={() => void save(fare)}>{busy === fare.id ? "Enregistrement…" : "Enregistrer"}</button></td>
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
              <thead><tr><th>Date</th><th>Tronçon</th><th>Ancien prix</th><th>Nouveau prix</th><th>Par</th></tr></thead>
              <tbody>
                {changes.map((change) => (
                  <tr key={change.id}>
                    <td className="whitespace-nowrap">{formatDate(change.created_at)}</td>
                    <td className="strong">{change.label}</td>
                    <td>{change.old_amount === null ? "—" : money(change.old_amount)}</td>
                    <td>{money(change.new_amount)}</td>
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

  async function changeRole(user: User, role: string) {
    if (role === user.role) return;
    if (!window.confirm(`Changer le rôle de ${user.username} en « ${[...staffRoles, ["CLIENT", "Client"]].find(([key]) => key === role)?.[1]} » ? Ses sessions ouvertes seront fermées.`)) return;
    try {
      await apiFetch(`/users/${user.id}/`, { method: "PATCH", body: JSON.stringify({ role }) });
      feedback.success(`Rôle de ${user.username} modifié.`);
      await reload();
    } catch (reason) { feedback.failure(reason, "Le rôle n’a pas été modifié."); }
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

  async function submitReset(event: FormEvent) {
    event.preventDefault();
    if (!resetTarget) return;
    try {
      await apiFetch(`/users/${resetTarget.id}/reset-password/`, { method: "POST", body: JSON.stringify({ password: resetPassword }) });
      feedback.success(`Mot de passe de ${resetTarget.username} modifié. Ses sessions sont fermées.`);
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
                    <td>
                      <select className="field max-w-40" aria-label={`Rôle de ${user.username}`} value={user.role} onChange={(e) => void changeRole(user, e.target.value)}>
                        {[...staffRoles, ["CLIENT", "Client"]].map(([key, label]) => <option key={key} value={key}>{label}</option>)}
                      </select>
                    </td>
                    <td>{user.phone || user.email || "—"}</td>
                    <td><StatusBadge tone={user.is_active === false ? "grey" : "green"}>{user.is_active === false ? "Désactivé" : "Actif"}</StatusBadge></td>
                    <td className="whitespace-nowrap">
                      <button type="button" className="text-button mr-2" onClick={() => { setResetTarget(user); setResetPassword(""); }}>Mot de passe</button>
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
        {resetTarget && (
          <form onSubmit={submitReset} className="card space-y-4">
            <SectionHeading eyebrow="Mot de passe" title={`Réinitialiser ${resetTarget.username}`} />
            <p className="text-sm text-slate-500">Communiquez-le à la personne en main propre. Toutes ses sessions seront fermées.</p>
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
      <input className="field" type={type} value={value} onChange={(e) => onChange(e.target.value)} required={required} autoComplete={type === "password" ? "new-password" : undefined} />
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
