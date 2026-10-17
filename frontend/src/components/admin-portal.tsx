"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import { AccessDenied, EmptyState, Loading, Notice, type NoticeState, SectionHeading, StaffLogin, StaffShell, StaffTitle, StatusBadge, ticketTone, tripTone, useActionFeedback } from "./ui";
import { LoginCard } from "./login-card";
import { apiFetch, apiList, clearTokens, formatDate, getAccessToken, money } from "@/lib/api";
import { actionErrorText, counterTripLabel, holdMinutesConfigured } from "@/lib/portal-rules";
import type { AgencyProfile, AgencySettingChange, FareRule, FeatureFlag, Location, ManualTicketChange, Tax, Parcel, PaymentIncident, PaymentMethod, Route, SegmentFare, SegmentFareChange, Seat, SystemSetting, Ticket, Trip, User, Vehicle } from "@/lib/types";

type AdminTab = "dashboard" | "planning" | "guichet" | "colis" | "flotte" | "tarifs" | "troncons" | "agence" | "paiements" | "equipe";
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
  ["dashboard", "Tableau de bord"], ["planning", "Trajets & planning"], ["guichet", "Vente au guichet"], ["colis", "Colis"],
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
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const [accessDenied, setAccessDenied] = useState(false);

  const load = useCallback(async () => {
    if (!getAccessToken()) { setLoading(false); return; }
    setLoading(true); setError(""); setAccessDenied(false);
    try {
      const currentUser = await apiFetch<User>("/auth/me/");
      if (currentUser.role !== "ADMIN") { setMe(currentUser); setAccessDenied(true); return; }
      const [dash, allLocations, allRoutes, allTrips, allVehicles, allFares, allFlags, team, allParcels, methods, allSettings, allIncidents] = await Promise.all([
        apiFetch<Dashboard>("/dashboard/"), apiList<Location>("/locations/?all=true"), apiList<Route>("/routes/?all=true"),
        apiList<Trip>("/trips/?all=true"), apiList<Vehicle>("/vehicles/"), apiList<FareRule>("/fare-rules/?all=true"),
        apiList<FeatureFlag>("/feature-flags/"), apiList<User>("/users/"), apiList<Parcel>("/parcels/"), apiList<PaymentMethod>("/payment-methods/?all=true"), apiList<SystemSetting>("/settings/"),
        apiList<PaymentIncident>("/payment-incidents/"),
      ]);
      setMe(currentUser); setDashboard(dash); setLocations(allLocations); setRoutes(allRoutes); setTrips(allTrips); setVehicles(allVehicles);
      setFares(allFares); setFlags(allFlags); setUsers(team); setParcels(allParcels); setPayments(methods); setSettings(allSettings); setIncidents(allIncidents);
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
          {tab === "dashboard" && <DashboardPanel data={dashboard} trips={trips} />}
          {tab === "planning" && <PlanningPanel routes={routes} vehicles={vehicles.filter((v) => v.category === "BUS")} trips={trips} onChanged={load} />}
          {tab === "guichet" && <CounterPanel trips={trips} payments={payments} onChanged={load} />}
          {tab === "colis" && <ParcelPanel parcels={parcels} trips={trips} onChanged={load} />}
          {tab === "flotte" && <FleetPanel locations={locations} vehicles={vehicles} onChanged={load} />}
          {tab === "tarifs" && <PricingPanel routes={routes} fares={fares} flags={flags} payments={payments} settings={settings} onChanged={load} />}
          {tab === "troncons" && <SegmentFarePanel />}
          {tab === "agence" && <AgencyPanel />}
          {tab === "paiements" && <div className="space-y-5"><IncidentPanel incidents={incidents} onChanged={load} /><ManualTicketChangeLog /></div>}
          {tab === "equipe" && <TeamPanel users={users} onChanged={load} />}
        </>
      )}
    </StaffShell>
  );
}

function DashboardPanel({ data, trips }: { data: Dashboard | null; trips: Trip[] }) {
  if (!data) return null;
  const cards = [[data.tickets.sold, "Billets vendus"], [data.tickets.checked, "Passagers contrôlés"], [data.parcels.reduce((sum, item) => sum + item.count, 0), "Colis suivis"], [money(data.revenue.total), "Encaissements"]];
  // Les départs d'un itinéraire désactivé ne sont pas listés ici ; ils restent visibles dans « Trajets & planning ».
  const listed = trips.filter((trip) => trip.route_detail.active);
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
          <SectionHeading eyebrow="Source de vérité" title="Trajets de la période" />
          {listed.length ? (
            <div className="table-scroll">
              <table className="staff-table min-w-[620px]">
                <thead><tr><th>Trajet</th><th>Date</th><th>Ventes</th><th>Statut</th></tr></thead>
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

function PlanningPanel({ routes, vehicles, trips, onChanged }: { routes: Route[]; vehicles: Vehicle[]; trips: Trip[]; onChanged: () => Promise<void> }) {
  const feedback = useActionFeedback();
  const [form, setForm] = useState({ route: "", vehicle: "", departure_at: "", arrival_at: "", status: "SCHEDULED", note: "" });

  async function submit(event: FormEvent) {
    event.preventDefault();
    try {
      await apiFetch<Trip>("/trips/", { method: "POST", body: JSON.stringify({ ...form, route: Number(form.route), vehicle: Number(form.vehicle), arrival_at: form.arrival_at || null }) });
      feedback.success("Trajet ajouté au planning.");
      await onChanged();
    } catch (reason) { feedback.failure(reason, "Le trajet n’a pas été ajouté."); }
  }

  async function cancel(trip: Trip) {
    try {
      await apiFetch(`/trips/${trip.id}/`, { method: "PATCH", body: JSON.stringify({ status: "CANCELLED" }) });
      feedback.success(`Trajet du ${formatDate(trip.departure_at)} annulé.`);
      await onChanged();
    } catch (reason) { feedback.failure(reason, "Le trajet n’a pas été annulé."); }
  }

  return (
    <div className="grid gap-5 xl:grid-cols-[1.45fr_.55fr]">
      <section className="card">
        <SectionHeading eyebrow="Table modifiable" title="Planning réel" />
        {trips.length ? (
          <div className="table-scroll">
            <table className="staff-table min-w-[720px]">
              <thead><tr><th>Date</th><th>Parcours</th><th>Bus</th><th>Places</th><th>Statut</th><th /></tr></thead>
              <tbody>
                {trips.map((trip) => (
                  <tr key={trip.id}>
                    <td>{formatDate(trip.departure_at)}</td>
                    <td className="strong">{trip.route_detail.label}</td>
                    <td>{trip.vehicle_detail.name}</td>
                    <td>{trip.vehicle_detail.capacity ?? "À configurer"}</td>
                    <td>
                      <span className="flex flex-wrap gap-1.5">
                        <StatusBadge tone={tripTone(trip.status)}>{trip.status_display}</StatusBadge>
                        {!trip.route_detail.active && <StatusBadge tone="grey">Itinéraire inactif</StatusBadge>}
                      </span>
                    </td>
                    <td className="text-right">{trip.status !== "CANCELLED" && <button onClick={() => void cancel(trip)} className="text-button danger">Annuler</button>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : <EmptyState title="Planning vide" text="Ajoutez chaque trajet et chaque exception comme un enregistrement indépendant." />}
      </section>
      <section className="card">
        <SectionHeading eyebrow="Horaire administrable" title="Ajouter un trajet" />
        <form onSubmit={submit} className="space-y-4">
          <Select label="Parcours" value={form.route} onChange={(value) => setForm({ ...form, route: value })} options={routes.map((r) => [String(r.id), r.label])} />
          <Select label="Véhicule" value={form.vehicle} onChange={(value) => setForm({ ...form, vehicle: value })} options={vehicles.map((v) => [String(v.id), `${v.name} · ${v.capacity ?? "capacité requise"}`])} />
          <Input label="Départ" type="datetime-local" value={form.departure_at} onChange={(value) => setForm({ ...form, departure_at: value })} />
          <Input label="Arrivée (même jour)" type="datetime-local" value={form.arrival_at} onChange={(value) => setForm({ ...form, arrival_at: value })} required={false} />
          <button className="primary-button w-full">Ajouter au planning</button>
        </form>
      </section>
    </div>
  );
}

export function CounterPanel({ trips, payments, onChanged }: { trips: Trip[]; payments: PaymentMethod[]; onChanged: () => Promise<void> }) {
  const feedback = useActionFeedback();
  const [tripId, setTripId] = useState("");
  const [seats, setSeats] = useState<Seat[]>([]);
  const [seat, setSeat] = useState("");
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [ticket, setTicket] = useState<Ticket | null>(null);
  const [notice, setNotice] = useState<NoticeState>(null);
  const [busy, setBusy] = useState(false);

  const loadSeats = useCallback(async (id: string) => {
    if (!id) { setSeats([]); return; }
    try { setSeats(await apiList<Seat>(`/seats/?trip=${id}`)); } catch (reason) { setSeats([]); setNotice(failure(reason, "Chargement des sièges impossible.")); }
  }, []);

  useEffect(() => { void loadSeats(tripId); }, [tripId, loadSeats]);

  async function sell(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    try {
      const created = await apiFetch<Ticket>("/tickets/", { method: "POST", body: JSON.stringify({ trip: Number(tripId), seat: Number(seat), passenger_name: name, passenger_phone: phone, channel: "COUNTER" }) });
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
  }

  // Les départs d'un itinéraire désactivé ne sont pas proposés à la vente.
  const sellable = trips.filter((trip) => trip.route_detail.active && ["SCHEDULED", "BOARDING"].includes(trip.status));
  const activeMethods = payments.filter((p) => p.active);
  const held = ticket?.status === "HELD";

  return (
    <div className="grid gap-5 lg:grid-cols-2">
      <section className="card">
        <SectionHeading eyebrow="Base commune" title="Vendre un billet" />
        <form onSubmit={sell} className="space-y-4">
          <Select label="Voyage" value={tripId} onChange={(value) => { setTripId(value); setSeat(""); }} options={sellable.map((trip) => [String(trip.id), counterTripLabel(trip.route_detail.label, formatDate(trip.departure_at), trip.current_fare ? money(trip.current_fare.amount, trip.current_fare.currency) : null)])} />
          <Select label="Siège libre" value={seat} onChange={setSeat} options={seats.filter((item) => item.status === "AVAILABLE").map((item) => [String(item.id), item.number])} />
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
            <p className="text-sm text-slate-500">{ticket.trip_detail.route_detail.label}</p>
            <dl className="mt-4 grid grid-cols-2 gap-3 text-sm">
              <div><dt className="field-label">Embarquement</dt><dd>{ticket.trip_detail.boarding_at ? formatDate(ticket.trip_detail.boarding_at) : "à confirmer"}</dd></div>
              <div><dt className="field-label">Départ</dt><dd>{formatDate(ticket.trip_detail.departure_at)}</dd></div>
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
                {ticket.status === "ISSUED" && <a className="primary-button" href={`/t/${encodeURIComponent(ticket.reference)}`} target="_blank" rel="noreferrer">Afficher le billet</a>}
                <button className="secondary-button" onClick={reset}>Nouvelle vente</button>
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
      {parcels.length === 0 ? <EmptyState title="Aucun colis" text="Les colis en ligne et au guichet apparaîtront dans la même liste." /> : (
        <div className="table-scroll">
          <table className="staff-table min-w-[820px]">
            <thead><tr><th>Référence</th><th>Trajet</th><th>Destinataire</th><th>Statut</th><th>Étape suivante</th></tr></thead>
            <tbody>
              {parcels.map((parcel) => (
                <tr key={parcel.id}>
                  <td className="strong">{parcel.tracking_number}</td>
                  <td>{parcel.origin_detail.name} → {parcel.destination_detail.name}</td>
                  <td>{parcel.recipient_name}</td>
                  <td><StatusBadge tone={parcel.status === "PICKED_UP" ? "green" : "blue"}>{parcel.status_display}</StatusBadge></td>
                  <td>
                    <span className="flex flex-wrap items-center gap-2">
                      {nextParcelStatus[parcel.status] === "ASSIGNED" && (
                        <select className="field max-w-56" value={assignments[parcel.id] || ""} onChange={(e) => setAssignments({ ...assignments, [parcel.id]: e.target.value })}>
                          <option value="">Affecter un trajet</option>
                          {trips.filter((t) => t.route === undefined || (t.route_detail.origin === parcel.origin && t.route_detail.destination === parcel.destination)).map((trip) => <option key={trip.id} value={trip.id}>{formatDate(trip.departure_at)}</option>)}
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
  const [form, setForm] = useState({ category: "BUS", name: "", registration_number: "", capacity: "", base_location: "", rental_daily_rate: "", driver_available: false, state: "ACTIVE", seat_configuration: "" });

  async function submit(event: FormEvent) {
    event.preventDefault();
    try {
      const seatConfiguration = form.seat_configuration.trim() ? JSON.parse(form.seat_configuration) : [];
      await apiFetch("/vehicles/", { method: "POST", body: JSON.stringify({ ...form, seat_configuration: seatConfiguration, capacity: form.capacity ? Number(form.capacity) : null, base_location: form.base_location ? Number(form.base_location) : null, rental_daily_rate: form.rental_daily_rate || null, registration_number: form.registration_number || null }) });
      feedback.success("Véhicule ajouté.");
      await onChanged();
    } catch (reason) { feedback.failure(reason, "Le véhicule n’a pas été ajouté (vérifiez notamment le plan de sièges)."); }
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
          <button className="primary-button w-full">Ajouter</button>
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
        <p className="mb-4 text-sm text-slate-500">Un champ vide est imprimé « À renseigner ». Les comptes bancaires ne sont jamais imprimés.</p>
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
        <SectionHeading eyebrow="Comprises dans le prix affiché (TTC)" title="Taxes" />
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

// Prix des tronçons de la ligne (mêmes prix dans les deux sens), relus au serveur à l'ouverture et après chaque modification.
function SegmentFarePanel() {
  const feedback = useActionFeedback();
  const [fares, setFares] = useState<SegmentFare[] | null>(null);
  const [changes, setChanges] = useState<SegmentFareChange[]>([]);
  const [drafts, setDrafts] = useState<Record<number, string>>({});
  const [busy, setBusy] = useState<number | null>(null);
  const [notice, setNotice] = useState<NoticeState>(null);

  const load = useCallback(async () => {
    try {
      const [rows, log] = await Promise.all([apiList<SegmentFare>("/segment-fares/"), apiList<SegmentFareChange>("/segment-fare-changes/")]);
      setFares(rows);
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
        <p className="mb-4 text-sm text-slate-500">Prix en francs CFA. Un billet déjà vendu ou une réservation en cours garde le prix du moment de la vente.</p>
        {fares === null ? <Loading /> : fares.length === 0 ? <EmptyState title="Aucun tronçon" text="La grille des prix n’est pas encore chargée." /> : (
          <div className="table-scroll">
            <table className="staff-table min-w-[620px]">
              <thead><tr><th>Tronçon</th><th>Prix actuel</th><th>Nouveau prix</th><th /></tr></thead>
              <tbody>
                {fares.map((fare) => (
                  <tr key={fare.id}>
                    <td className="strong">{fare.label}</td>
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

function TeamPanel({ users, onChanged }: { users: User[]; onChanged: () => Promise<void> }) {
  const feedback = useActionFeedback();
  const [form, setForm] = useState({ username: "", password: "", first_name: "", last_name: "", phone: "", role: "COUNTER" });

  async function submit(event: FormEvent) {
    event.preventDefault();
    try {
      await apiFetch("/users/", { method: "POST", body: JSON.stringify(form) });
      feedback.success(`Membre ${form.username} ajouté.`);
      await onChanged();
    } catch (reason) { feedback.failure(reason, "Le membre n’a pas été ajouté."); }
  }

  return (
    <div className="grid gap-5 xl:grid-cols-[1.25fr_.75fr]">
      <section className="card self-start">
        <SectionHeading eyebrow="RBAC" title="Équipe Axis" />
        <div className="table-scroll">
          <table className="staff-table min-w-[600px]">
            <thead><tr><th>Nom</th><th>Identifiant</th><th>Rôle</th><th>Contact</th></tr></thead>
            <tbody>
              {users.map((user) => (
                <tr key={user.id}>
                  <td className="strong">{[user.first_name, user.last_name].filter(Boolean).join(" ") || "—"}</td>
                  <td>{user.username}</td>
                  <td><StatusBadge tone={user.role === "ADMIN" ? "amber" : user.role === "CLIENT" ? "grey" : "blue"}>{user.role_display}</StatusBadge></td>
                  <td>{user.phone || user.email || "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
      <form onSubmit={submit} className="card space-y-4">
        <SectionHeading eyebrow="Accès limité" title="Ajouter un membre" />
        <Input label="Identifiant" value={form.username} onChange={(value) => setForm({ ...form, username: value })} />
        <Input label="Mot de passe initial" type="password" value={form.password} onChange={(value) => setForm({ ...form, password: value })} />
        <Input label="Prénom" value={form.first_name} onChange={(value) => setForm({ ...form, first_name: value })} required={false} />
        <Input label="Nom" value={form.last_name} onChange={(value) => setForm({ ...form, last_name: value })} required={false} />
        <Input label="Téléphone" value={form.phone} onChange={(value) => setForm({ ...form, phone: value })} required={false} />
        <Select label="Rôle" value={form.role} onChange={(value) => setForm({ ...form, role: value })} options={[["COUNTER", "Guichetier"], ["CONTROLLER", "Contrôleur"], ["ADMIN", "Administrateur"], ["CLIENT", "Client"]]} />
        <button className="primary-button w-full">Créer le compte</button>
      </form>
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
