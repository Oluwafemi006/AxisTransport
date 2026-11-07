// Pages publiques /privacy et /suppression-compte : HTML simple produit sur le serveur, sans aucun script,
// lisible sans connexion. Contenu fondé uniquement sur ce que fait le code ; les points ouverts sont marqués « À valider ».

export interface PrivacyContact {
  legal_name: string;
  email: string;
  contact_phone: string;
  contact_whatsapp: string;
}

export const EMPTY_CONTACT: PrivacyContact = { legal_name: "", email: "", contact_phone: "", contact_whatsapp: "" };

function escape(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

// Coordonnées saisies dans /admin (adresse publique /client/privacy-contact/) ; vides si l'API ne répond pas.
export function readPrivacyContact(payload: unknown): PrivacyContact {
  const source = (payload && typeof payload === "object" ? payload : {}) as Record<string, unknown>;
  const text = (key: keyof PrivacyContact) => (typeof source[key] === "string" ? (source[key] as string).trim() : "");
  return { legal_name: text("legal_name"), email: text("email"), contact_phone: text("contact_phone"), contact_whatsapp: text("contact_whatsapp") };
}

const toValidate = (what: string) => ` <span class="v">À valider : ${escape(what)}</span>`;

function companyName(contact: PrivacyContact) {
  return escape(contact.legal_name || "Axis Transport");
}

function contactBlock(contact: PrivacyContact) {
  const lines = [["E-mail", contact.email], ["Téléphone", contact.contact_phone], ["WhatsApp", contact.contact_whatsapp]].filter(([, value]) => value);
  if (lines.length === 0) return "<p>Coordonnées : À renseigner.</p>";
  return `<ul>${lines.map(([label, value]) => `<li>${label} : ${escape(value)}</li>`).join("")}</ul>`;
}

function page(title: string, body: string) {
  return `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escape(title)} · Axis Transport</title>
<style>
body{margin:0;background:#fff;color:#1f2937;font:16px/1.6 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:760px;margin:0 auto;padding:24px 16px 48px}
h1{font-size:1.6rem;margin:12px 0 16px;color:#0b3c74}
h2{font-size:1.15rem;margin:24px 0 8px}
ul{padding-left:20px}li{margin:4px 0}
a{color:#0b3c74}
.v{display:inline-block;padding:0 6px;border-radius:4px;background:#fef3c7;color:#92400e;font-weight:600;font-size:.9em}
.links{margin-top:32px;font-size:.9rem}
</style>
</head>
<body>
<main>
<p><a href="/">← Axis Transport</a></p>
<h1>${escape(title)}</h1>
${body}
<p class="links"><a href="/privacy">Politique de confidentialité</a> · <a href="/suppression-compte">Suppression de compte</a></p>
</main>
</body>
</html>`;
}

export function privacyPage(contact: PrivacyContact): string {
  const name = companyName(contact);
  return page("Politique de confidentialité", `
<p>Cette page décrit les données utilisées par le site et l’application ${name} : billets de car, colis et location de véhicules.</p>
<h2>Responsable et contact</h2>
<p>${name}.${toValidate("personne responsable des données personnelles")}</p>
${contactBlock(contact)}
<h2>Données que nous utilisons</h2>
<ul>
<li><strong>Compte client</strong> : identifiant, prénom, nom, téléphone, e-mail et mot de passe (gardé sous forme chiffrée, jamais lisible).</li>
<li><strong>Billets</strong> : nom et téléphone de chaque passager, téléphone et e-mail de contact, numéro IFU s’il est saisi, trajet, siège, points de montée et de descente, montant.</li>
<li><strong>Colis</strong> : nom et téléphone de l’expéditeur et du destinataire, description du colis, photos du colis prises par le personnel, identité de la personne qui le retire.</li>
<li><strong>Locations</strong> : véhicule, dates, option chauffeur, montant et caution fixés par l’agence.</li>
<li><strong>Paiements</strong> : montant, numéro de la transaction Mobile Money et statut du paiement.</li>
<li><strong>Contrôle des billets</strong> : heure du contrôle et agent qui l’a fait.</li>
<li><strong>Historique</strong> : les modifications faites sur un compte, une location ou un billet sont enregistrées, avec leur date et leur auteur.</li>
</ul>
<h2>Ce que nous n’utilisons pas</h2>
<ul>
<li>Aucune localisation de votre téléphone.</li>
<li>Aucune notification envoyée sur votre téléphone.</li>
<li>Aucun outil de mesure d’audience ni de publicité.</li>
<li>Aucun enregistrement du son.</li>
</ul>
<h2>Sur votre téléphone ou votre navigateur</h2>
<ul>
<li>Votre session de connexion et une copie de vos billets confirmés (pour les montrer sans réseau) restent sur votre appareil.</li>
<li>Le verrouillage par empreinte ou visage est vérifié par votre téléphone : l’application ne reçoit jamais votre empreinte ni votre visage.</li>
<li>La caméra sert seulement au personnel, pour scanner les billets et photographier les colis.</li>
</ul>
<h2>Qui y a accès</h2>
<ul>
<li>Vous, depuis votre compte.</li>
<li>Le personnel de l’agence (guichet, contrôle, administration), selon son rôle.</li>
<li>Toute personne qui connaît la référence d’un billet peut voir la page publique du billet : nom du passager, trajet et siège.</li>
</ul>
<h2>Prestataires</h2>
<ul>
<li><strong>FedaPay</strong>, pour le paiement Mobile Money : nous lui transmettons le montant et la référence de la réservation, du billet ou du colis, jamais votre nom ni votre téléphone. Vous saisissez votre numéro de paiement directement sur sa page.</li>
<li><strong>Cloudinary</strong>, pour conserver les photos des colis et des véhicules.</li>
<li><strong>Un service d’envoi d’e-mails</strong>, pour les codes « mot de passe oublié ».${toValidate("nom du service")}</li>
<li><strong>L’hébergeur du serveur.</strong>${toValidate("nom et pays de l’hébergeur")}</li>
</ul>
<h2>Sécurité</h2>
<p>Les échanges entre l’application, le site et le serveur passent par une connexion chiffrée (HTTPS). Un code « mot de passe oublié » n’est valable que 15 minutes.</p>
<h2>Durée de conservation</h2>
<ul>
<li>Sauvegardes de la base de données : 14 jours.</li>
<li>Comptes, billets, colis, locations et paiements : aucune durée n’est encore fixée.${toValidate("durée de conservation, en particulier pour la comptabilité")}</li>
</ul>
<h2>Vos droits</h2>
<p>Vous pouvez corriger votre prénom, votre nom, votre téléphone et votre e-mail dans le profil de l’application. Pour supprimer votre compte, consultez la page <a href="/suppression-compte">Suppression de compte</a>.</p>`);
}

export function accountDeletionPage(contact: PrivacyContact): string {
  return page("Suppression de compte", `
<p>Vous pouvez demander la suppression de votre compte client ${companyName(contact)}, créé depuis l’application ou le site.</p>
<h2>Comment la demander</h2>
<p>Contactez l’agence avec le numéro de téléphone ou l’e-mail de votre compte, et indiquez votre identifiant :</p>
${contactBlock(contact)}
<p>${toValidate("délai de traitement de la demande").trim()}</p>
<h2>Ce qui est supprimé</h2>
<p>Votre prénom, votre nom, votre téléphone, votre e-mail et votre mot de passe. Vous ne pouvez plus vous connecter.</p>
<h2>Ce qui est conservé</h2>
<p>Les billets, les colis, les locations et les paiements déjà enregistrés sont conservés pour la comptabilité de l’agence.${toValidate("données exactes conservées et durée de conservation")}</p>
<p>Un compte qui a un billet à venir, un paiement en attente, un colis en cours ou une location en cours ne peut être supprimé qu’après la fin de ce service.${toValidate("règle à confirmer")}</p>
<p>Plus de détails : <a href="/privacy">Politique de confidentialité</a>.</p>`);
}

export async function loadPrivacyContact(apiUrl: string | undefined): Promise<PrivacyContact> {
  const base = (apiUrl ?? "").replace(/\/$/, "");
  if (!base) return EMPTY_CONTACT;
  try {
    const response = await fetch(`${base}/client/privacy-contact/`, { cache: "no-store", signal: AbortSignal.timeout(5000) });
    return response.ok ? readPrivacyContact(await response.json()) : EMPTY_CONTACT;
  } catch {
    return EMPTY_CONTACT;
  }
}

export function htmlResponse(html: string): Response {
  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" } });
}
