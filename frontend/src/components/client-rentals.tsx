"use client";

import { useEffect, useRef, useState, type FormEvent } from "react";
import { apiFetch, formatDate, money } from "@/lib/api";
import { beninDateKey, beninDateTimeToIso, rentalDailyRate, rentalDays, rentalFormulas, rentalPeriodError, rentalIdentityError, rentalStatusTone, type RentalIdentity } from "@/lib/portal-rules";
import type { RentalBooking, User, Vehicle } from "@/lib/types";
import { CarIcon } from "./icons";
import { LoginCard } from "./login-card";
import { RentalIdentityFields, emptyRentalIdentity } from "./rental-identity-fields";

// Location de véhicules : même parcours que l'application (mobile-flutter/lib/features/rentals/rentals_screen.dart).
// Tarifs, formules et disponibilité viennent de la Flotte (serveur). Le site ne calcule aucun montant :
// l'API ne fournit ni estimation, ni conditions, ni caution (voir le rapport de la tâche cc/web-location-controleur).

// Demain 08:00 → +2 jours, comme l'application (rentals_screen.dart, initState).
function defaultPeriod() {
  const tomorrow = new Date(`${beninDateKey()}T00:00:00Z`);
  tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
  const end = new Date(tomorrow);
  end.setUTCDate(end.getUTCDate() + 2);
  const day = (value: Date) => value.toISOString().slice(0, 10);
  return { start: `${day(tomorrow)}T08:00`, end: `${day(end)}T08:00` };
}

function vehicleSpecs(vehicle: Vehicle): string {
  return [
    vehicle.capacity ? `${vehicle.capacity} places` : "",
    vehicle.description?.trim() ?? "",
    vehicle.base_location_detail?.name?.trim() ?? "",
  ].filter(Boolean).join(" · ");
}

function rateLabel(rate: string | null): string {
  return rate === null ? "À renseigner" : `${money(rate)} / jour`;
}

export function Rentals({ user, vehicles, rentals, onAuthenticated, onChanged }: {
  user: User | null;
  vehicles: Vehicle[];
  rentals: RentalBooking[];
  onAuthenticated: () => Promise<void>;
  onChanged: () => Promise<void>;
}) {
  const [selected, setSelected] = useState<Vehicle | null>(null);
  const [notice, setNotice] = useState("");

  if (selected) {
    return (
      <RentalRequest
        vehicle={selected}
        user={user}
        onAuthenticated={onAuthenticated}
        onBack={() => { setSelected(null); window.scrollTo({ top: 0 }); }}
        onSent={async (message) => { setSelected(null); setNotice(message); await onChanged(); }}
      />
    );
  }

  return (
    <div className="rental-layout">
      <div className="card">
        <h3>Véhicules disponibles</h3>
        <p style={{ color: "var(--mute)", marginTop: "6px" }}>Choisissez la formule, puis le véhicule disponible.</p>
        <hr style={{ border: 0, borderBottom: "1px solid var(--line)", margin: "16px 0" }} />
        {notice && <p role="status" className="rental-notice">{notice}</p>}
        {vehicles.length === 0 ? (
          <div>
            <p style={{ fontWeight: 700, color: "var(--navy)" }}>Bientôt disponible</p>
            <p style={{ color: "var(--mute)" }}>Aucun véhicule n’est disponible à la location pour le moment.</p>
          </div>
        ) : (
          <div style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
            {vehicles.map((vehicle) => {
              const formulas = rentalFormulas(vehicle);
              return (
                <div key={vehicle.id} className="rental-vehicle" style={{ opacity: vehicle.rentable === false ? 0.7 : 1 }}>
                  {vehicle.photo_url
                    ? <img src={vehicle.photo_url} alt={vehicle.name} className="rental-photo" />
                    : <div aria-label="Pas de photo" className="rental-photo rental-photo-empty"><CarIcon size={40} /></div>}
                  <h4 style={{ color: "var(--navy)", marginTop: "12px" }}>{vehicle.name}</h4>
                  {(vehicle.brand || vehicle.model_name) && <p style={{ fontSize: "13px" }}>{[vehicle.brand, vehicle.model_name].filter(Boolean).join(" ")}</p>}
                  {vehicleSpecs(vehicle) && <p style={{ fontSize: "13px", color: "var(--mute)" }}>{vehicleSpecs(vehicle)}</p>}
                  <p style={{ fontSize: "13px", color: "var(--mute)", marginTop: "4px" }}>
                    {[
                      formulas.selfDrive ? `Sans chauffeur : ${rateLabel(rentalDailyRate(vehicle, false))}` : "",
                      formulas.withDriver
                        ? `${formulas.selfDrive ? "Avec chauffeur" : "Avec chauffeur uniquement"} : ${rateLabel(rentalDailyRate(vehicle, true))}`
                        : "",
                    ].filter(Boolean).join(" · ")}
                  </p>
                  <div style={{ marginTop: "12px" }}>
                    {vehicle.rentable === false
                      ? <span className="pill ex">Indisponible</span>
                      : <button type="button" className="btn s p" onClick={() => { setNotice(""); setSelected(vehicle); }}>Réserver</button>}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      <div className="card">
        <h3>Mes demandes</h3>
        <hr style={{ border: 0, borderBottom: "1px solid var(--line)", margin: "16px 0" }} />
        {!user ? <LoginCard title="Connectez-vous" allowRegistration onSuccess={() => void onAuthenticated()} /> : rentals.length === 0 ? <p style={{ color: "var(--mute)" }}>Aucune demande en cours.</p> : (
          <div style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
            {rentals.map((rental) => (
              <div key={rental.id} className="rental-request">
                <div style={{ display: "flex", justifyContent: "space-between", gap: "8px", alignItems: "flex-start" }}>
                  <b style={{ color: "var(--navy)" }}>{rental.vehicle_detail.name} · {rental.reference}</b>
                  <span className={`pill rental-${rentalStatusTone(rental.status)}`}>{rental.status_display || rental.status}</span>
                </div>
                <p style={{ fontSize: "13px", marginTop: "6px" }}>{formatDate(rental.starts_at)} → {formatDate(rental.ends_at)}</p>
                <p style={{ fontSize: "12px", color: "var(--mute)", marginTop: "2px" }}>{rental.with_driver ? "Avec chauffeur" : "Sans chauffeur"}</p>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function RentalRequest({ vehicle, user, onAuthenticated, onBack, onSent }: {
  vehicle: Vehicle;
  user: User | null;
  onAuthenticated: () => Promise<void>;
  onBack: () => void;
  onSent: (message: string) => Promise<void>;
}) {
  const formulas = rentalFormulas(vehicle);
  const initial = defaultPeriod();
  const [withDriver, setWithDriver] = useState(formulas.defaultWithDriver || !formulas.selfDrive);
  const [startsAt, setStartsAt] = useState(initial.start);
  const [endsAt, setEndsAt] = useState(initial.end);
  const [error, setError] = useState("");
  const [sending, setSending] = useState(false);
  const [identity, setIdentity] = useState<RentalIdentity>(() => ({ ...emptyRentalIdentity, renter_full_name: [user?.first_name, user?.last_name].filter(Boolean).join(" ") }));
  const today = beninDateKey();
  const periodError = rentalPeriodError(startsAt, endsAt, today);
  const days = rentalDays(startsAt, endsAt);
  const rate = rentalDailyRate(vehicle, withDriver);
  // Constaté sur téléphone : la page gardait sa position et l'on arrivait au milieu de la fiche.
  const sheet = useRef<HTMLDivElement>(null);
  useEffect(() => { sheet.current?.scrollIntoView({ block: "start" }); }, []);

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (periodError) { setError(periodError); return; }
    const missing = rentalIdentityError(identity);
    if (missing) { setError(missing); return; }
    setSending(true); setError("");
    try {
      const rental = await apiFetch<RentalBooking>("/client/rentals/", {
        method: "POST",
        body: JSON.stringify({ vehicle: vehicle.id, starts_at: beninDateTimeToIso(startsAt), ends_at: beninDateTimeToIso(endsAt), with_driver: withDriver, ...identity, zone: Number(identity.zone) }),
      });
      await onSent(`Demande ${rental.reference} envoyée (${rental.status_display}).`);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "La demande n’a pas pu être envoyée.");
      setSending(false);
    }
  }

  return (
    <div ref={sheet} className="card rental-sheet">
      <button type="button" className="text-button" onClick={onBack}>← Véhicules</button>
      {vehicle.photo_url && <img src={vehicle.photo_url} alt={vehicle.name} className="rental-photo" style={{ marginTop: "12px" }} />}
      <h3 style={{ marginTop: "12px" }}>{vehicle.name}</h3>
      {vehicleSpecs(vehicle) && <p style={{ fontSize: "13px", color: "var(--mute)" }}>{vehicleSpecs(vehicle)}</p>}

      {!user ? (
        <div style={{ marginTop: "20px" }}>
          <LoginCard title="Connectez-vous pour envoyer la demande" allowRegistration onSuccess={() => void onAuthenticated()} />
        </div>
      ) : (
        <form onSubmit={submit}>
          <p className="rental-label">FORMULE</p>
          <div className="rental-choices">
            <button type="button" className={`rental-choice${!withDriver ? " on" : ""}`} disabled={!formulas.selfDrive} aria-pressed={!withDriver} onClick={() => setWithDriver(false)}>
              <b>Sans chauffeur</b>
              <span>{formulas.selfDrive ? "Vous conduisez" : "Non disponible"}</span>
              {formulas.selfDrive && <strong>{rateLabel(rentalDailyRate(vehicle, false))}</strong>}
            </button>
            <button type="button" className={`rental-choice${withDriver ? " on" : ""}`} disabled={!formulas.withDriver} aria-pressed={withDriver} onClick={() => setWithDriver(true)}>
              <b>Avec chauffeur</b>
              <span>{formulas.withDriver ? "Chauffeur Axis inclus" : "Non disponible"}</span>
              {formulas.withDriver && <strong>{rateLabel(rentalDailyRate(vehicle, true))}</strong>}
            </button>
          </div>

          <p className="rental-label">DATES</p>
          <div className="f">
            <label htmlFor="rental-start">PRISE DU VÉHICULE</label>
            <input id="rental-start" type="datetime-local" value={startsAt} min={`${today}T00:00`} onChange={(e) => setStartsAt(e.target.value)} required />
          </div>
          <div className="f" style={{ marginTop: "10px" }}>
            <label htmlFor="rental-end">RETOUR DU VÉHICULE</label>
            <input id="rental-end" type="datetime-local" value={endsAt} min={startsAt || `${today}T00:00`} onChange={(e) => setEndsAt(e.target.value)} required />
          </div>
          <p style={{ fontSize: "12px", color: "var(--mute)", marginTop: "6px" }}>Heure du Bénin.</p>
          {periodError && <p className="rental-error">{periodError}</p>}

          <p className="rental-label">CONDUCTEUR</p>
          <RentalIdentityFields value={identity} onChange={(next) => { setIdentity(next); setError(""); }} />

          <p className="rental-info">Aucun paiement maintenant. L’agence vous appelle pour confirmer, puis vous réglez à la remise du véhicule.</p>

          <div className="rental-footer">
            <div>
              <p className="rental-label" style={{ margin: 0 }}>Durée · {days} {days > 1 ? "jours" : "jour"}</p>
              <p style={{ fontWeight: 800, color: "var(--navy)" }}>Tarif / jour : {rate === null ? "À renseigner" : money(rate)}</p>
            </div>
            <button className="btn p" disabled={sending || periodError !== null}>{sending ? "Envoi…" : "Envoyer la demande"}</button>
          </div>
          {error && <p className="rental-error">{error}</p>}
        </form>
      )}
    </div>
  );
}
