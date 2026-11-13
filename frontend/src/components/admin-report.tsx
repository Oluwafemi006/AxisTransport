"use client";

import { useCallback, useEffect, useState } from "react";
import { apiFetch, formatDate, money } from "@/lib/api";
import { beninDateKey, reportPeriodError } from "@/lib/portal-rules";
import { Loading, Notice, SectionHeading } from "./ui";
import type { NoticeState } from "./ui";

// Chiffres calculés par le serveur (apps/core/reporting.py) : le site n'en recalcule aucun.
export type Headline = {
  tickets_sold: number;
  tickets_scanned: number;
  tickets_refunded: number;
  gross_revenue: number;
  parcels: { tracked: number; cancelled: number; picked_up: number };
};

type Report = {
  period: { start: string; end: string };
  default_start: string;
  all_time_start: string;
  headline: Headline;
  revenue: { tickets: number; parcels: number; rentals: number; mobile_money: number; cash_or_other: number; total: number };
  rentals: { requested: number; by_status: Array<{ status: string; label: string; count: number }>; planned_amount: number };
  days: Array<{ date: string; tickets_sold: number; tickets_scanned: number; tickets_refunded: number; gross_revenue: number; parcels_tracked: number }>;
  trips: Array<{ id: number; label: string; departure_at: string; status_display: string; capacity: number | null; tickets_sold: number; tickets_scanned: number; gross_revenue: number }>;
  agents: Array<{ id: number; name: string; role: string; tickets_sold: number; tickets_scanned: number; parcels_registered: number; cash_fcfa: number; mobile_money_fcfa: number }>;
};

export const GROSS_REVENUE_LABEL = "Encaissements bruts (remboursements non déduits)";

const roleLabels: Record<string, string> = { COUNTER: "Guichet", CONTROLLER: "Contrôleur", ADMIN: "Administrateur" };

function dayLabel(key: string) {
  return new Date(`${key}T00:00:00`).toLocaleDateString("fr-FR", { weekday: "short", day: "2-digit", month: "2-digit", year: "numeric" });
}

// Les cartes principales, partagées par l'accueil (aujourd'hui, cumul) et le bilan (période).
export function HeadlineCards({ data }: { data: Headline }) {
  const cards: Array<[string, string, string?]> = [
    ["Billets vendus", String(data.tickets_sold)],
    ["Billets scannés", String(data.tickets_scanned)],
    ["Colis suivis", String(data.parcels.tracked), `${data.parcels.cancelled} annulé${data.parcels.cancelled > 1 ? "s" : ""}`],
    [GROSS_REVENUE_LABEL, money(data.gross_revenue), `${data.tickets_refunded} billet${data.tickets_refunded > 1 ? "s" : ""} remboursé${data.tickets_refunded > 1 ? "s" : ""}`],
  ];
  return (
    <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
      {cards.map(([label, value, note]) => (
        <div key={label} className="card">
          <p className="field-label">{label}</p>
          <p className="stat-value">{value}</p>
          {note && <p className="text-sm" style={{ color: "var(--mute)", marginTop: 4 }}>{note}</p>}
        </div>
      ))}
    </div>
  );
}

export function ReportPanel() {
  const today = beninDateKey();
  const [start, setStart] = useState("");
  const [end, setEnd] = useState(today);
  const [report, setReport] = useState<Report | null>(null);
  const [notice, setNotice] = useState<NoticeState | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async (params?: { start: string; end: string }) => {
    setBusy(true);
    setNotice(null);
    try {
      const query = params ? `?${new URLSearchParams(params).toString()}` : "";
      const data = await apiFetch<Report>(`/dashboard/report/${query}`);
      setReport(data);
      setStart(data.period.start);
      setEnd(data.period.end);
    } catch {
      setNotice({ text: "Impossible de charger le bilan.", tone: "error" });
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  function submit() {
    const problem = reportPeriodError(start, end, today);
    if (problem) { setNotice({ text: problem, tone: "error" }); return; }
    void load({ start, end });
  }

  return (
    <div className="space-y-5">
      <section className="card">
        <SectionHeading eyebrow="Jours entiers, heure du Bénin" title="Bilan global" />
        <div className="grid gap-3 sm:grid-cols-[1fr_1fr_auto] sm:items-end">
          <div className="f">
            <label htmlFor="report-start">Du</label>
            <input id="report-start" type="date" value={start} max={today} onChange={(e) => setStart(e.target.value)} />
          </div>
          <div className="f">
            <label htmlFor="report-end">Au</label>
            <input id="report-end" type="date" value={end} max={today} onChange={(e) => setEnd(e.target.value)} />
          </div>
          <button type="button" className="btn p" disabled={busy} onClick={submit}>{busy ? "Patientez…" : "Afficher"}</button>
        </div>
        {report && (
          <p className="text-sm" style={{ color: "var(--mute)", marginTop: 10 }}>
            Début proposé : création du plus ancien compte administrateur ({dayLabel(report.default_start)}).{" "}
            <button type="button" className="underline" disabled={busy} onClick={() => void load({ start: report.all_time_start, end: today })}>
              Cumul global depuis le premier jour connu ({dayLabel(report.all_time_start)})
            </button>
          </p>
        )}
        {notice && <Notice notice={notice} />}
      </section>

      {!report ? <Loading /> : (
        <>
          <HeadlineCards data={report.headline} />

          <div className="grid gap-5 lg:grid-cols-2">
            <section className="card">
              <SectionHeading eyebrow="Transactions réussies, à leur date" title="Encaissements par canal" />
              <dl className="space-y-2 text-sm">
                <Row label="Billets">{money(report.revenue.tickets)}</Row>
                <Row label="Colis">{money(report.revenue.parcels)}</Row>
                <Row label="Locations">{money(report.revenue.rentals)}</Row>
                <Row label="Mobile Money (en ligne)">{money(report.revenue.mobile_money)}</Row>
                <Row label="Espèces et autres">{money(report.revenue.cash_or_other)}</Row>
                <Row label="Total brut" strong>{money(report.revenue.total)}</Row>
              </dl>
            </section>
            <section className="card">
              <SectionHeading eyebrow="Demandes créées sur la période" title="Locations" />
              <dl className="space-y-2 text-sm">
                <Row label="Demandes">{String(report.rentals.requested)}</Row>
                {report.rentals.by_status.map((row) => <Row key={row.status} label={row.label}>{String(row.count)}</Row>)}
                <Row label="Montant prévu (hors annulées, non encaissé)" strong>{money(report.rentals.planned_amount)}</Row>
              </dl>
            </section>
          </div>

          <section className="card">
            <SectionHeading eyebrow="Chiffres agrégés, sans passager" title="Activité par agent" />
            {report.agents.length === 0 ? <p className="text-sm">Aucune activité du personnel sur la période.</p> : (
              <div className="table-scroll">
                <table className="staff-table min-w-[640px]">
                  <thead><tr><th>Agent</th><th>Rôle</th><th>Billets vendus</th><th>Billets scannés</th><th>Colis enregistrés</th><th>Espèces</th><th>Mobile Money</th></tr></thead>
                  <tbody>
                    {report.agents.map((row) => (
                      <tr key={row.id}>
                        <td className="strong">{row.name}</td><td>{roleLabels[row.role] ?? row.role}</td>
                        <td>{row.tickets_sold}</td><td>{row.tickets_scanned}</td><td>{row.parcels_registered}</td>
                        <td>{money(row.cash_fcfa)}</td><td>{money(row.mobile_money_fcfa)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>

          <section className="card">
            <SectionHeading eyebrow="Date de départ sur la période" title="Détail par trajet" />
            {report.trips.length === 0 ? <p className="text-sm">Aucun départ sur la période.</p> : (
              <div className="table-scroll">
                <table className="staff-table min-w-[640px]">
                  <thead><tr><th>Trajet</th><th>Départ</th><th>Statut</th><th>Vendus / capacité</th><th>Scannés</th><th>Encaissé (brut)</th></tr></thead>
                  <tbody>
                    {report.trips.map((trip) => (
                      <tr key={trip.id}>
                        <td className="strong">{trip.label}</td><td>{formatDate(trip.departure_at)}</td><td>{trip.status_display}</td>
                        <td>{trip.capacity ? `${trip.tickets_sold} / ${trip.capacity}` : String(trip.tickets_sold)}</td>
                        <td>{trip.tickets_scanned}</td><td>{money(trip.gross_revenue)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>

          <section className="card">
            <SectionHeading eyebrow="Du plus ancien au plus récent" title="Détail jour par jour" />
            <div className="table-scroll">
              <table className="staff-table min-w-[640px]">
                <thead><tr><th>Jour</th><th>Billets vendus</th><th>Billets scannés</th><th>Remboursés</th><th>Colis suivis</th><th>Encaissé (brut)</th></tr></thead>
                <tbody>
                  {report.days.map((day) => (
                    <tr key={day.date}>
                      <td className="strong">{dayLabel(day.date)}</td><td>{day.tickets_sold}</td><td>{day.tickets_scanned}</td>
                      <td>{day.tickets_refunded}</td><td>{day.parcels_tracked}</td><td>{money(day.gross_revenue)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        </>
      )}
    </div>
  );
}

function Row({ label, children, strong = false }: { label: string; children: string; strong?: boolean }) {
  return (
    <div className="flex justify-between gap-3">
      <dt style={{ color: "var(--mute)" }}>{label}</dt>
      <dd className={strong ? "font-bold" : ""}>{children}</dd>
    </div>
  );
}
