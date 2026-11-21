"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";

import { apiFetch, apiList, formatDate } from "@/lib/api";
import { beninDateTimeToIso, rentalIdentityError, rentalPeriodError, beninDateKey, type RentalIdentity } from "@/lib/portal-rules";
import type { RentalBooking, Vehicle } from "@/lib/types";
import { RentalIdentityFields, emptyRentalIdentity } from "./rental-identity-fields";
import { EmptyState, SectionHeading, StatusBadge, useActionFeedback } from "./ui";

// Guichet : consulte les locations et enregistre une demande pour un client présent (compte retrouvé par téléphone).
// Statut, montants, véhicules et prix restent gérés par l'administrateur.
export function CounterRentals() {
  const feedback = useActionFeedback();
  const [rentals, setRentals] = useState<RentalBooking[] | null>(null);
  const [vehicles, setVehicles] = useState<Vehicle[]>([]);
  const [phone, setPhone] = useState("");
  const [vehicle, setVehicle] = useState("");
  const [withDriver, setWithDriver] = useState(false);
  const [startsAt, setStartsAt] = useState("");
  const [endsAt, setEndsAt] = useState("");
  const [identity, setIdentity] = useState<RentalIdentity>(emptyRentalIdentity);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const [rows, cars] = await Promise.all([apiList<RentalBooking>("/rentals/"), apiList<Vehicle>("/client/vehicles/", false)]);
      setRentals(rows);
      setVehicles(cars);
    } catch (reason) { feedback.failure(reason, "Les locations n’ont pas pu être chargées."); }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  useEffect(() => { void load(); }, [load]);

  async function submit(event: FormEvent) {
    event.preventDefault();
    const problem = !phone.trim() ? "Indiquez le téléphone du client." : !vehicle ? "Choisissez un véhicule."
      : rentalPeriodError(startsAt, endsAt, beninDateKey()) || rentalIdentityError(identity);
    if (problem) { feedback.failure(null, problem); return; }
    setBusy(true);
    try {
      const rental = await apiFetch<RentalBooking>("/rentals/counter/", {
        method: "POST",
        body: JSON.stringify({
          customer_phone: phone, vehicle: Number(vehicle), with_driver: withDriver,
          starts_at: beninDateTimeToIso(startsAt), ends_at: beninDateTimeToIso(endsAt), ...identity, zone: Number(identity.zone),
        }),
      });
      feedback.success(`Demande ${rental.reference} enregistrée pour le client.`);
      setPhone(""); setVehicle(""); setStartsAt(""); setEndsAt(""); setIdentity(emptyRentalIdentity); setWithDriver(false);
      await load();
    } catch (reason) { feedback.failure(reason, "La demande n’a pas été enregistrée."); }
    finally { setBusy(false); }
  }

  return (
    <section className="card mt-5">
      <SectionHeading eyebrow="Client présent au guichet" title="Locations" />
      <form onSubmit={submit} className="grid gap-3">
        <label className="block"><span className="field-label">Téléphone du compte client</span>
          <input className="field" inputMode="tel" value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="01 …" />
        </label>
        <label className="block"><span className="field-label">Véhicule</span>
          <select className="field" value={vehicle} onChange={(e) => setVehicle(e.target.value)}>
            <option value="">Choisir</option>
            {vehicles.map((car) => <option key={car.id} value={car.id}>{car.name}</option>)}
          </select>
        </label>
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={withDriver} onChange={(e) => setWithDriver(e.target.checked)} />Avec chauffeur</label>
        <div className="grid gap-3 sm:grid-cols-2">
          <label className="block"><span className="field-label">Prise du véhicule</span><input className="field" type="datetime-local" value={startsAt} onChange={(e) => setStartsAt(e.target.value)} /></label>
          <label className="block"><span className="field-label">Retour du véhicule</span><input className="field" type="datetime-local" value={endsAt} onChange={(e) => setEndsAt(e.target.value)} /></label>
        </div>
        <RentalIdentityFields value={identity} onChange={setIdentity} />
        <button className="primary-button" disabled={busy}>{busy ? "Enregistrement…" : "Enregistrer la demande"}</button>
      </form>
      <h3 className="mt-6 font-semibold">Demandes enregistrées</h3>
      {rentals === null ? null : rentals.length === 0 ? <EmptyState title="Aucune location" text="Les demandes apparaîtront ici." /> : (
        <ul className="mt-2 space-y-2">
          {rentals.map((rental) => (
            <li key={rental.id} className="rounded-lg border border-slate-200 p-3 text-sm">
              <div className="flex flex-wrap items-center gap-2">
                <p className="min-w-0 flex-1 break-words font-semibold">{rental.reference} · {rental.vehicle_detail?.name}</p>
                <StatusBadge tone={rental.status === "CANCELLED" ? "grey" : rental.status === "COMPLETED" ? "green" : "blue"}>{rental.status_display}</StatusBadge>
              </div>
              <p className="mt-1 text-slate-500 break-words">Du {formatDate(rental.starts_at)} au {formatDate(rental.ends_at)}{rental.renter_full_name ? ` · ${rental.renter_full_name}` : ""}{rental.zone_name ? ` · ${rental.zone_name}` : ""}</p>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
