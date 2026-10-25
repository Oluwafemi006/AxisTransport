"use client";

import { Seat } from "@/lib/types";
import { groupSeatsYutong } from "@/lib/portal-rules";

export interface BusSeatMapProps {
  seats: Seat[];
  selectedSeatIds: number[];
  onToggleSeat: (seat: Seat) => void;
  maxSeats?: number;
  disabled?: boolean;
}

export function BusSeatMap({
  seats,
  selectedSeatIds,
  onToggleSeat,
  maxSeats = 8,
  disabled = false,
}: BusSeatMapProps) {
  const rows = groupSeatsYutong(seats);

  return (
    <div className="bus-layout-container" style={{ marginTop: "20px" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "8px" }}>
        <label style={{ margin: 0, fontWeight: 700 }}>Plan des sièges (Car Yutong)</label>
        <span style={{ fontSize: "12px", color: "var(--mute)" }}>
          {selectedSeatIds.length > 0
            ? `${selectedSeatIds.length} place${selectedSeatIds.length > 1 ? "s" : ""} sélectionnée${selectedSeatIds.length > 1 ? "s" : ""} (max. ${maxSeats})`
            : `Choisissez jusqu’à ${maxSeats} places`}
        </span>
      </div>

      <div
        style={{
          border: "2px solid var(--line)",
          borderRadius: "16px",
          padding: "16px",
          background: "#fff",
          maxWidth: "460px",
          margin: "0 auto",
        }}
      >
        {/* Avant du bus */}
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            padding: "8px 12px",
            background: "var(--tint)",
            borderRadius: "10px",
            color: "var(--navy)",
            fontSize: "12px",
            fontWeight: 700,
            letterSpacing: "0.05em",
            marginBottom: "16px",
          }}
        >
          <span>AVANT DU CAR</span>
          <span style={{ fontSize: "16px" }}>🚌 CHAUFFEUR</span>
        </div>

        {/* Grille des rangées Yutong : 2 sièges | allée | 2 sièges */}
        <div style={{ display: "flex", flexDirection: "column", gap: "10px" }}>
          {rows.map((row) => (
            <div
              key={row.rowNumber}
              style={{
                display: "grid",
                gridTemplateColumns: "1fr 1fr 32px 1fr 1fr",
                gap: "8px",
                alignItems: "center",
              }}
            >
              {/* 2 Sièges Gauche */}
              {row.left.map((seat) => renderSeatButton(seat))}
              {row.left.length < 2 &&
                Array.from({ length: 2 - row.left.length }).map((_, i) => (
                  <div key={`empty-left-${i}`} style={{ aspectRatio: "1/1" }} />
                ))}

              {/* Allée Centrale */}
              {row.aisleExtra ? (
                renderSeatButton(row.aisleExtra)
              ) : (
                <div
                  style={{
                    height: "100%",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    color: "var(--line)",
                    fontSize: "10px",
                    userSelect: "none",
                  }}
                  title="Allée centrale"
                >
                  ·
                </div>
              )}

              {/* 2 Sièges Droite */}
              {row.right.map((seat) => renderSeatButton(seat))}
              {row.right.length < 2 &&
                Array.from({ length: 2 - row.right.length }).map((_, i) => (
                  <div key={`empty-right-${i}`} style={{ aspectRatio: "1/1" }} />
                ))}
            </div>
          ))}
        </div>

        {/* Légende du plan */}
        <div
          style={{
            display: "flex",
            justifyContent: "center",
            gap: "16px",
            marginTop: "16px",
            paddingTop: "12px",
            borderTop: "1px solid var(--line)",
            fontSize: "12px",
            color: "var(--mute)",
            flexWrap: "wrap",
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
            <span
              style={{
                width: "14px",
                height: "14px",
                background: "#fff",
                border: "1px solid var(--line)",
                borderRadius: "4px",
                display: "inline-block",
              }}
            />
            <span>Libre</span>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
            <span
              style={{
                width: "14px",
                height: "14px",
                background: "var(--blue)",
                borderRadius: "4px",
                display: "inline-block",
              }}
            />
            <span>Sélectionné</span>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
            <span
              style={{
                width: "14px",
                height: "14px",
                background: "var(--bg)",
                border: "1px solid var(--line)",
                borderRadius: "4px",
                display: "inline-block",
              }}
            />
            <span>Occupé</span>
          </div>
        </div>
      </div>
    </div>
  );

  function renderSeatButton(seat: Seat) {
    const free = seat.status === "AVAILABLE";
    const chosen = selectedSeatIds.includes(seat.id);
    const canSelect = free && (chosen || selectedSeatIds.length < maxSeats);

    return (
      <button
        type="button"
        key={seat.id}
        disabled={disabled || !free || (!chosen && selectedSeatIds.length >= maxSeats)}
        onClick={() => onToggleSeat(seat)}
        title={chosen ? `Siège ${seat.number} sélectionné` : free ? `Siège ${seat.number} libre` : `Siège ${seat.number} (${seat.status_display})`}
        aria-pressed={chosen}
        style={{
          aspectRatio: "1/1",
          borderRadius: "8px",
          fontWeight: 700,
          fontSize: "13px",
          border: chosen ? "2px solid var(--blue)" : "1px solid var(--line)",
          background: chosen ? "var(--blue)" : free ? "#fff" : "var(--bg)",
          color: chosen ? "#fff" : free ? "var(--ink)" : "var(--mute)",
          cursor: !free ? "not-allowed" : canSelect ? "pointer" : "not-allowed",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          transition: "all 0.15s ease",
          boxShadow: chosen ? "0 2px 6px rgba(47, 111, 237, 0.3)" : "none",
        }}
      >
        {seat.number}
      </button>
    );
  }
}
