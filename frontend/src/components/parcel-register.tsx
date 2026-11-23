"use client";

import { FormEvent, useEffect, useState } from "react";

import { apiFetch, apiList, money } from "@/lib/api";
import { parcelFormError, type ParcelDraft } from "@/lib/portal-rules";
import type { Location, PaymentMethod } from "@/lib/types";
import { SectionHeading, useActionFeedback } from "./ui";

type Receipt = { tracking_number: string; origin: string; destination: string; amount: number | null; currency: string; paid: boolean; payment_mode: string };
type Created = { id: number; tracking_number: string; amount: string | number | null };

// Réduction des photos avant l'envoi (comme l'application) : une photo de téléphone dépasse souvent 5 Mo,
// limite du serveur. Plus grand côté 1600 px, JPEG ; en cas d'échec du navigateur, le fichier part tel quel.
const MAX_SIDE_PX = 1600;
async function shrinkPhoto(file: File): Promise<File> {
  try {
    const bitmap = await createImageBitmap(file);
    const scale = Math.min(1, MAX_SIDE_PX / Math.max(bitmap.width, bitmap.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(bitmap.width * scale);
    canvas.height = Math.round(bitmap.height * scale);
    canvas.getContext("2d")?.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    bitmap.close();
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.82));
    return blob ? new File([blob], "colis.jpg", { type: "image/jpeg" }) : file;
  } catch { return file; }
}

const emptyDraft: ParcelDraft = { sender_name: "", sender_phone: "", recipient_name: "", recipient_phone: "", origin: "", destination: "", description: "" };

// Enregistrement d'un colis au guichet (et dans l'admin) : même route et mêmes règles que l'application
// (POST /staff/sales/parcel/ avec 1 à 3 photos, puis encaissement /parcels/<id>/pay/). Le prix vient du serveur.
export function ParcelRegister() {
  const feedback = useActionFeedback();
  const [places, setPlaces] = useState<Location[]>([]);
  const [methods, setMethods] = useState<PaymentMethod[]>([]);
  const [draft, setDraft] = useState<ParcelDraft>(emptyDraft);
  const [photos, setPhotos] = useState<File[]>([]);
  const [busy, setBusy] = useState(false);
  const [created, setCreated] = useState<Created | null>(null);
  const [receipt, setReceipt] = useState<Receipt | null>(null);
  const [paymentUrl, setPaymentUrl] = useState<string | null>(null);

  useEffect(() => {
    apiList<Location>("/client/locations/", false).then((rows) => setPlaces(rows.filter((row) => row.active))).catch(() => undefined);
    apiList<PaymentMethod>("/payment-methods/").then((rows) => setMethods(rows.filter((row) => row.active))).catch(() => undefined);
  }, []);

  const set = (key: keyof ParcelDraft) => (value: string) => setDraft({ ...draft, [key]: value });

  async function register(event: FormEvent) {
    event.preventDefault();
    const problem = parcelFormError(draft, photos.length);
    if (problem) { feedback.failure(null, problem); return; }
    const body = new FormData();
    Object.entries(draft).forEach(([key, value]) => body.append(key, value.trim()));
    setBusy(true);
    try {
      (await Promise.all(photos.map(shrinkPhoto))).forEach((photo) => body.append("photos", photo));
      const result = await apiFetch<Created>("/staff/sales/parcel/", { method: "POST", body });
      setCreated(result);
      feedback.success(`Colis ${result.tracking_number} enregistré. Encaissez-le maintenant.`);
    } catch (reason) { feedback.failure(reason, "Le colis n’a pas été enregistré."); }
    finally { setBusy(false); }
  }

  async function pay(method: PaymentMethod) {
    if (!created) return;
    setBusy(true);
    try {
      const result = await apiFetch<{ checkout: { payment_url?: string | null } | null; receipt: Receipt }>(`/parcels/${created.id}/pay/`, { method: "POST", body: JSON.stringify({ payment_method: method.id }) });
      setReceipt(result.receipt);
      setPaymentUrl(result.checkout?.payment_url ?? null);
      if (result.receipt.paid) feedback.success(`Colis ${created.tracking_number} encaissé.`);
    } catch (reason) { feedback.failure(reason, "L’encaissement n’a pas abouti."); }
    finally { setBusy(false); }
  }

  async function verify() {
    if (!created) return;
    setBusy(true);
    try {
      const result = await apiFetch<{ receipt: Receipt }>(`/parcels/${created.id}/verify/`, { method: "POST", body: "{}" });
      setReceipt(result.receipt);
      if (result.receipt.paid) feedback.success("Paiement reçu.");
      else feedback.failure(null, "Paiement pas encore reçu. Réessayez dans un instant.");
    } catch (reason) { feedback.failure(reason, "La vérification n’a pas abouti."); }
    finally { setBusy(false); }
  }

  function restart() { setDraft(emptyDraft); setPhotos([]); setCreated(null); setReceipt(null); setPaymentUrl(null); }

  const field = (key: keyof ParcelDraft, label: string, type = "text") => (
    <label className="block"><span className="field-label">{label}</span>
      <input className="field" type={type} inputMode={type === "tel" ? "tel" : undefined} value={draft[key]} onChange={(e) => set(key)(e.target.value)} />
    </label>
  );
  const city = (key: "origin" | "destination", label: string, other: string) => (
    <label className="block"><span className="field-label">{label}</span>
      <select className="field" value={draft[key]} onChange={(e) => set(key)(e.target.value)}>
        <option value="">Choisir</option>
        {places.filter((place) => String(place.id) !== other).map((place) => <option key={place.id} value={place.id}>{place.name}</option>)}
      </select>
    </label>
  );

  return (
    <section className="card mt-5 min-w-0">
      <SectionHeading eyebrow="Colis déposé au guichet" title="Enregistrer un colis" />
      {!created ? (
        <form onSubmit={register} className="grid gap-3 sm:grid-cols-2">
          {field("sender_name", "Nom de l’expéditeur")}
          {field("sender_phone", "Téléphone de l’expéditeur", "tel")}
          {field("recipient_name", "Nom du destinataire")}
          {field("recipient_phone", "Téléphone du destinataire", "tel")}
          {city("origin", "Ville de départ", draft.destination)}
          {city("destination", "Ville d’arrivée", draft.origin)}
          <label className="block sm:col-span-2"><span className="field-label">Description du colis</span>
            <input className="field" value={draft.description} onChange={(e) => set("description")(e.target.value)} placeholder="Ex. : carton, sac, contenu" />
          </label>
          <label className="block sm:col-span-2"><span className="field-label">Photos du colis (1 à 3)</span>
            <input className="field" type="file" accept="image/*" capture="environment" multiple onChange={(e) => setPhotos(Array.from(e.target.files ?? []).slice(0, 3))} />
            <span className="mt-1 block text-xs text-slate-500">{photos.length ? `${photos.length} photo(s) choisie(s).` : "Prenez ou choisissez au moins une photo."}</span>
          </label>
          <button className="primary-button sm:col-span-2" disabled={busy}>{busy ? "Enregistrement…" : "Enregistrer le colis"}</button>
        </form>
      ) : (
        <div className="space-y-3">
          <p className="text-lg font-extrabold break-all">{created.tracking_number}</p>
          <p className="text-sm">Prix : <b>{created.amount !== null && created.amount !== "" ? money(created.amount) : "À renseigner par l’agence"}</b></p>
          {!receipt?.paid && (
            <div className="flex flex-wrap gap-2">
              {methods.map((method) => <button key={method.id} type="button" className="primary-button" disabled={busy || created.amount === null} onClick={() => void pay(method)}>Encaisser · {method.label}</button>)}
              {paymentUrl && <a className="secondary-button" href={paymentUrl} target="_blank" rel="noopener noreferrer">Ouvrir la page de paiement</a>}
              {paymentUrl && <button type="button" className="secondary-button" disabled={busy} onClick={() => void verify()}>Vérifier le paiement</button>}
            </div>
          )}
          {receipt?.paid && <p className="notice">Encaissé ({receipt.payment_mode}) · {receipt.origin} → {receipt.destination}</p>}
          <button type="button" className="text-button" onClick={restart}>Nouveau colis</button>
        </div>
      )}
    </section>
  );
}
