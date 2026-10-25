"use client";

import { FormEvent, useCallback, useEffect, useRef, useState } from "react";
import { QRCodeSVG } from "qrcode.react";
import { apiFetch, apiList, clearTokens, formatDate, getAccessToken, money } from "@/lib/api";
import { beninDateKey, phoneHref, placeChoices, searchDateError, searchError, whatsappHref } from "@/lib/portal-rules";
import type { Checkout, Contact, Location, Parcel, ParcelTracking, PaymentMethod, RentalBooking, Seat, Ticket, Trip, User, Vehicle } from "@/lib/types";
import { LoginCard } from "./login-card";
import { BusSeatMap } from "./bus-seat-map";
import { PassengerForm, type PassengerItem } from "./passenger-form";
import { clearGuestBooking, loadGuestBooking, rememberGuestPayment, saveGuestBooking } from "@/lib/guest-booking";

type ClientTab = "accueil" | "billets" | "colis" | "location" | "profil";

export function ClientPortal() {
  const [tab, setTab] = useState<ClientTab>("accueil");
  const [user, setUser] = useState<User | null>(null);
  const [trips, setTrips] = useState<Trip[]>([]);
  const [locations, setLocations] = useState<Location[]>([]);
  const [vehicles, setVehicles] = useState<Vehicle[]>([]);
  const [tickets, setTickets] = useState<Ticket[]>([]);
  const [parcels, setParcels] = useState<Parcel[]>([]);
  const [rentals, setRentals] = useState<RentalBooking[]>([]);
  const [paymentMethods, setPaymentMethods] = useState<PaymentMethod[]>([]);
  // Coordonnées lues dans les réglages admin ; vides tant qu'elles ne sont pas renseignées.
  const [contact, setContact] = useState<Contact>({ contact_phone: "", contact_whatsapp: "" });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const loadPrivate = useCallback(async () => {
    if (!getAccessToken()) return setUser(null);
    try {
      const me = await apiFetch<User>("/auth/me/");
      if (me.role !== "CLIENT") {
        setUser(null);
        setTickets([]);
        setParcels([]);
        setRentals([]);
        return;
      }
      const [myTickets, myParcels, myRentals] = await Promise.all([
        apiList<Ticket>("/client/tickets/"),
        apiList<Parcel>("/client/parcels/"),
        apiList<RentalBooking>("/client/rentals/"),
      ]);
      setUser(me);
      setTickets(myTickets);
      setParcels(myParcels);
      setRentals(myRentals);
    } catch {
      clearTokens();
      setUser(null);
    }
  }, []);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const [availableTrips, activeLocations, rentalVehicles, methods] = await Promise.all([
        apiList<Trip>("/client/trips/", false),
        apiList<Location>("/client/locations/", false),
        apiList<Vehicle>("/client/vehicles/", false),
        apiList<PaymentMethod>("/client/payment-methods/", false),
      ]);
      setTrips(availableTrips);
      setLocations(activeLocations);
      setVehicles(rentalVehicles);
      setPaymentMethods(methods);
      apiFetch<Contact>("/client/contact/", {}, false).then(setContact).catch(() => undefined);
      await loadPrivate();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "L’API Axis est indisponible.");
    } finally {
      setLoading(false);
    }
  }, [loadPrivate]);

  useEffect(() => { void load(); }, [load]);

  function logout() {
    clearTokens();
    setUser(null);
    setTickets([]);
    setParcels([]);
    setRentals([]);
    setTab("accueil");
  }

  // --- Search Form State ---
  const [searchOrigin, setSearchOrigin] = useState("");
  const [searchDestination, setSearchDestination] = useState("");
  const [searchDate, setSearchDate] = useState("");
  const [searchMessage, setSearchMessage] = useState("");
  const [preselectedTripId, setPreselectedTripId] = useState("");

  // Aujourd'hui au Bénin : date minimale du calendrier (les jours passés sont grisés).
  const beninToday = beninDateKey();

  // Rechercher sans les deux villes, sans date, ou avec une date passée : message, et rien n'est lancé.
  async function runSearch() {
    const problem = searchError(searchOrigin, searchDestination) ?? searchDateError(searchDate, beninDateKey());
    setSearchMessage(problem ?? "");
    if (!problem) {
      try {
        const query = new URLSearchParams({
          origin: searchOrigin,
          destination: searchDestination,
          ...(searchDate ? { date: searchDate } : {}),
        });
        const serverTrips = await apiList<Trip>(`/client/trips/?${query.toString()}`, false);
        if (serverTrips.length > 0) {
          setTrips(current => {
            const serverIds = new Set(serverTrips.map(t => t.id));
            return [...serverTrips, ...current.filter(t => !serverIds.has(t.id))];
          });
          setPreselectedTripId(String(serverTrips[0].id));
        }
      } catch {
        // En cas d'erreur de requête, le filtre local s'applique
      }
      setTab("billets");
    }
  }
  
  // Derived state: Filtered Trips based on Search
  const filteredTrips = trips.filter(trip => {
    let match = true;
    const stops = trip.route_detail?.stops || [];

    if (searchOrigin && searchDestination) {
      const origId = Number(searchOrigin);
      const destId = Number(searchDestination);
      const originIdx = stops.findIndex(s => s.id === origId || s.location_id === origId);
      const destIdx = stops.findIndex(s => s.id === destId || s.location_id === destId);
      if (originIdx !== -1 && destIdx !== -1) {
        if (originIdx >= destIdx) match = false;
      } else if (trip.route_detail.origin !== origId || trip.route_detail.destination !== destId) {
        match = false;
      }
    } else if (searchOrigin) {
      const origId = Number(searchOrigin);
      const originIdx = stops.findIndex(s => s.id === origId || s.location_id === origId);
      if (originIdx !== -1) {
        if (originIdx === stops.length - 1) match = false;
      } else if (trip.route_detail.origin !== origId) {
        match = false;
      }
    } else if (searchDestination) {
      const destId = Number(searchDestination);
      const destIdx = stops.findIndex(s => s.id === destId || s.location_id === destId);
      if (destIdx !== -1) {
        if (destIdx === 0) match = false;
      } else if (trip.route_detail.destination !== destId) {
        match = false;
      }
    }

    if (searchDate) {
      // Date du départ au Bénin (et non en UTC : un départ à 00 h 30 tombe le bon jour).
      const tripDate = beninDateKey(new Date(trip.departure_at));
      if (tripDate !== searchDate) match = false;
    }
    return match;
  });

  return (
    <>
      <div className="top">
        <div className="wrap">
          <span>Axe Parakou – Cotonou</span>
          {contact.contact_phone && <span>Téléphone : <PhoneText value={contact.contact_phone} /></span>}
          <WhatsAppIcon value={contact.contact_whatsapp} />
          <span>Voyagez en toute confiance</span>
        </div>
      </div>
      
      <header>
        <div className="wrap nav">
          <a className="logo" href="#" onClick={(e) => { e.preventDefault(); setTab("accueil"); }}>
            <img src="/images/axis-logo.png" alt="AXIS Transport" width={570} height={176} />
          </a>
          <nav className="menu">
            <button className={tab === "accueil" ? "on" : ""} onClick={() => setTab("accueil")}>Accueil</button>
            <button className={tab === "billets" ? "on" : ""} onClick={() => setTab("billets")}>Billets</button>
            <button className={tab === "colis" ? "on" : ""} onClick={() => setTab("colis")}>Colis</button>
            <button className={tab === "location" ? "on" : ""} onClick={() => setTab("location")}>Location</button>
            <button className={tab === "profil" ? "on" : ""} onClick={() => setTab("profil")}>Profil</button>
          </nav>
          <div className="sp"></div>
          {user ? (
            <button className="btn s" onClick={() => setTab("profil")}>Mon compte</button>
          ) : (
            <button className="btn s" onClick={() => setTab("profil")}>Se connecter</button>
          )}
          <button className="btn p s" onClick={() => setTab("billets")}>Réserver</button>
        </div>
      </header>

      {error && (
        <div className="wrap" style={{ marginTop: '20px' }}>
          <div style={{ background: 'var(--warnbg)', color: 'var(--warn)', padding: '12px 20px', borderRadius: '10px' }}>
            {error}
          </div>
        </div>
      )}

      {loading ? (
        <div className="wrap" style={{ padding: '60px 0', textAlign: 'center', color: 'var(--mute)' }}>
          Chargement des données AXIS...
        </div>
      ) : (
        <>
          {tab === "accueil" && (
            <>
              <div className="hero has-bg">
                <div className="wrap">
                  <small>AXIS TRANSPORT</small>
                  <h1>Voyagez simplement avec AXIS Transport</h1>
                  <p>Réservez votre place en ligne, payez par Mobile Money et voyagez avec un billet électronique.</p>
                  <div className="axe">
                    <span>Parakou</span><em>›</em>
                    <span>Savè</span><em>›</em>
                    <span>Kétou</span><em>›</em>
                    <span>Porto-Novo</span><em>›</em>
                    <span>Cotonou</span>
                  </div>
                </div>
              </div>

              <main className="wrap">
                <div className="search">
                  <div className="f">
                    <label>Départ</label>
                    <select value={searchOrigin} onChange={(e) => { setSearchOrigin(e.target.value); setSearchMessage(""); }}>
                      <option value="">Choisir…</option>
                      {placeChoices(locations, searchDestination).map(loc => <option key={loc.id} value={loc.id}>{loc.name}</option>)}
                    </select>
                  </div>
                  <div className="f">
                    <label>Destination</label>
                    <select value={searchDestination} onChange={(e) => { setSearchDestination(e.target.value); setSearchMessage(""); }}>
                      <option value="">Choisir…</option>
                      {placeChoices(locations, searchOrigin).map(loc => <option key={loc.id} value={loc.id}>{loc.name}</option>)}
                    </select>
                  </div>
                  <div className="f">
                    <label>Date de départ</label>
                    <input type="date" min={beninToday} value={searchDate} onChange={(e) => { setSearchDate(e.target.value); setSearchMessage(""); }} />
                  </div>
                  <div className="f">
                    <label>Passagers</label>
                    <select>
                      <option value="1">1 passager</option>
                      <option value="2">2 passagers</option>
                      <option value="3">3 passagers</option>
                    </select>
                  </div>
                  <button className="btn p" onClick={runSearch}>Rechercher</button>
                </div>
                {searchMessage && <p role="alert" style={{ color: 'var(--warn)', marginTop: '10px', fontWeight: 600 }}>{searchMessage}</p>}

                <section className="section-margin">
                  <div className="head">
                    <div>
                      <h2>Prochains départs</h2>
                      <p className="sub">Trouvez un trajet et réservez votre place en quelques clics.</p>
                    </div>
                    <button style={{ background: 'none', border: 'none', color: 'var(--blue)', fontWeight: 600, fontSize: '14px', cursor: 'pointer', marginBottom: '18px' }} onClick={() => setTab("billets")}>
                      Voir tous les départs →
                    </button>
                  </div>
                  
                  {filteredTrips.length === 0 ? (
                    <div style={{ textAlign: 'center', padding: '40px', background: '#fff', borderRadius: '16px', border: '1px dashed var(--line)', color: 'var(--mute)' }}>
                      Aucun départ publié pour ces critères.
                    </div>
                  ) : (
                    <div className="grid3">
                      {filteredTrips.slice(0, 6).map((trip) => (
                        <div key={trip.id} className="card dep">
                          <div className="r">
                            <h3>{trip.route_detail.label}</h3>
                            <span className={trip.available_seats > 0 ? "pill" : "pill ex"}>
                              {trip.available_seats > 0 ? "Places disponibles" : "Bientôt complet"}
                            </span>
                          </div>
                          <div className="d">Date : {formatDate(trip.departure_at)}</div>
                          <div className="times">
                            <span>Départ <b>{new Date(trip.departure_at).toLocaleTimeString('fr-FR', {hour: '2-digit', minute:'2-digit'})}</b></span>
                            <span>Arrivée <b>{trip.arrival_at ? new Date(trip.arrival_at).toLocaleTimeString('fr-FR', {hour: '2-digit', minute:'2-digit'}) : "--:--"}</b></span>
                          </div>
                          <div className="b">
                            <span className="price">{trip.current_fare ? money(trip.current_fare.amount, trip.current_fare.currency) : "Sur devis"}</span>
                            <button className="btn p s" onClick={() => { setPreselectedTripId(String(trip.id)); setTab("billets"); }}>Réserver</button>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </section>
              </main>

              <div className="why">
                <div className="wrap whyg">
                  <div>
                    <h2>Pourquoi voyager avec AXIS ?</h2>
                    <p>Un parcours simple, de la réservation au contrôle du billet.</p>
                  </div>
                  <div>
                    <div className="ic">🎫</div>
                    <h3>Billet électronique</h3>
                    <p>Recevez votre billet avec QR code sur votre téléphone.</p>
                  </div>
                  <div>
                    <div className="ic">📱</div>
                    <h3>Paiement Mobile Money</h3>
                    <p>Payez en ligne, votre place est confirmée aussitôt.</p>
                  </div>
                  <div>
                    <div className="ic">📦</div>
                    <h3>Suivi de colis</h3>
                    <p>Suivez votre colis étape par étape jusqu'au retrait.</p>
                  </div>
                </div>
              </div>

              <main className="wrap">
                <section className="section-margin" style={{ paddingBottom: '60px' }}>
                  <h2>Nos services</h2>
                  <p className="sub">Voyage, colis et location depuis un seul compte.</p>
                  <div className="svc">
                    <div className="card" onClick={() => setTab("billets")}>
                      <div className="pic" style={ { backgroundImage: "url('/images/service-passenger.jpg')" } }></div>
                      <div>
                        <h3>Transport de voyageurs</h3>
                        <p>Réservez votre place sur l'axe Parakou – Cotonou.</p>
                      </div>
                    </div>
                    <div className="card" onClick={() => setTab("colis")}>
                      <div className="pic" style={ { backgroundImage: "url('/images/service-parcel.jpg')" } }></div>
                      <div>
                        <h3>Suivi de colis</h3>
                        <p>Déposez à l'agence et suivez votre colis en ligne.</p>
                      </div>
                    </div>
                    <div className="card" onClick={() => setTab("location")}>
                      {/* Using emoji as fallback since image failed */}
                      <div className="pic">🚗</div>
                      <div>
                        <h3>Location de véhicules</h3>
                        <p>Véhicules et tarifs à confirmer avec Axis.</p>
                      </div>
                    </div>
                  </div>
                </section>
              </main>
            </>
          )}

          {tab === "billets" && (
            <main className="wrap section-margin" style={{ paddingBottom: '60px' }}>
              <h2>Billetterie & Réservation</h2>
              <p className="sub">Trouvez un départ, choisissez votre siège et recevez votre billet électronique.</p>
              <Tickets user={user} trips={trips} tickets={tickets} paymentMethods={paymentMethods} onAuthenticated={loadPrivate} onChanged={loadPrivate} preselectedTripId={preselectedTripId} searchOrigin={searchOrigin} searchDestination={searchDestination} />
            </main>
          )}
          
          {tab === "colis" && (
            <main className="wrap section-margin" style={{ paddingBottom: '60px' }}>
              <h2>Suivi de colis</h2>
              <p className="sub">Suivez l'acheminement de votre colis avec son code de suivi.</p>
              <Parcels />
            </main>
          )}

          {tab === "location" && (
            <main className="wrap section-margin" style={{ paddingBottom: '60px' }}>
              <h2>Location de véhicules</h2>
              <p className="sub">Découvrez notre flotte et effectuez une demande de réservation.</p>
              <Rentals user={user} vehicles={vehicles} rentals={rentals} onAuthenticated={loadPrivate} onChanged={loadPrivate} />
            </main>
          )}

          {tab === "profil" && (
            <main className="wrap section-margin" style={{ paddingBottom: '60px' }}>
              <h2>Espace personnel</h2>
              <p className="sub">Gérez votre compte, vos réservations et vos préférences.</p>
              <Profile user={user} tickets={tickets} parcels={parcels} rentals={rentals} onAuthenticated={loadPrivate} onLogout={logout} />
            </main>
          )}
        </>
      )}

      <footer>
        <div className="wrap">
          <div className="fg">
            <div>
              <a className="logo" style={{ color: '#fff' }} href="#">
                <img src="/images/axis-emblem.png" alt="" width={192} height={192} />AXIS Transport
              </a>
              <p style={{ marginTop: '10px', opacity: '.8' }}>Voyager, expédier, louer.</p>
            </div>
            <div>
              <h4>Navigation</h4>
              <button style={{ display: 'block', margin: '0 0 6px 0', background: 'none', border: 'none', color: 'inherit', cursor: 'pointer', textAlign: 'left', opacity: 0.8 }} onClick={() => setTab("accueil")}>Accueil</button>
              <button style={{ display: 'block', margin: '0 0 6px 0', background: 'none', border: 'none', color: 'inherit', cursor: 'pointer', textAlign: 'left', opacity: 0.8 }} onClick={() => setTab("billets")}>Billets</button>
              <button style={{ display: 'block', margin: '0 0 6px 0', background: 'none', border: 'none', color: 'inherit', cursor: 'pointer', textAlign: 'left', opacity: 0.8 }} onClick={() => setTab("colis")}>Colis</button>
              <button style={{ display: 'block', margin: '0 0 6px 0', background: 'none', border: 'none', color: 'inherit', cursor: 'pointer', textAlign: 'left', opacity: 0.8 }} onClick={() => setTab("location")}>Location</button>
            </div>
            <div>
              <h4>À propos</h4>
              <a href="#">Notre histoire</a>
              <a href="#">Notre axe</a>
            </div>
            <div>
              <h4>Assistance</h4>
              <a href="#">FAQ</a>
              <a href="#">Suivi de colis</a>
            </div>
            <div>
              <h4>Contact</h4>
              <p style={{ opacity: '.8', marginBottom: '6px' }}>Téléphone : {contact.contact_phone ? <PhoneText value={contact.contact_phone} /> : "À renseigner"}</p>
              <p style={{ opacity: '.8', marginBottom: '10px', display: 'flex', alignItems: 'center', gap: '8px' }}>WhatsApp : {contact.contact_whatsapp || "À renseigner"} <WhatsAppIcon value={contact.contact_whatsapp} /></p>
              {phoneHref(contact.contact_phone) && <a className="btn s" href={phoneHref(contact.contact_phone)!}>Appeler</a>}
            </div>
          </div>
          <div className="copy">© {new Date().getFullYear()} AXIS Transport · Mentions légales · Politique de confidentialité</div>
        </div>
      </footer>
    </>
  );
}

// ==============================================
// SUB-COMPONENTS FOR TABS (Billets, Colis, Location, Profil)
// Using standard tailwind / inline styles to match the template UI within cards.
// ==============================================

type Quote = Omit<Checkout, "transaction_id" | "payment_url" | "simulated">;
type BookingPayload = { id: number; status: string; tickets: Ticket[]; payment_quotes: Quote[]; guest_access_token?: string };

function Tickets({
  user,
  trips,
  tickets,
  paymentMethods,
  onAuthenticated,
  onChanged,
  preselectedTripId = "",
  searchOrigin = "",
  searchDestination = "",
}: {
  user: User | null;
  trips: Trip[];
  tickets: Ticket[];
  paymentMethods: PaymentMethod[];
  onAuthenticated: () => Promise<void>;
  onChanged: () => Promise<void>;
  preselectedTripId?: string;
  searchOrigin?: string;
  searchDestination?: string;
}) {
  const [tripId, setTripId] = useState(preselectedTripId || "");

  useEffect(() => {
    if (preselectedTripId) setTripId(preselectedTripId);
  }, [preselectedTripId]);
  const [paymentCheck, setPaymentCheck] = useState<{ ticketId: number; busy: boolean; text: string } | null>(null);
  const [seats, setSeats] = useState<Seat[]>([]);
  const [selectedSeatIds, setSelectedSeatIds] = useState<number[]>([]);
  const [passengers, setPassengers] = useState<PassengerItem[]>([]);
  const [contactPhone, setContactPhone] = useState("");
  const [buyerIfu, setBuyerIfu] = useState("");
  const [pendingTickets, setPendingTickets] = useState<Ticket[]>([]);
  const [checkout, setCheckout] = useState<Checkout | null>(null);
  // Réservation en cours. Sans compte, le serveur renvoie un jeton qui autorise le paiement.
  const [booking, setBooking] = useState<{ id: number; token: string | null } | null>(null);
  // Montants calculés par le serveur : avant la réservation (par trajet), puis pour la réservation en cours.
  const [tripQuotes, setTripQuotes] = useState<Quote[]>([]);
  const [bookingQuotes, setBookingQuotes] = useState<Quote[]>([]);
  const [paymentFailed, setPaymentFailed] = useState(false);
  const [busy, setBusy] = useState(false);
  // Verrou immédiat contre le double clic : l'état « busy » n'est visible qu'au rendu suivant.
  const locked = useRef(false);
  const [now, setNow] = useState(() => Date.now());
  const [message, setMessage] = useState("");
  const selectedTrip = trips.find((trip) => String(trip.id) === tripId);
  const onlineMethods = paymentMethods.filter((method) => method.online);
  // Un seul moyen de paiement en ligne : une seule action « Payer [total] ». Plusieurs : le choix reste à l'écran.
  const singleQuote = tripQuotes.length === 1 ? tripQuotes[0] : null;
  const pending = pendingTickets[0] ?? null;
  const held = pending?.status === "HELD";
  // Un billet vient d'être émis : le formulaire ne propose plus de payer tant que l'on n'a pas choisi « Acheter un autre billet ».
  const issued = pending?.status === "ISSUED";
  const access = (current: { token: string | null }): Record<string, string> => (current.token ? { "X-Booking-Token": current.token } : {});

  useEffect(() => {
    if (user) {
      setContactPhone((current) => current || user.phone || "");
    }
  }, [user]);

  // Au chargement, reprend la réservation conservée dans le navigateur (retour de la page de paiement,
  // onglet fermé, page rechargée). Un invité y accède par son jeton, un client connecté par son compte.
  useEffect(() => {
    const stored = loadGuestBooking();
    if (!stored || (!stored.token && !user)) return;
    let cancelled = false;
    apiFetch<BookingPayload>(`/client/bookings/${stored.id}/`, { headers: access(stored) }, !stored.token)
      .then((found) => {
        if (cancelled || !found.tickets.length) return;
        const first = found.tickets[0];
        if (first.status !== "HELD" && first.status !== "ISSUED") { clearGuestBooking(); return; }
        setBooking({ id: stored.id, token: stored.token });
        setPendingTickets(found.tickets);
        setBookingQuotes(found.payment_quotes);
        const quote = found.payment_quotes.find((item) => item.payment_method === stored.paymentMethod);
        if (first.status === "HELD" && quote && stored.transactionId) setCheckout({ ...quote, transaction_id: stored.transactionId, payment_url: stored.paymentUrl ?? null, simulated: false });
        setMessage(first.status === "ISSUED" ? "Vos billets sont prêts." : "Réservation retrouvée. Finalisez le paiement avant l’expiration.");
      })
      .catch((reason) => { if ((reason as { status?: number }).status === 403 || (reason as { status?: number }).status === 404) clearGuestBooking(); });
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user]);

  // Revenu par le bouton « retour » du navigateur depuis la page de paiement : la page peut être restaurée telle quelle.
  useEffect(() => {
    const restore = (event: PageTransitionEvent) => { if (event.persisted) { locked.current = false; setBusy(false); setMessage(""); } };
    window.addEventListener("pageshow", restore);
    return () => window.removeEventListener("pageshow", restore);
  }, []);

  // Plan de sièges relu auprès du serveur : après une réservation ou un paiement, un siège pris n'est plus proposé.
  const loadSeats = useCallback(async () => {
    if (!tripId) { setSeats([]); return; }
    try { setSeats(await apiList<Seat>(`/client/seats/?trip=${tripId}`, false)); } catch (reason) { setMessage(reason instanceof Error ? reason.message : "Plan de sièges indisponible."); }
  }, [tripId]);

  useEffect(() => { void loadSeats(); }, [loadSeats]);

  // Total à payer pour le trajet choisi et le nombre de passagers, demandé au serveur avant toute réservation.
  useEffect(() => {
    setTripQuotes([]);
    if (!tripId) return;
    const count = Math.max(1, selectedSeatIds.length);
    let cancelled = false;
    const params = new URLSearchParams({ passengers: String(count) });
    if (searchOrigin) params.set("origin", searchOrigin);
    if (searchDestination) params.set("destination", searchDestination);
    apiFetch<Quote[]>(`/client/trips/${tripId}/payment-quotes/?${params.toString()}`, {}, false).then((quotes) => { if (!cancelled) setTripQuotes(quotes); }).catch(() => undefined);
    return () => { cancelled = true; };
  }, [tripId, selectedSeatIds.length, searchOrigin, searchDestination]);

  function handleToggleSeat(seat: Seat) {
    setSelectedSeatIds((current) => {
      const exists = current.includes(seat.id);
      let next: number[];
      if (exists) {
        next = current.filter((id) => id !== seat.id);
      } else {
        if (current.length >= 8) return current;
        next = [...current, seat.id];
      }

      setPassengers((prev) => {
        const defaultName = user ? [user.first_name, user.last_name].filter(Boolean).join(" ") || user.username : "";
        return next.map((sId, index) => {
          const found = prev.find((p) => p.seatId === sId);
          if (found) return found;
          const sObj = seats.find((s) => s.id === sId);
          return {
            seatId: sId,
            seatNumber: sObj?.number ?? String(sId),
            fullName: index === 0 && !prev.length ? defaultName : "",
            phone: index === 0 && !prev.length ? (user?.phone || contactPhone) : "",
          };
        });
      });

      return next;
    });
  }

  function handlePassengerChange(index: number, field: "fullName" | "phone", value: string) {
    setPassengers((prev) => {
      const updated = [...prev];
      if (updated[index]) {
        updated[index] = { ...updated[index], [field]: value };
      }
      return updated;
    });
  }

  // Compte à rebours de la tenue du siège.
  const expiresAt = held && pending?.reservation_expires_at ? new Date(pending.reservation_expires_at).getTime() : null;
  useEffect(() => {
    if (!expiresAt) return;
    const timer = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, [expiresAt]);
  const remainingSeconds = expiresAt ? Math.max(0, Math.floor((expiresAt - now) / 1000)) : null;
  const expired = remainingSeconds === 0;
  useEffect(() => { if (expired) void loadSeats(); }, [expired, loadSeats]);

  function forget() {
    clearGuestBooking();
    setBooking(null); setPendingTickets([]); setCheckout(null); setBookingQuotes([]); setPaymentFailed(false); setMessage("");
    setSelectedSeatIds([]); setPassengers([]);
    void loadSeats();
  }

  // Repart d'un formulaire vierge après un achat. Sans compte, le billet n'est gardé nulle part sur le site :
  // on demande confirmation avant de ne plus le proposer.
  function buyAnother() {
    if (!user && !window.confirm("Avez-vous téléchargé vos billets ? Sans compte, ils ne seront plus proposés sur cette page.")) return;
    forget();
  }

  // Annulation d'une réservation non payée : le serveur libère le siège tout de suite.
  async function cancelBooking() {
    if (locked.current || !booking) return;
    if (!window.confirm("Annuler cette réservation ? Les sièges seront libérés.")) return;
    locked.current = true;
    setBusy(true);
    try {
      await apiFetch(`/client/bookings/${booking.id}/cancel/`, { method: "POST", headers: access(booking) }, !booking.token);
      forget();
      setMessage("Réservation annulée. Les sièges sont libérés.");
      void onChanged();
    } catch (reason) { setMessage(reason instanceof Error ? reason.message : "Annulation impossible."); }
    finally { locked.current = false; setBusy(false); }
  }

  async function createBooking() {
    if (passengers.length === 0) throw new Error("Veuillez sélectionner au moins une place sur le plan.");
    for (let i = 0; i < passengers.length; i++) {
      if (!passengers[i].fullName.trim()) {
        throw new Error(`Veuillez renseigner le nom du passager pour le siège N° ${passengers[i].seatNumber}.`);
      }
    }
    const payload = {
      trip: Number(tripId),
      contact_phone: contactPhone || passengers[0]?.phone || "",
      buyer_ifu: buyerIfu.trim(),
      origin: searchOrigin || undefined,
      destination: searchDestination || undefined,
      passengers: passengers.map((p) => ({
        full_name: p.fullName.trim(),
        phone: p.phone.trim() || contactPhone,
        seat: p.seatId,
      })),
    };
    const created = await apiFetch<BookingPayload>("/client/bookings/", { method: "POST", body: JSON.stringify(payload) }, !!user);
    const current = { id: created.id, token: created.guest_access_token ?? null };
    saveGuestBooking(current.id, current.token);
    setBooking(current);
    setPendingTickets(created.tickets);
    setBookingQuotes(created.payment_quotes);
    setCheckout(null);
    setSelectedSeatIds([]);
    setPassengers([]);
    void Promise.all([onChanged(), loadSeats()]);
    return current;
  }

  // Le serveur crée la transaction et fixe le montant ; le site redirige ensuite vers la page de paiement.
  async function openPayment(current: { id: number; token: string | null }, methodId: number) {
    setPaymentFailed(false);
    try {
      const created = await apiFetch<Checkout>(`/client/bookings/${current.id}/checkout/`, { method: "POST", headers: access(current), body: JSON.stringify({ payment_method: methodId }) }, !current.token);
      setCheckout(created);
      rememberGuestPayment(created.payment_method, created.transaction_id, created.payment_url);
      if (created.payment_url) {
        setMessage("Redirection vers la page de paiement…");
        window.location.assign(created.payment_url);
        return true;
      }
      await confirmPayment(created, current);
    } catch (reason) {
      // La réservation existe toujours : le client réessaie le paiement sur la même réservation.
      setPaymentFailed(true);
      setMessage(reason instanceof Error ? `Le paiement n’a pas pu démarrer : ${reason.message}` : "Le paiement n’a pas pu démarrer.");
    }
    return false;
  }

  // Action unique : réserver les sièges puis ouvrir le paiement, dans un seul enchaînement.
  async function payNow(event: FormEvent) {
    event.preventDefault();
    if (locked.current || held || !singleQuote) return;
    locked.current = true;
    setBusy(true); setMessage("");
    let redirecting = false;
    try {
      const current = await createBooking();
      redirecting = await openPayment(current, singleQuote.payment_method);
    } catch (reason) {
      setMessage(reason instanceof Error ? reason.message : "Réservation impossible.");
    } finally {
      if (!redirecting) { locked.current = false; setBusy(false); }
    }
  }

  // Plusieurs moyens de paiement en ligne (ou aucun) : la réservation d'abord, le choix du moyen ensuite.
  async function reserveOnly(event: FormEvent) {
    event.preventDefault();
    if (locked.current || held) return;
    locked.current = true;
    setBusy(true); setMessage("");
    try {
      await createBooking();
      setMessage("Sièges réservés temporairement. Finalisez le paiement avant l’expiration.");
    } catch (reason) { setMessage(reason instanceof Error ? reason.message : "Réservation impossible."); }
    finally { locked.current = false; setBusy(false); }
  }

  // Payer, réessayer ou reprendre le paiement de la réservation en cours : jamais de seconde réservation.
  async function payHeld(methodId: number) {
    if (locked.current || !booking) return;
    locked.current = true;
    setBusy(true); setMessage("");
    const redirecting = await openPayment(booking, methodId);
    if (!redirecting) { locked.current = false; setBusy(false); }
  }

  // « Vérifier mon paiement » depuis la liste : le serveur relit la transaction chez FedaPay, rien n'est décidé ici.
  async function checkTicketPayment(ticket: Ticket) {
    if (!ticket.booking) return;
    setPaymentCheck({ ticketId: ticket.id, busy: true, text: "Vérification du paiement…" });
    try {
      const found = await apiFetch<BookingPayload>(`/client/bookings/${ticket.booking}/refresh-payment/`, { method: "POST", body: "{}" });
      const confirmed = found.tickets.some((item) => item.id === ticket.id && item.status === "ISSUED");
      setPaymentCheck({ ticketId: ticket.id, busy: false, text: confirmed ? "Paiement confirmé : votre billet est prêt." : "Paiement pas encore confirmé par FedaPay. Réessayez dans un instant." });
      if (confirmed) await onChanged();
    } catch (reason) {
      setPaymentCheck({ ticketId: ticket.id, busy: false, text: reason instanceof Error ? reason.message : "Vérification impossible. Réessayez." });
    }
  }

  async function confirmPayment(current: Checkout | null = checkout, target: { id: number; token: string | null } | null = booking) {
    if (!current || !target) return;
    // La vérification interroge le prestataire : elle peut prendre plusieurs secondes.
    setBusy(true);
    setMessage("Vérification du paiement…");
    try {
      const response = await apiFetch<{ booking: { tickets: Ticket[] } }>(`/client/bookings/${target.id}/pay/`, { method: "POST", headers: access(target), body: JSON.stringify({ payment_method: current.payment_method, external_reference: current.transaction_id }) }, !target.token);
      setPendingTickets(response.booking.tickets);
      setCheckout(null);
      setMessage("Paiement confirmé, billet(s) émis.");
      setSelectedSeatIds([]);
      setPassengers([]);
      await Promise.all([onChanged(), loadSeats()]);
    } catch (reason) { setMessage(reason instanceof Error ? reason.message : "Paiement non confirmé."); }
    finally { locked.current = false; setBusy(false); }
  }

  // Le serveur chiffre tous les moyens actifs ; seuls ceux payables en ligne sont proposés ici.
  const payableQuotes = bookingQuotes.filter((item) => onlineMethods.some((method) => method.id === item.payment_method));
  const heldQuote = payableQuotes.find((item) => item.payment_method === checkout?.payment_method) ?? (payableQuotes.length === 1 ? payableQuotes[0] : null);
  const countdown = remainingSeconds === null ? "—" : `${Math.floor(remainingSeconds / 60)} min ${String(remainingSeconds % 60).padStart(2, "0")} s`;

  return (
    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '30px' }} className="responsive-grid">
      <div className="card">
        <h3>Réserver un billet</h3>
        <hr style={{ border: 0, borderBottom: '1px solid var(--line)', margin: '16px 0' }} />
        {trips.length === 0 ? <p>Aucun trajet disponible.</p> : (
          <form onSubmit={singleQuote ? payNow : reserveOnly} className="f">
            <label style={{ marginTop: '10px' }}>Voyage</label>
            <select value={tripId} onChange={(e) => { setTripId(e.target.value); setSelectedSeatIds([]); setPassengers([]); }} required>
              <option value="">Choisir un départ</option>
              {trips.map((trip) => <option key={trip.id} value={trip.id}>{trip.route_detail.label} — {formatDate(trip.departure_at)}</option>)}
            </select>
            
            {seats.length > 0 && (
              <BusSeatMap
                seats={seats}
                selectedSeatIds={selectedSeatIds}
                onToggleSeat={handleToggleSeat}
                disabled={busy}
              />
            )}

            <PassengerForm
              passengers={passengers}
              onPassengerChange={handlePassengerChange}
              contactPhone={contactPhone}
              onContactPhoneChange={setContactPhone}
              buyerIfu={buyerIfu}
              onBuyerIfuChange={setBuyerIfu}
              isUserLoggedIn={Boolean(user)}
            />

            {singleQuote && !held && !issued && (
              <p style={{ marginTop: '20px', fontSize: '14px', color: 'var(--mute)' }}>
                Total : <b>{money(singleQuote.total, singleQuote.currency)}</b>
                {selectedSeatIds.length > 1 && ` (${selectedSeatIds.length} billets)`}
              </p>
            )}
            {!held && !issued && (singleQuote ? (
              <button className="btn p" style={{ marginTop: '16px', width: '100%' }} disabled={busy || selectedSeatIds.length === 0}>
                {busy ? "Patientez…" : selectedSeatIds.length === 0 ? "Sélectionnez au moins un siège" : `Payer ${money(singleQuote.total, singleQuote.currency)}${selectedSeatIds.length > 1 ? ` (${selectedSeatIds.length} billets)` : ""}`}
              </button>
            ) : (
              <button className="btn p" style={{ marginTop: '24px', width: '100%' }} disabled={busy || selectedSeatIds.length === 0 || !selectedTrip?.current_fare}>
                {busy ? "Patientez…" : selectedSeatIds.length === 0 ? "Sélectionnez au moins un siège" : <>Réserver {selectedTrip?.current_fare ? ` · ${selectedSeatIds.length} place(s)` : ""}</>}
              </button>
            ))}
          </form>
        )}
        
        {message && <div role="status" style={{ background: 'var(--tint)', color: 'var(--navy)', padding: '16px', borderRadius: '10px', marginTop: '20px' }}>{message}</div>}
        
        {held && pending && booking && (
          <div style={{ background: 'var(--warnbg)', color: 'var(--warn)', padding: '20px', borderRadius: '12px', marginTop: '20px', border: '1px solid #f2dfb6' }}>
            <p style={{ fontWeight: 'bold', marginBottom: '8px' }}>Réservation en cours · {pending.reference}</p>
            <p style={{ fontSize: '14px' }}>
              Siège(s) : <b>{pendingTickets.map((t) => t.seat_detail?.number ?? t.seat).join(", ")}</b> · {pending.trip_detail.route_detail.label}
            </p>
            {expired ? (
              <>
                <p style={{ fontSize: '14px', margin: '8px 0 16px' }}>Le délai de réservation est écoulé : les sièges ne sont plus tenus.</p>
                <button type="button" className="btn" onClick={forget}>Nouvelle réservation</button>
                {checkout && <button type="button" className="btn" style={{ marginLeft: '10px' }} disabled={busy} onClick={() => void confirmPayment()}>J’ai payé · vérifier</button>}
              </>
            ) : (
              <>
                <p style={{ fontSize: '14px', margin: '8px 0 16px' }}>Temps restant : <b>{countdown}</b></p>
                {heldQuote && (
                  <p style={{ fontSize: '14px', marginBottom: '12px' }}>
                    Total à régler : <b>{money(heldQuote.total, heldQuote.currency)}</b>
                    {pendingTickets.length > 1 && ` (${pendingTickets.length} billets)`}
                  </p>
                )}
                <div style={{ display: 'flex', gap: '10px', flexWrap: 'wrap' }}>
                  {checkout?.payment_url && !paymentFailed && (
                    <a className="btn p" href={checkout.payment_url}>Reprendre le paiement</a>
                  )}
                  {(!checkout?.payment_url || paymentFailed) && payableQuotes.length === 1 && (
                    <button type="button" className="btn p" disabled={busy} onClick={() => void payHeld(payableQuotes[0].payment_method)}>
                      {busy ? "Patientez…" : paymentFailed ? "Réessayer le paiement" : `Payer ${money(payableQuotes[0].total, payableQuotes[0].currency)}`}
                    </button>
                  )}
                  {payableQuotes.length > 1 && onlineMethods.map((method) => (
                    <button key={method.id} type="button" className="btn" disabled={busy} onClick={() => void payHeld(method.id)}>Payer avec {method.label}</button>
                  ))}
                  {checkout && <button type="button" className="btn" disabled={busy} onClick={() => void confirmPayment()}>J’ai payé · vérifier</button>}
                  <button type="button" className="btn" disabled={busy} onClick={() => void cancelBooking()} style={{ borderColor: '#B42318', color: '#B42318' }}>Annuler la réservation</button>
                </div>
                {payableQuotes.length === 0 && <p style={{ fontSize: '14px' }}>Aucun paiement en ligne n’est disponible. Réglez votre billet au guichet.</p>}
              </>
            )}
          </div>
        )}
        
        {issued && pending && (
           <div style={{ background: 'var(--okbg)', color: 'var(--ok)', padding: '20px', borderRadius: '12px', marginTop: '20px', border: '1px solid #c3e6d3', textAlign: 'center' }}>
             <p style={{ fontWeight: 'bold', fontSize: '18px', marginBottom: '10px' }}>🎉 Voyage confirmé !</p>
             <p style={{ marginBottom: '16px' }}>
               {pendingTickets.length > 1
                 ? `${pendingTickets.length} billets ont été émis avec succès.`
                 : `Votre billet ${pending.reference} a été émis avec succès.`}
             </p>
             <div style={{ display: 'flex', flexDirection: 'column', gap: '10px', marginBottom: '16px' }}>
               {pendingTickets.map((ticket) => (
                 <div
                   key={ticket.id}
                   style={{
                     display: 'flex',
                     justifyContent: 'space-between',
                     alignItems: 'center',
                     background: '#fff',
                     padding: '12px 16px',
                     borderRadius: '10px',
                     border: '1px solid #c3e6d3',
                     textAlign: 'left',
                   }}
                 >
                   <div>
                     <div style={{ fontWeight: 700, color: 'var(--ink)' }}>{ticket.passenger_name}</div>
                     <div style={{ fontSize: '12px', color: 'var(--mute)' }}>
                       Siège N° {ticket.seat_detail?.number ?? ticket.seat} · Réf. {ticket.reference}
                     </div>
                   </div>
                   <a
                     href={`/t/${ticket.reference}`}
                     target="_blank"
                     rel="noreferrer"
                     onClick={clearGuestBooking}
                     className="btn p"
                     style={{
                       display: 'inline-flex',
                       background: 'var(--ok)',
                       borderColor: 'var(--ok)',
                       padding: '6px 14px',
                       fontSize: '13px',
                     }}
                   >
                     Télécharger le billet
                   </a>
                 </div>
               ))}
             </div>
             {!user && <p style={{ marginTop: '12px', fontSize: '13px' }}>Sans compte, ces billets ne sont pas conservés sur le site : téléchargez-les maintenant.</p>}
             <p style={{ marginTop: '16px' }}>
               <button type="button" className="btn" onClick={buyAnother}>Acheter d’autres billets</button>
             </p>
           </div>
        )}
      </div>

      <div className="card">
        <h3>Vos Billets</h3>
        <hr style={{ border: 0, borderBottom: '1px solid var(--line)', margin: '16px 0' }} />
        {tickets.length === 0 ? <p style={{ color: 'var(--mute)' }}>Vos billets apparaîtront ici.</p> : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
            {tickets.map((ticket) => (
              <div key={ticket.id} style={{ border: '1px solid var(--line)', borderRadius: '12px', padding: '16px', background: 'var(--bg)' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '16px' }}>
                  <div>
                    <h4 style={{ color: 'var(--navy)', marginBottom: '4px' }}>{ticket.trip_detail.route_detail.label}</h4>
                    <p style={{ fontSize: '13px', color: 'var(--mute)' }}>Départ : {formatDate(ticket.trip_detail.departure_at)}</p>
                    {ticket.trip_detail.boarding_at && <p style={{ fontSize: '13px', color: 'var(--mute)' }}>Embarquement : {formatDate(ticket.trip_detail.boarding_at)}</p>}
                  </div>
                  <span className={ticket.status === "ISSUED" ? "pill" : "pill ex"} style={{ alignSelf: 'flex-start' }}>{ticket.status_display}</span>
                </div>
                
                {["ISSUED", "CHECKED"].includes(ticket.status) && (
                  <div style={{ display: 'flex', justifyContent: 'center', padding: '20px', background: '#fff', borderRadius: '10px', marginBottom: '16px' }}>
                    <QRCodeSVG value={ticket.qr_token} size={140} fgColor="var(--navy)" level="M" />
                  </div>
                )}
                
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '10px', fontSize: '13px' }}>
                  <div><span style={{ color: 'var(--mute)', display: 'block', fontSize: '11px', textTransform: 'uppercase' }}>Réf.</span> {ticket.reference}</div>
                  <div><span style={{ color: 'var(--mute)', display: 'block', fontSize: '11px', textTransform: 'uppercase' }}>Siège</span> N°{ticket.seat_detail.number}</div>
                  <div><span style={{ color: 'var(--mute)', display: 'block', fontSize: '11px', textTransform: 'uppercase' }}>Passager</span> {ticket.passenger_name}</div>
                  <div><span style={{ color: 'var(--mute)', display: 'block', fontSize: '11px', textTransform: 'uppercase' }}>Prix du billet</span> {money(ticket.amount, ticket.currency)}</div>
                </div>
                {ticket.status === "HELD" && ticket.booking && (
                  <div style={{ marginTop: '14px' }}>
                    <p style={{ fontSize: '13px', color: 'var(--mute)', marginBottom: '8px' }}>Vous avez payé ? La confirmation peut prendre une minute.</p>
                    <button type="button" className="btn" disabled={paymentCheck?.ticketId === ticket.id && paymentCheck.busy} onClick={() => void checkTicketPayment(ticket)}>
                      {paymentCheck?.ticketId === ticket.id && paymentCheck.busy ? "Vérification…" : "Vérifier mon paiement"}
                    </button>
                    {paymentCheck?.ticketId === ticket.id && !paymentCheck.busy && <p role="status" style={{ fontSize: '13px', marginTop: '8px' }}>{paymentCheck.text}</p>}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
      <style>{`
        @media(max-width: 800px) {
          .responsive-grid { grid-template-columns: 1fr !important; }
        }
      `}</style>
    </div>
  );
}

// Le client ne crée jamais de colis : l'agence l'enregistre et remet un code de suivi.
function Parcels() {
  const [code, setCode] = useState("");
  const [result, setResult] = useState<ParcelTracking | null>(null);
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);

  async function track(event: FormEvent) {
    event.preventDefault();
    setMessage(""); setResult(null); setBusy(true);
    try {
      setResult(await apiFetch<ParcelTracking>(`/client/parcels/track/?code=${encodeURIComponent(code.trim())}`, {}, false));
    } catch (reason) { setMessage(reason instanceof Error ? reason.message : "Suivi indisponible."); }
    finally { setBusy(false); }
  }

  return (
    <div className="card" style={{ maxWidth: '640px' }}>
      <h3>Suivre un colis</h3>
      <hr style={{ border: 0, borderBottom: '1px solid var(--line)', margin: '16px 0' }} />
      <p style={{ color: 'var(--mute)', marginBottom: '16px' }}>Votre colis est enregistré en agence. Saisissez le code de suivi qui vous a été remis.</p>
      <form onSubmit={track} className="f">
        <label>Code de suivi</label>
        <input value={code} onChange={(e) => setCode(e.target.value)} placeholder="AX-COL-…" required />
        <button className="btn p" style={{ width: '100%', marginTop: '16px' }} disabled={busy}>{busy ? "Recherche…" : "Suivre mon colis"}</button>
      </form>
      {message && <div style={{ background: 'var(--tint)', color: 'var(--navy)', padding: '16px', borderRadius: '10px', marginTop: '20px' }}>{message}</div>}
      {result && (
        <div style={{ marginTop: '24px' }}>
          <div style={{ fontSize: '12px', fontWeight: 'bold', color: 'var(--mute)' }}>{result.tracking_number}</div>
          <div style={{ fontWeight: 'bold', color: 'var(--navy)', margin: '4px 0 16px' }}>{result.origin} → {result.destination}</div>
          <ol style={{ listStyle: 'none', padding: 0, margin: 0, display: 'flex', flexDirection: 'column', gap: '10px' }}>
            {result.steps.map((step) => (
              <li key={step.key} style={{ display: 'flex', alignItems: 'center', gap: '12px', opacity: step.done ? 1 : 0.45 }}>
                <span style={{ width: '22px', height: '22px', borderRadius: '50%', display: 'inline-grid', placeItems: 'center', fontSize: '12px', color: '#fff', background: step.done ? 'var(--ok)' : 'var(--line)' }}>{step.done ? "✓" : ""}</span>
                <span style={{ fontWeight: step.current ? 'bold' : 'normal' }}>{step.label}</span>
                {step.reached_at && <span style={{ marginLeft: 'auto', fontSize: '12px', color: 'var(--mute)' }}>{formatDate(step.reached_at)}</span>}
              </li>
            ))}
          </ol>
        </div>
      )}
    </div>
  );
}

function Rentals({ user, vehicles, rentals, onAuthenticated, onChanged }: { user: User | null; vehicles: Vehicle[]; rentals: RentalBooking[]; onAuthenticated: () => Promise<void>; onChanged: () => Promise<void> }) {
  // Simplified rentals UI
  return (
    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '30px' }} className="responsive-grid">
      <div className="card">
        <h3>Véhicules disponibles</h3>
        <hr style={{ border: 0, borderBottom: '1px solid var(--line)', margin: '16px 0' }} />
        {vehicles.length === 0 ? <p style={{ color: 'var(--mute)' }}>Aucun véhicule publié.</p> : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
            {vehicles.map(v => (
              <div key={v.id} style={{ border: '1px solid var(--line)', padding: '16px', borderRadius: '12px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <div>
                  <h4 style={{ color: 'var(--navy)' }}>{v.name}</h4>
                  <p style={{ fontSize: '13px', color: 'var(--mute)' }}>{v.capacity} places · {money(v.rental_daily_rate)} / jour</p>
                </div>
                <button className="btn s p">Louer</button>
              </div>
            ))}
          </div>
        )}
      </div>
      <div className="card">
        <h3>Vos demandes</h3>
        <hr style={{ border: 0, borderBottom: '1px solid var(--line)', margin: '16px 0' }} />
        {!user ? <LoginCard title="Connectez-vous" allowRegistration onSuccess={() => void onAuthenticated()} /> : rentals.length === 0 ? <p style={{ color: 'var(--mute)' }}>Aucune demande en cours.</p> : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
            {rentals.map(r => (
              <div key={r.id} style={{ background: 'var(--bg)', padding: '12px', borderRadius: '8px', display: 'flex', justifyContent: 'space-between' }}>
                <span>{r.vehicle_detail.name}</span>
                <span className="pill ex">{r.status_display}</span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function Profile({ user, tickets, parcels, rentals, onAuthenticated, onLogout }: { user: User | null; tickets: Ticket[]; parcels: Parcel[]; rentals: RentalBooking[]; onAuthenticated: () => Promise<void>; onLogout: () => void }) {
  if (!user) return <div style={{ maxWidth: '400px', margin: '0 auto' }}><LoginCard title="Connexion" allowRegistration onSuccess={() => void onAuthenticated()} /></div>;
  
  return (
    <div style={{ maxWidth: '600px', margin: '0 auto' }} className="card">
      <div style={{ display: 'flex', alignItems: 'center', gap: '20px', marginBottom: '30px' }}>
        <div style={{ width: '80px', height: '80px', background: 'var(--navy)', color: '#fff', borderRadius: '20px', display: 'grid', placeItems: 'center', fontSize: '28px', fontWeight: 'bold' }}>
          {(user.first_name[0] || user.username[0]).toUpperCase()}
        </div>
        <div>
          <h3 style={{ fontSize: '22px' }}>{[user.first_name, user.last_name].filter(Boolean).join(" ") || user.username}</h3>
          <p style={{ color: 'var(--mute)' }}>{user.phone || user.email || user.role_display}</p>
        </div>
      </div>
      
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '16px', marginBottom: '40px' }}>
        <div style={{ background: 'var(--bg)', padding: '20px', borderRadius: '16px', textAlign: 'center' }}>
          <div style={{ fontSize: '28px', fontWeight: 'bold', color: 'var(--navy)' }}>{tickets.length}</div>
          <div style={{ fontSize: '13px', color: 'var(--mute)' }}>Billets</div>
        </div>
        <div style={{ background: 'var(--bg)', padding: '20px', borderRadius: '16px', textAlign: 'center' }}>
          <div style={{ fontSize: '28px', fontWeight: 'bold', color: 'var(--navy)' }}>{parcels.length}</div>
          <div style={{ fontSize: '13px', color: 'var(--mute)' }}>Colis</div>
        </div>
        <div style={{ background: 'var(--bg)', padding: '20px', borderRadius: '16px', textAlign: 'center' }}>
          <div style={{ fontSize: '28px', fontWeight: 'bold', color: 'var(--navy)' }}>{rentals.length}</div>
          <div style={{ fontSize: '13px', color: 'var(--mute)' }}>Locations</div>
        </div>
      </div>
      
      <button className="btn" style={{ width: '100%', borderColor: 'var(--warn)', color: 'var(--warn)' }} onClick={onLogout}>Se déconnecter</button>
    </div>
  );
}

// Téléphone de contact : lien d'appel seulement si le numéro est valide ; sinon le texte seul.
function PhoneText({ value }: { value: string }) {
  const href = phoneHref(value);
  return href ? <a href={href} style={{ color: 'inherit', textDecoration: 'underline' }}>{value}</a> : <>{value}</>;
}

// Icône WhatsApp : seulement si un numéro international est renseigné (sinon rien).
function WhatsAppIcon({ value }: { value: string }) {
  const href = whatsappHref(value);
  if (!href) return null;
  return (
    <a href={href} target="_blank" rel="noopener noreferrer" aria-label="Écrire sur WhatsApp" title="WhatsApp" style={{ display: 'inline-flex', color: 'inherit' }}>
      <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
        <path d="M12 2a10 10 0 0 0-8.6 15.1L2 22l5-1.3A10 10 0 1 0 12 2zm0 18.2a8.2 8.2 0 0 1-4.2-1.2l-.3-.2-3 .8.8-2.9-.2-.3A8.2 8.2 0 1 1 12 20.2zm4.5-6.1c-.2-.1-1.5-.7-1.7-.8s-.4-.1-.6.1-.7.8-.8 1-.3.2-.5.1a6.7 6.7 0 0 1-3.3-2.9c-.2-.4.2-.4.7-1.3.1-.2 0-.3 0-.4l-.8-1.8c-.2-.5-.4-.4-.6-.4h-.5a1 1 0 0 0-.7.3 3 3 0 0 0-.9 2.2 5.2 5.2 0 0 0 1.1 2.7 11.8 11.8 0 0 0 4.5 4c1.7.7 2.3.8 3.2.6a2.7 2.7 0 0 0 1.8-1.3 2.2 2.2 0 0 0 .2-1.3c-.1-.1-.3-.2-.5-.3z" />
      </svg>
    </a>
  );
}
