"use client";

import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { QRCodeSVG } from "qrcode.react";

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

    const apiUrl = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000/api/v1";
    // Normalize URL if it ends with /api vs /api/v1
    const base = apiUrl.replace(/\/$/, "");
    const endpoint = base.endsWith("/v1")
      ? `${base}/client/tickets/public/${encodeURIComponent(reference)}/`
      : `${base}/v1/client/tickets/public/${encodeURIComponent(reference)}/`;

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

  return (
    <div className="min-h-screen bg-slate-100 py-8 px-4 font-sans antialiased text-slate-900">
      <div className="max-w-lg mx-auto bg-white rounded-3xl shadow-2xl overflow-hidden border border-slate-200">
        
        {/* Header Branding */}
        <div className="bg-gradient-to-r from-slate-900 via-indigo-950 to-slate-900 p-6 text-white text-center relative">
          <div className="inline-block bg-indigo-500/20 text-indigo-300 px-3 py-1 rounded-full text-xs font-semibold tracking-wider uppercase mb-2">
            Billet Électronique Officiel
          </div>
          <h1 className="text-2xl font-black tracking-tight">{ticket.company_name}</h1>
          <p className="text-slate-400 text-xs mt-1">Votre réseau de transport fiable</p>
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

          {/* Amount Paid */}
          <div className="bg-slate-900 text-white p-4 rounded-2xl flex items-center justify-between shadow-lg">
            <span className="text-xs font-medium text-slate-300">Montant réglé</span>
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
