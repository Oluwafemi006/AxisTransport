"use client";

export interface PassengerItem {
  seatId: number | null;
  seatNumber: string | null;
  fullName: string;
  phone: string;
}

export interface PassengerFormProps {
  passengers: PassengerItem[];
  onPassengerChange: (index: number, field: "fullName" | "phone", value: string) => void;
  onAddPassenger?: () => void;
  onRemovePassenger?: (index: number) => void;
  onClearSeat?: (index: number) => void;
  maxPassengers?: number;
  contactPhone: string;
  onContactPhoneChange: (value: string) => void;
  buyerIfu: string;
  onBuyerIfuChange: (value: string) => void;
  isUserLoggedIn: boolean;
}

export function PassengerForm({
  passengers,
  onPassengerChange,
  onAddPassenger,
  onRemovePassenger,
  onClearSeat,
  maxPassengers = 8,
  contactPhone,
  onContactPhoneChange,
  buyerIfu,
  onBuyerIfuChange,
  isUserLoggedIn,
}: PassengerFormProps) {
  return (
    <div style={{ marginTop: "20px" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "10px", flexWrap: "wrap", gap: "8px" }}>
        <label style={{ fontSize: "14px", fontWeight: 700, margin: 0 }}>
          Passagers ({passengers.length} billet{passengers.length > 1 ? "s" : ""})
        </label>
        {onAddPassenger && passengers.length < maxPassengers && (
          <button
            type="button"
            className="btn s"
            onClick={onAddPassenger}
            style={{ fontSize: "12px", padding: "6px 12px" }}
          >
            + Ajouter un passager
          </button>
        )}
      </div>

      <div style={{ display: "flex", flexDirection: "column", gap: "14px" }}>
        {passengers.map((passenger, index) => (
          <div
            key={`pax-${index}-${passenger.seatId ?? "auto"}`}
            style={{
              border: "1px solid var(--line)",
              borderRadius: "12px",
              padding: "14px",
              background: "#fff",
              boxShadow: "0 1px 3px rgba(0,0,0,0.03)",
            }}
          >
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                marginBottom: "12px",
                paddingBottom: "8px",
                borderBottom: "1px solid var(--line)",
                flexWrap: "wrap",
                gap: "8px",
              }}
            >
              <span style={{ fontWeight: 700, fontSize: "14px", color: "var(--ink)" }}>
                Passager {index + 1}
              </span>
              <div style={{ display: "flex", alignItems: "center", gap: "8px", flexWrap: "wrap" }}>
                {passenger.seatId !== null && passenger.seatNumber ? (
                  <span
                    style={{
                      background: "var(--tint)",
                      color: "var(--navy)",
                      padding: "4px 10px",
                      borderRadius: "999px",
                      fontSize: "12px",
                      fontWeight: 700,
                      display: "inline-flex",
                      alignItems: "center",
                      gap: "6px",
                    }}
                  >
                    Siège N° {passenger.seatNumber} (préférence)
                    {onClearSeat && (
                      <button
                        type="button"
                        onClick={() => onClearSeat(index)}
                        title="Retirer ce choix (attribution automatique)"
                        style={{
                          background: "none",
                          border: "none",
                          color: "var(--navy)",
                          cursor: "pointer",
                          fontWeight: 900,
                          padding: 0,
                          lineHeight: 1,
                        }}
                      >
                        ×
                      </button>
                    )}
                  </span>
                ) : (
                  <span
                    style={{
                      background: "var(--bg)",
                      color: "var(--mute)",
                      border: "1px solid var(--line)",
                      padding: "4px 10px",
                      borderRadius: "999px",
                      fontSize: "12px",
                      fontWeight: 600,
                    }}
                  >
                    Places attribuées après paiement
                  </span>
                )}
                {onRemovePassenger && passengers.length > 1 && (
                  <button
                    type="button"
                    onClick={() => onRemovePassenger(index)}
                    style={{
                      background: "none",
                      border: "1px solid var(--line)",
                      borderRadius: "6px",
                      color: "#B42318",
                      cursor: "pointer",
                      fontSize: "11px",
                      padding: "3px 8px",
                    }}
                  >
                    Retirer
                  </button>
                )}
              </div>
            </div>

            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "10px" }} className="passenger-row-grid">
              <div>
                <label style={{ fontSize: "12px", color: "var(--mute)", display: "block", marginBottom: "4px" }}>
                  Nom et prénom du passager *
                </label>
                <input
                  type="text"
                  placeholder="Ex. Koffi Mensah"
                  value={passenger.fullName}
                  onChange={(e) => onPassengerChange(index, "fullName", e.target.value)}
                  required
                  style={{ width: "100%" }}
                />
              </div>

              <div>
                <label style={{ fontSize: "12px", color: "var(--mute)", display: "block", marginBottom: "4px" }}>
                  Téléphone (facultatif)
                </label>
                <input
                  type="tel"
                  placeholder="Ex. +229 01 97 00 00 00"
                  value={passenger.phone}
                  onChange={(e) => onPassengerChange(index, "phone", e.target.value)}
                  style={{ width: "100%" }}
                />
              </div>
            </div>
          </div>
        ))}
      </div>

      <div style={{ marginTop: "20px", borderTop: "1px solid var(--line)", paddingTop: "16px" }}>
        <label style={{ fontSize: "13px", fontWeight: 700, display: "block", marginBottom: "6px" }}>
          Numéro de contact principal {!isUserLoggedIn && "(obligatoire pour recevoir vos billets)"}
        </label>
        <input
          type="tel"
          placeholder="Ex. +229 01 97 00 00 00"
          value={contactPhone}
          onChange={(e) => onContactPhoneChange(e.target.value)}
          required={!isUserLoggedIn}
          pattern={isUserLoggedIn ? undefined : "\\+?[0-9\\(][0-9 \\(\\)\\.\\-]{5,}"}
          title="Numéro de téléphone"
          style={{ width: "100%" }}
        />

        <label style={{ fontSize: "13px", fontWeight: 700, display: "block", marginTop: "14px", marginBottom: "6px" }}>
          IFU de l’acheteur (facultatif, imprimé sur le billet)
        </label>
        <input
          type="text"
          placeholder="Ex. 3200000000000"
          value={buyerIfu}
          onChange={(e) => onBuyerIfuChange(e.target.value)}
          maxLength={30}
          style={{ width: "100%" }}
        />
      </div>

      <style>{`
        @media(max-width: 640px) {
          .passenger-row-grid { grid-template-columns: 1fr !important; }
        }
      `}</style>
    </div>
  );
}
