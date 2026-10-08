"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import { QRCodeSVG } from "qrcode.react";
import { apiFetch, apiList, clearTokens, formatDate, getAccessToken, money } from "@/lib/api";
import type { Checkout, Contact, Location, Parcel, PaymentMethod, RentalBooking, Seat, Ticket, Trip, User, Vehicle } from "@/lib/types";
import { LoginCard } from "./login-card";

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
  
  // Derived state: Filtered Trips based on Search
  const filteredTrips = trips.filter(trip => {
    let match = true;
    if (searchOrigin && trip.route_detail.origin !== Number(searchOrigin)) match = false;
    if (searchDestination && trip.route_detail.destination !== Number(searchDestination)) match = false;
    if (searchDate) {
      const tripDate = new Date(trip.departure_at).toISOString().split('T')[0];
      if (tripDate !== searchDate) match = false;
    }
    return match;
  });

  return (
    <>
      <div className="top">
        <div className="wrap">
          <span>Axe Parakou – Cotonou</span>
          {contact.contact_phone && <span>Téléphone : {contact.contact_phone}</span>}
          <span>Voyagez en toute confiance</span>
        </div>
      </div>
      
      <header>
        <div className="wrap nav">
          <a className="logo" href="#" onClick={(e) => { e.preventDefault(); setTab("accueil"); }}>
            <i>A</i>AXIS Transport
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
                    <select value={searchOrigin} onChange={(e) => setSearchOrigin(e.target.value)}>
                      <option value="">Toutes origines</option>
                      {locations.map(loc => <option key={loc.id} value={loc.id}>{loc.name}</option>)}
                    </select>
                  </div>
                  <div className="f">
                    <label>Destination</label>
                    <select value={searchDestination} onChange={(e) => setSearchDestination(e.target.value)}>
                      <option value="">Toutes destinations</option>
                      {locations.map(loc => <option key={loc.id} value={loc.id}>{loc.name}</option>)}
                    </select>
                  </div>
                  <div className="f">
                    <label>Date de départ</label>
                    <input type="date" value={searchDate} onChange={(e) => setSearchDate(e.target.value)} />
                  </div>
                  <div className="f">
                    <label>Passagers</label>
                    <select>
                      <option value="1">1 passager</option>
                      <option value="2">2 passagers</option>
                      <option value="3">3 passagers</option>
                    </select>
                  </div>
                  <button className="btn p" onClick={() => setTab("billets")}>Rechercher</button>
                </div>

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
                            {/* Dummy arrival time for mockup, could calculate via duration */}
                            <span>Arrivée <b>--:--</b></span>
                          </div>
                          <div className="b">
                            <span className="price">{trip.current_fare ? money(trip.current_fare.amount, trip.current_fare.currency) : "Sur devis"}</span>
                            <button className="btn p s" onClick={() => setTab("billets")}>Réserver</button>
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
                        <h3>Expédition de colis</h3>
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
              <Tickets user={user} trips={trips} tickets={tickets} paymentMethods={paymentMethods} onAuthenticated={loadPrivate} onChanged={loadPrivate} />
            </main>
          )}
          
          {tab === "colis" && (
            <main className="wrap section-margin" style={{ paddingBottom: '60px' }}>
              <h2>Expédition de colis</h2>
              <p className="sub">Déclarez vos envois et suivez l'acheminement en temps réel.</p>
              <Parcels user={user} locations={locations} parcels={parcels} onAuthenticated={loadPrivate} onChanged={loadPrivate} />
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
                <i style={{ background: '#fff', color: 'var(--navy)' }}>A</i>AXIS Transport
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
              <p style={{ opacity: '.8', marginBottom: '6px' }}>Téléphone : {contact.contact_phone || "À renseigner"}</p>
              <p style={{ opacity: '.8', marginBottom: '10px' }}>WhatsApp : {contact.contact_whatsapp || "À renseigner"}</p>
              {contact.contact_phone && <a className="btn s" href={`tel:${contact.contact_phone.replace(/[^+\d]/g, "")}`}>Appeler</a>}
              {contact.contact_whatsapp && <a className="btn s" style={{ marginLeft: contact.contact_phone ? '8px' : 0 }} href={`https://wa.me/${contact.contact_whatsapp.replace(/\D/g, "")}`} target="_blank" rel="noreferrer">WhatsApp</a>}
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

function Tickets({ user, trips, tickets, paymentMethods, onAuthenticated, onChanged }: { user: User | null; trips: Trip[]; tickets: Ticket[]; paymentMethods: PaymentMethod[]; onAuthenticated: () => Promise<void>; onChanged: () => Promise<void> }) {
  const [tripId, setTripId] = useState("");
  const [seats, setSeats] = useState<Seat[]>([]);
  const [seatId, setSeatId] = useState("");
  const [passengerName, setPassengerName] = useState("");
  const [phone, setPhone] = useState("");
  const [pending, setPending] = useState<Ticket | null>(null);
  const [checkout, setCheckout] = useState<Checkout | null>(null);
  const [message, setMessage] = useState("");
  const selectedTrip = trips.find((trip) => String(trip.id) === tripId);

  useEffect(() => {
    if (user) {
      setPassengerName((current) => current || [user.first_name, user.last_name].filter(Boolean).join(" ") || user.username);
      setPhone((current) => current || user.phone || "");
    }
  }, [user]);

  useEffect(() => {
    if (!tripId) return setSeats([]);
    apiList<Seat>(`/client/seats/?trip=${tripId}`, false).then(setSeats).catch((reason) => setMessage(reason.message));
  }, [tripId]);

  async function reserve(event: FormEvent) {
    event.preventDefault();
    setMessage("");
    try {
      const ticket = await apiFetch<Ticket>("/client/tickets/", { method: "POST", body: JSON.stringify({ trip: Number(tripId), seat: Number(seatId), passenger_name: passengerName, passenger_phone: phone }) }, !!user);
      setPending(ticket);
      setCheckout(null);
      setMessage("Siège réservé temporairement. Finalisez le paiement avant l’expiration.");
      await onChanged();
    } catch (reason) { setMessage(reason instanceof Error ? reason.message : "Réservation impossible."); }
  }

  // Le serveur crée la transaction et fixe le montant ; le site ne fait qu'ouvrir la page de paiement.
  async function startPayment(method: PaymentMethod) {
    if (!pending) return;
    setMessage("");
    try {
      const created = await apiFetch<Checkout>(`/client/tickets/${pending.id}/checkout/`, { method: "POST", body: JSON.stringify({ payment_method: method.id }) });
      setCheckout(created);
      if (created.payment_url) {
        window.open(created.payment_url, "_blank", "noopener");
        setMessage("La page de paiement s’est ouverte dans un nouvel onglet. Revenez ici une fois le paiement terminé.");
      } else {
        await confirmPayment(created);
      }
    } catch (reason) { setMessage(reason instanceof Error ? reason.message : "Paiement impossible."); }
  }

  async function confirmPayment(current: Checkout | null = checkout) {
    if (!pending || !current) return;
    setMessage("");
    try {
      const response = await apiFetch<{ ticket: Ticket }>(`/client/tickets/${pending.id}/pay/`, { method: "POST", body: JSON.stringify({ payment_method: current.payment_method, external_reference: current.transaction_id }) });
      setPending(response.ticket);
      setCheckout(null);
      setMessage("Paiement confirmé, ticket émis.");
      await onChanged();
    } catch (reason) { setMessage(reason instanceof Error ? reason.message : "Paiement non confirmé."); }
  }

  return (
    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '30px' }} className="responsive-grid">
      <div className="card">
        <h3>Réserver un billet</h3>
        <hr style={{ border: 0, borderBottom: '1px solid var(--line)', margin: '16px 0' }} />
        {trips.length === 0 ? <p>Aucun trajet disponible.</p> : (
          <form onSubmit={reserve} className="f">
            <label style={{ marginTop: '10px' }}>Voyage</label>
            <select value={tripId} onChange={(e) => { setTripId(e.target.value); setSeatId(""); }} required>
              <option value="">Choisir un départ</option>
              {trips.map((trip) => <option key={trip.id} value={trip.id}>{trip.route_detail.label} — {formatDate(trip.departure_at)}</option>)}
            </select>
            
            {seats.length > 0 && (
              <div style={{ marginTop: '20px' }}>
                <label>Plan de sièges</label>
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: '10px' }}>
                  {seats.map((seat) => (
                    <button type="button" key={seat.id} disabled={seat.status !== "AVAILABLE"} onClick={() => setSeatId(String(seat.id))} 
                      style={{ 
                        aspectRatio: '1/1', borderRadius: '8px', fontWeight: 'bold', fontSize: '14px', border: '1px solid var(--line)',
                        background: seatId === String(seat.id) ? 'var(--blue)' : seat.status === "AVAILABLE" ? '#fff' : 'var(--bg)',
                        color: seatId === String(seat.id) ? '#fff' : seat.status === "AVAILABLE" ? 'var(--ink)' : 'var(--mute)',
                        cursor: seat.status === "AVAILABLE" ? 'pointer' : 'not-allowed'
                      }}
                    >
                      {seat.number}
                    </button>
                  ))}
                </div>
              </div>
            )}

            <label style={{ marginTop: '20px' }}>Nom du passager</label>
            <input value={passengerName} onChange={(e) => setPassengerName(e.target.value)} required />
            
            <label style={{ marginTop: '20px' }}>Téléphone</label>
            <input value={phone} onChange={(e) => setPhone(e.target.value)} />
            
            <button className="btn p" style={{ marginTop: '30px', width: '100%' }} disabled={!seatId || !selectedTrip?.current_fare}>
              Réserver {selectedTrip?.current_fare ? ` · ${money(selectedTrip.current_fare.amount, selectedTrip.current_fare.currency)}` : ""}
            </button>
          </form>
        )}
        
        {message && <div style={{ background: 'var(--tint)', color: 'var(--navy)', padding: '16px', borderRadius: '10px', marginTop: '20px' }}>{message}</div>}
        
        {pending?.status === "HELD" && (
          <div style={{ background: 'var(--warnbg)', color: 'var(--warn)', padding: '20px', borderRadius: '12px', marginTop: '20px', border: '1px solid #f2dfb6' }}>
            <p style={{ fontWeight: 'bold', marginBottom: '8px' }}>Finaliser la réservation {pending.reference}</p>
            <p style={{ fontSize: '14px', marginBottom: '16px' }}>Expiration : {pending.reservation_expires_at ? formatDate(pending.reservation_expires_at) : "—"}</p>
            {checkout && (
              <div style={{ marginBottom: '16px' }}>
                <p style={{ fontSize: '14px' }}>Prix : {money(checkout.amount, checkout.currency)} · Frais de paiement : {money(checkout.fee_amount, checkout.currency)}</p>
                <p style={{ fontWeight: 'bold', margin: '6px 0 12px' }}>Total à payer : {money(checkout.total, checkout.currency)}</p>
                <div style={{ display: 'flex', gap: '10px', flexWrap: 'wrap' }}>
                  {checkout.payment_url && <a className="btn" href={checkout.payment_url} target="_blank" rel="noreferrer">Rouvrir la page de paiement</a>}
                  <button type="button" className="btn p" onClick={() => void confirmPayment()}>J’ai payé · vérifier</button>
                </div>
              </div>
            )}
            <div style={{ display: 'flex', gap: '10px', flexWrap: 'wrap' }}>
              {paymentMethods.filter((method) => method.online).map((method) => (
                <button key={method.id} type="button" className="btn" onClick={() => void startPayment(method)}>Payer avec {method.label}</button>
              ))}
            </div>
            {paymentMethods.filter((method) => method.online).length === 0 && <p style={{ fontSize: '14px' }}>Aucun paiement en ligne n’est disponible. Réglez votre billet au guichet.</p>}
          </div>
        )}
        
        {pending?.status === "ISSUED" && (
           <div style={{ background: 'var(--okbg)', color: 'var(--ok)', padding: '20px', borderRadius: '12px', marginTop: '20px', border: '1px solid #c3e6d3', textAlign: 'center' }}>
             <p style={{ fontWeight: 'bold', fontSize: '18px', marginBottom: '10px' }}>🎉 Voyage confirmé !</p>
             <p style={{ marginBottom: '16px' }}>Votre billet {pending.reference} a été émis avec succès.</p>
             <a href={`/t/${pending.reference}`} target="_blank" rel="noreferrer" className="btn p" style={{ display: 'inline-flex', background: 'var(--ok)', borderColor: 'var(--ok)' }}>
               Consulter & Télécharger mon billet
             </a>
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
                    <p style={{ fontSize: '13px', color: 'var(--mute)' }}>{formatDate(ticket.trip_detail.departure_at)}</p>
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
                  <div><span style={{ color: 'var(--mute)', display: 'block', fontSize: '11px', textTransform: 'uppercase' }}>Tarif</span> {money(ticket.amount, ticket.currency)}</div>
                </div>
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

function Parcels({ user, locations, parcels, onAuthenticated, onChanged }: { user: User | null; locations: Location[]; parcels: Parcel[]; onAuthenticated: () => Promise<void>; onChanged: () => Promise<void> }) {
  const [form, setForm] = useState({ sender_name: "", sender_phone: "", recipient_name: "", recipient_phone: "", origin: "", destination: "", description: "", weight_kg: "" });
  const [message, setMessage] = useState("");
  async function submit(event: FormEvent) { 
    event.preventDefault(); setMessage(""); 
    try { 
      await apiFetch<Parcel>("/client/parcels/", { method: "POST", body: JSON.stringify({ ...form, origin: Number(form.origin), destination: Number(form.destination), weight_kg: form.weight_kg || null }) }); 
      setMessage("Colis enregistré. Le numéro de suivi est disponible dans votre historique."); 
      await onChanged(); 
    } catch (reason) { setMessage(reason instanceof Error ? reason.message : "Enregistrement impossible."); } 
  }
  
  return (
    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '30px' }} className="responsive-grid">
      <div className="card">
        <h3>Déclarer un colis</h3>
        <hr style={{ border: 0, borderBottom: '1px solid var(--line)', margin: '16px 0' }} />
        {!user ? <LoginCard title="Connectez-vous pour expédier" allowRegistration onSuccess={() => void onAuthenticated()} /> : (
          <form onSubmit={submit} className="f" style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
            <div style={{ gridColumn: '1 / -1' }}><label>Description</label><input value={form.description} onChange={(v) => setForm({...form, description: v.target.value})} required /></div>
            <div><label>Expéditeur</label><input value={form.sender_name} onChange={(v) => setForm({...form, sender_name: v.target.value})} required /></div>
            <div><label>Tél expéditeur</label><input value={form.sender_phone} onChange={(v) => setForm({...form, sender_phone: v.target.value})} required /></div>
            <div><label>Destinataire</label><input value={form.recipient_name} onChange={(v) => setForm({...form, recipient_name: v.target.value})} required /></div>
            <div><label>Tél destinataire</label><input value={form.recipient_phone} onChange={(v) => setForm({...form, recipient_phone: v.target.value})} required /></div>
            <div><label>Départ</label><select value={form.origin} onChange={(v) => setForm({...form, origin: v.target.value})} required><option value="">Choisir</option>{locations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}</select></div>
            <div><label>Arrivée</label><select value={form.destination} onChange={(v) => setForm({...form, destination: v.target.value})} required><option value="">Choisir</option>{locations.map(l => <option key={l.id} value={l.id}>{l.name}</option>)}</select></div>
            <div style={{ gridColumn: '1 / -1' }}><button className="btn p" style={{ width: '100%', marginTop: '10px' }}>Enregistrer</button></div>
          </form>
        )}
        {message && <div style={{ background: 'var(--tint)', color: 'var(--navy)', padding: '16px', borderRadius: '10px', marginTop: '20px' }}>{message}</div>}
      </div>
      <div className="card">
        <h3>Historique de suivi</h3>
        <hr style={{ border: 0, borderBottom: '1px solid var(--line)', margin: '16px 0' }} />
        {parcels.length === 0 ? <p style={{ color: 'var(--mute)' }}>Aucun historique d'expédition.</p> : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
            {parcels.map(parcel => (
              <div key={parcel.id} style={{ border: '1px solid var(--line)', borderRadius: '10px', padding: '16px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
                  <span style={{ fontSize: '12px', fontWeight: 'bold', color: 'var(--mute)' }}>{parcel.tracking_number}</span>
                  <span className="pill">{parcel.status_display}</span>
                </div>
                <div style={{ fontWeight: 'bold', color: 'var(--navy)' }}>{parcel.origin_detail.name} → {parcel.destination_detail.name}</div>
              </div>
            ))}
          </div>
        )}
      </div>
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
