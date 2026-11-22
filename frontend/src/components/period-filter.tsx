"use client";

import { type ListPeriod } from "@/lib/portal-rules";

// Sélecteur commun aux listes Billets, Colis et Locations (heure du Bénin, filtré par le serveur).
export function PeriodFilter({ value, onChange, statuses, status, onStatus }: {
  value: ListPeriod;
  onChange: (next: ListPeriod) => void;
  statuses: Array<[string, string]>;
  status: string;
  onStatus: (next: string) => void;
}) {
  return (
    <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4 lg:items-end">
      <label className="block"><span className="field-label">Jours</span>
        <select className="field" value={value.mode} onChange={(e) => onChange({ ...value, mode: e.target.value as ListPeriod["mode"] })}>
          <option value="day">Un jour</option>
          <option value="period">Une période</option>
          <option value="all">Tous les jours</option>
        </select>
      </label>
      {value.mode === "day" && (
        <label className="block"><span className="field-label">Jour</span>
          <input className="field" type="date" value={value.day} onChange={(e) => onChange({ ...value, day: e.target.value })} />
        </label>
      )}
      {value.mode === "period" && (
        <>
          <label className="block"><span className="field-label">Du</span>
            <input className="field" type="date" value={value.start} onChange={(e) => onChange({ ...value, start: e.target.value })} />
          </label>
          <label className="block"><span className="field-label">Au</span>
            <input className="field" type="date" value={value.end} onChange={(e) => onChange({ ...value, end: e.target.value })} />
          </label>
        </>
      )}
      <label className="block"><span className="field-label">Statut</span>
        <select className="field" value={status} onChange={(e) => onStatus(e.target.value)}>
          <option value="">Tous les statuts</option>
          {statuses.map(([key, label]) => <option key={key} value={key}>{label}</option>)}
        </select>
      </label>
    </div>
  );
}
