"use client";

import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { QRCodeCanvas, QRCodeSVG } from "qrcode.react";
import { API_URL } from "@/lib/api";

interface PublicTicketData {
  reference: string;
  status: string;
  status_display: string;
  passenger_name: string;
  seat_label: string;
  origin: string;
  destination: string;
  departure_at: string | null;
  amount: number;
  currency: string;
  formatted_amount: string;
  qr_token: string;
  company_name: string;
  created_at: string;
}

export default function PublicTicketPage() {
  const params = useParams();
  const reference = params?.reference as string;

  const [ticket, setTicket] = useState<PublicTicketData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!reference) return;

    const endpoint = `${API_URL}/client/tickets/public/${encodeURIComponent(reference)}/`;

    fetch(endpoint)
      .then((res) => {
        if (!res.ok) {
          if (res.status === 404) {
            throw new Error("Billet introuvable ou invalide.");
          }
          throw new Error("Impossible de charger les informations du billet.");
        }
        return res.json();
      })
      .then((data) => {
        setTicket(data);
        setLoading(false);
      })
      .catch((err) => {
        setError(err.message || "Erreur lors du chargement du billet.");
        setLoading(false);
      });
  }, [reference]);

  const formatDate = (isoString: string | null) => {
    if (!isoString) return "Non précisée";
    try {
      const date = new Date(isoString);
      return new Intl.DateTimeFormat("fr-FR", {
        weekday: "long",
        day: "numeric",
        month: "long",
        year: "numeric",
        hour: "2-digit",
        minute: "2-digit",
      }).format(date);
    } catch {
      return isoString;
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-slate-50 flex items-center justify-center p-4">
        <div className="text-center">
          <div className="w-12 h-12 border-4 border-indigo-600 border-t-transparent rounded-full animate-spin mx-auto mb-4"></div>
          <p className="text-slate-600 font-medium">Chargement du billet...</p>
        </div>
      </div>
    );
  }

  if (error || !ticket) {
    return (
      <div className="min-h-screen bg-slate-50 flex items-center justify-center p-4">
        <div className="bg-white rounded-2xl shadow-xl max-w-md w-full p-6 text-center border border-slate-100">
          <div className="w-16 h-16 bg-red-100 text-red-600 rounded-full flex items-center justify-center mx-auto mb-4 text-2xl font-bold">
            ✕
          </div>
          <h1 className="text-xl font-bold text-slate-800 mb-2">Billet non disponible</h1>
          <p className="text-slate-600 mb-6">{error || "Le billet demandé n'existe pas."}</p>
          <div className="text-xs text-slate-400 border-t pt-4">AXIS Transport - Service Client</div>
        </div>
      </div>
    );
  }

  const isConfirmed = ticket.status === "CONFIRMED" || ticket.status === "ISSUED";

  // Compose le billet en image à partir des données du serveur ; une donnée absente affiche « à confirmer ».
  const downloadTicket = async () => {
    // Logo du site ; s'il ne se charge pas, le nom est écrit en texte.
    const logo = await new Promise<HTMLImageElement | null>((resolve) => {
      const image = new Image();
      image.onload = () => resolve(image);
      image.onerror = () => resolve(null);
      image.src = "/images/axis-logo.png";
    });
    const qr = document.getElementById("ticket-qr-canvas") as HTMLCanvasElement | null;
    const canvas = document.createElement("canvas");
    canvas.width = 800;
    canvas.height = 1120;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    ctx.fillStyle = "#ffffff";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = "#0f172a";
    if (logo) {
      ctx.drawImage(logo, 50, 28, Math.round((logo.width * 84) / logo.height), 84);
    } else {
      ctx.font = "bold 44px sans-serif";
      ctx.fillText(ticket.company_name || "AXIS Transport", 50, 80);
    }
    ctx.font = "24px sans-serif";
    ctx.fillText("Billet électronique", 50, 144);
    if (qr) ctx.drawImage(qr, 200, 160, 400, 400);
    const rows: [string, string][] = [
      ["Référence", ticket.reference],
      ["Trajet", ticket.origin && ticket.destination ? `${ticket.origin} → ${ticket.destination}` : ""],
      ["Départ", ticket.departure_at ? formatDate(ticket.departure_at) : ""],
      ["Siège", ticket.seat_label],
      ["Passager", ticket.passenger_name],
      ["Prix du billet", ticket.formatted_amount],
      ["Statut", ticket.status_display],
    ];
    rows.forEach(([label, value], index) => {
      const y = 640 + index * 58;
      ctx.font = "bold 24px sans-serif";
      ctx.fillText(label, 50, y);
      ctx.font = "24px sans-serif";
      ctx.fillText(value && value !== "N/A" ? value : "à confirmer", 250, y);
    });
    ctx.font = "20px sans-serif";
    ctx.fillText("Présentez ce QR code à l'embarquement.", 50, 1080);
    const link = document.createElement("a");
    link.download = `billet-axis-${ticket.reference}.png`;
    link.href = canvas.toDataURL("image/png");
    link.click();
  };

  return (
    <div className="min-h-screen bg-slate-100 py-8 px-4 font-sans antialiased text-slate-900">
      <div className="max-w-lg mx-auto bg-white rounded-3xl shadow-2xl overflow-hidden border border-slate-200">
        
        {/* Header Branding */}
        <div className="bg-white border-b border-slate-200 p-6 text-center relative">
          <div className="inline-block bg-axis-100 text-axis-900 px-3 py-1 rounded-full text-xs font-semibold tracking-wider uppercase mb-3">
            Billet Électronique Officiel
          </div>
          <h1>
            <img src="/images/axis-logo.png" alt={ticket.company_name || "AXIS Transport"} width={570} height={176} className="mx-auto h-16 w-auto" />
          </h1>
          <p className="text-slate-500 text-xs mt-2">Votre réseau de transport fiable</p>
        </div>

        {/* Status Badge */}
        <div className="px-6 pt-6 flex items-center justify-between">
          <span className="text-xs text-slate-400 font-medium">RÉFÉRENCE</span>
          <span
            className={`px-3 py-1 rounded-full text-xs font-bold tracking-wide ${
              isConfirmed
                ? "bg-emerald-100 text-emerald-800 border border-emerald-200"
                : "bg-amber-100 text-amber-800 border border-amber-200"
            }`}
          >
            ● {ticket.status_display || ticket.status}
          </span>
        </div>
        <div className="px-6 text-xl font-mono font-bold text-slate-900 mt-1">
          {ticket.reference}
        </div>

        {/* QR Code Section */}
        <div className="p-6 text-center border-b border-slate-100">
          {ticket.qr_token ? (
            <div className="inline-block p-4 bg-white rounded-2xl shadow-md border border-slate-200">
              <QRCodeSVG value={ticket.qr_token} size={180} level="H" includeMargin={true} />
            </div>
          ) : (
            <div className="p-8 bg-slate-50 rounded-2xl text-slate-400 text-sm">
              QR Code disponible après validation
            </div>
          )}
          <p className="text-xs text-slate-500 mt-3 font-medium">
            Présentez ce QR Code au contrôleur lors de l'embarquement.
          </p>
          {ticket.qr_token && (
            <>
              <div className="hidden">
                <QRCodeCanvas id="ticket-qr-canvas" value={ticket.qr_token} size={400} level="H" includeMargin={true} />
              </div>
              <button
                type="button"
                onClick={downloadTicket}
                className="mt-4 w-full rounded-xl bg-slate-900 px-4 py-3 text-sm font-bold text-white"
              >
                Télécharger le billet (image)
              </button>
            </>
          )}
        </div>

        {/* Trip & Route Details */}
        <div className="p-6 bg-slate-50/50 space-y-4">
          <div className="bg-white p-4 rounded-2xl border border-slate-200/80 shadow-sm">
            <div className="text-xs text-slate-400 font-semibold uppercase tracking-wider mb-2">
              Trajet
            </div>
            <div className="flex items-center justify-between">
              <div className="text-lg font-bold text-slate-900">{ticket.origin || "Départ"}</div>
              <div className="text-indigo-600 font-bold px-2">➔</div>
              <div className="text-lg font-bold text-slate-900">{ticket.destination || "Arrivée"}</div>
            </div>
            <div className="mt-3 pt-3 border-t border-slate-100 text-xs text-slate-600 flex items-center justify-between">
              <span>📅 Départ</span>
              <span className="font-semibold text-slate-800">{formatDate(ticket.departure_at)}</span>
            </div>
          </div>

          {/* Passenger & Seat */}
          <div className="grid grid-cols-2 gap-3">
            <div className="bg-white p-4 rounded-2xl border border-slate-200/80 shadow-sm">
              <div className="text-xs text-slate-400 font-semibold uppercase tracking-wider mb-1">
                Passager
              </div>
              <div className="font-bold text-slate-900 truncate">
                {ticket.passenger_name || "Nom non spécifié"}
              </div>
            </div>

            <div className="bg-white p-4 rounded-2xl border border-slate-200/80 shadow-sm">
              <div className="text-xs text-slate-400 font-semibold uppercase tracking-wider mb-1">
                Siège
              </div>
              <div className="text-2xl font-black text-indigo-700">
                N° {ticket.seat_label}
              </div>
            </div>
          </div>

          {/* Prix du billet seul : les frais de paiement n'apparaissent jamais sur le billet */}
          <div className="bg-slate-900 text-white p-4 rounded-2xl flex items-center justify-between shadow-lg">
            <span className="text-xs font-medium text-slate-300">Prix du billet</span>
            <span className="text-xl font-black tracking-tight text-emerald-400">
              {ticket.formatted_amount}
            </span>
          </div>
        </div>

        {/* Security / Footer Warning */}
        <div className="p-4 bg-slate-100 text-center text-[11px] text-slate-400 border-t border-slate-200 space-y-1">
          <p className="font-medium">Ce billet est personnel, en lecture seule et certifié par AXIS.</p>
          <p>© {new Date().getFullYear()} AXIS Transport. Tous droits réservés.</p>
        </div>

      </div>
    </div>
  );
}
