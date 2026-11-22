"use client";

import { useEffect, useState } from "react";

import { apiList } from "@/lib/api";
import { RENTAL_IDENTITY_LABELS, type RentalIdentity } from "@/lib/portal-rules";

type Zone = { id: number; name: string };

export const emptyRentalIdentity: RentalIdentity = { renter_full_name: "", cip_number: "", licence_number: "", zone: "" };

// Champs communs à la demande en ligne et à la demande enregistrée au guichet ; zones saisies dans /admin.
export function RentalIdentityFields({ value, onChange }: { value: RentalIdentity; onChange: (next: RentalIdentity) => void }) {
  const [zones, setZones] = useState<Zone[] | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    apiList<Zone>("/rental-zones/", false).then(setZones).catch(() => setFailed(true));
  }, []);
  const text = (key: "renter_full_name" | "cip_number" | "licence_number", autoComplete?: string) => (
    <div className="f" style={{ marginTop: "10px" }}>
      <label htmlFor={`rental-${key}`}>{RENTAL_IDENTITY_LABELS[key].toUpperCase()}</label>
      <input id={`rental-${key}`} value={value[key]} autoComplete={autoComplete} onChange={(e) => onChange({ ...value, [key]: e.target.value })} required />
    </div>
  );
  return (
    <>
      {text("renter_full_name", "name")}
      {text("cip_number")}
      {text("licence_number")}
      <div className="f" style={{ marginTop: "10px" }}>
        <label htmlFor="rental-zone">{RENTAL_IDENTITY_LABELS.zone.toUpperCase()}</label>
        <select id="rental-zone" value={value.zone} onChange={(e) => onChange({ ...value, zone: e.target.value })} required>
          <option value="">{zones === null ? (failed ? "Liste indisponible" : "Chargement…") : zones.length ? "Choisir" : "À renseigner par l’agence"}</option>
          {(zones || []).map((zone) => <option key={zone.id} value={zone.id}>{zone.name}</option>)}
        </select>
      </div>
    </>
  );
}
