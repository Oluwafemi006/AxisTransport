"use client";

export interface PassengerItem {
  seatId: number;
  seatNumber: string;
  fullName: string;
  phone: string;
}

export interface PassengerFormProps {
  passengers: PassengerItem[];
  onPassengerChange: (index: number, field: "fullName" | "phone", value: string) => void;
  contactPhone: string;
  onContactPhoneChange: (value: string) => void;
  buyerIfu: string;
  onBuyerIfuChange: (value: string) => void;
  isUserLoggedIn: boolean;
}

export function PassengerForm({
  passengers,
  onPassengerChange,
  contactPhone,
  onContactPhoneChange,
  buyerIfu,
  onBuyerIfuChange,
  isUserLoggedIn,
}: PassengerFormProps) {
  if (passengers.length === 0) {
    return (
      <div
        style={{
          padding: "16px",
          background: "var(--bg)",
          borderRadius: "10px",
          border: "1px dashed var(--line)",
          textAlign: "center",
          color: "var(--mute)",
          marginTop: "16px",
          fontSize: "14px",
        }}
      >
        👆 Veuillez sélectionner au moins une place sur le plan pour renseigner les passagers.
      </div>
    );
  }

  return (
    <div style={{ marginTop: "20px" }}>
      <label style={{ fontSize: "14px", fontWeight: 700, display: "block", marginBottom: "10px" }}>
        Informations des passagers ({passengers.length} billet{passengers.length > 1 ? "s" : ""})
      </label>

      <div style={{ display: "flex", flexDirection: "column", gap: "14px" }}>
        {passengers.map((passenger, index) => (
          <div
            key={passenger.seatId}
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
              }}
            >
              <span style={{ fontWeight: 700, fontSize: "14px", color: "var(--ink)" }}>
                Passager {index + 1}
              </span>
              <span
                style={{
                  background: "var(--tint)",
                  color: "var(--navy)",
                  padding: "4px 10px",
                  borderRadius: "999px",
                  fontSize: "12px",
                  fontWeight: 700,
                }}
              >
                Siège N° {passenger.seatNumber}
              </span>
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
