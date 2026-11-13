// Tests des règles de src/lib/portal-rules.ts, sans dépendance de plus :
// le fichier est compilé ici avec le TypeScript du projet, puis importé.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";
import ts from "typescript";

const here = path.dirname(fileURLToPath(import.meta.url));
const source = readFileSync(path.join(here, "../src/lib/portal-rules.ts"), "utf8");
const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2020 } });
const compiled = path.join(mkdtempSync(path.join(tmpdir(), "axis-portal-rules-")), "portal-rules.mjs");
writeFileSync(compiled, outputText);
const { placeChoices, segmentDepartureLabel, segmentSearchDate, searchError, holdMinutesConfigured, counterTripLabel, actionErrorText, nextPagePath, isSegmentFareMissing, SEGMENT_FARE_MISSING_MESSAGE, writeKey, shareInFlight } = await import(pathToFileURL(compiled).href);

const places = [{ id: 1, name: "Cotonou" }, { id: 2, name: "Parakou" }];

test("aucune ville n'est retirée tant que l'autre liste est vide", () => {
  assert.deepEqual(placeChoices(places, "").map((place) => place.name), ["Cotonou", "Parakou"]);
});

test("la destination exclut le départ choisi, et inversement", () => {
  assert.deepEqual(placeChoices(places, "1").map((place) => place.name), ["Parakou"]);
  assert.deepEqual(placeChoices(places, "2").map((place) => place.name), ["Cotonou"]);
});

test("recherche refusée sans les deux villes, ou avec la même ville", () => {
  assert.equal(searchError("", ""), "Choisissez une ville de départ et une destination.");
  assert.equal(searchError("1", ""), "Choisissez une ville de départ et une destination.");
  assert.equal(searchError("", "2"), "Choisissez une ville de départ et une destination.");
  assert.equal(searchError("1", "1"), "La destination doit être différente de la ville de départ.");
  assert.equal(searchError("1", "2"), null);
});

test("durée de blocage : absente, vide, nulle ou invalide = non configurée", () => {
  assert.equal(holdMinutesConfigured([]), false);
  for (const value of [null, "", 0, -5, "abc", 1.5]) {
    assert.equal(holdMinutesConfigured([{ key: "ticket_hold_minutes", value }]), false, String(value));
  }
  assert.equal(holdMinutesConfigured([{ key: "ticket_hold_minutes", value: 15 }]), true);
  assert.equal(holdMinutesConfigured([{ key: "ticket_hold_minutes", value: "10" }]), true);
});

test("le départ au guichet affiche parcours, date et prix, ou son absence", () => {
  assert.equal(counterTripLabel("Parakou → Cotonou", "18 oct. 2026, 07:00", "7 500 FCFA"), "Parakou → Cotonou · 18 oct. 2026, 07:00 · 7 500 FCFA");
  assert.equal(counterTripLabel("Parakou → Cotonou", "18 oct. 2026, 07:00", null), "Parakou → Cotonou · 18 oct. 2026, 07:00 · sans prix (non vendable)");
});

test("erreur d'action : toujours en français, sans texte technique, jamais comme un succès", () => {
  const failed = "La règle n’a pas été enregistrée.";
  const network = Object.assign(new TypeError("Failed to fetch"), {});
  assert.equal(actionErrorText(network, failed), `${failed} Le serveur ne répond pas : vérifiez la connexion et réessayez.`);
  assert.equal(actionErrorText({ status: 401, message: "Given token not valid for any token type" }, failed), `${failed} Votre session a expiré : reconnectez-vous, puis recommencez.`);
  assert.equal(actionErrorText({ status: 403, message: "You do not have permission" }, failed), `${failed} Votre compte n’a pas le droit de faire cette action.`);
  assert.equal(actionErrorText({ status: 502, message: "Bad Gateway" }, failed), `${failed} Le serveur a rencontré un problème : réessayez dans quelques minutes.`);
  assert.equal(actionErrorText({ status: 400, message: "Ce champ est obligatoire." }, failed), `${failed} Ce champ est obligatoire.`);
  assert.equal(actionErrorText({ status: 400, message: "Une erreur est survenue." }, failed), `${failed} Vérifiez les valeurs saisies et réessayez.`);
  assert.equal(actionErrorText(null, failed), `${failed} Vérifiez les valeurs saisies et réessayez.`);
  assert.equal(actionErrorText(new SyntaxError("Unexpected token } in JSON"), failed), `${failed} Vérifiez les valeurs saisies et réessayez.`);
  for (const reason of [network, { status: 401 }, { status: 500 }, { status: 400, message: "x" }]) {
    const text = actionErrorText(reason, failed);
    assert.ok(text.startsWith(failed));
    assert.doesNotMatch(text, /Failed to fetch|token|permission|Gateway|JSON|enregistrée\.$/i);
  }
});

test("lien d'appel : chiffres et « + » seulement, rien si vide ou invalide", async () => {
  const { phoneHref } = await import(pathToFileURL(compiled).href);
  assert.equal(phoneHref("+229 01 97 00 00 00"), "tel:+2290197000000");
  assert.equal(phoneHref("01 97 00 00 00"), "tel:0197000000");
  assert.equal(phoneHref("(+229) 97-00.00.00"), "tel:+22997000000");
  assert.equal(phoneHref(""), null);
  assert.equal(phoneHref("   "), null);
  assert.equal(phoneHref(null), null);
  assert.equal(phoneHref("À renseigner"), null);
  assert.equal(phoneHref("229+97"), null);
  assert.equal(phoneHref("+1234567890123456"), null);
});

test("lien WhatsApp : numéro international sans « + » ni espaces, rien sinon", async () => {
  const { whatsappHref } = await import(pathToFileURL(compiled).href);
  assert.equal(whatsappHref("+229 01 97 00 00 00"), "https://wa.me/2290197000000");
  assert.equal(whatsappHref("00229 97-00-00-00"), "https://wa.me/22997000000");
  assert.equal(whatsappHref(""), null);
  assert.equal(whatsappHref(null), null);
  assert.equal(whatsappHref("01 97 00 00 00"), null);
  assert.equal(whatsappHref("+229 abc"), null);
  assert.equal(whatsappHref("https://evil.example/+229"), null);
  assert.equal(whatsappHref("+1234567890123456"), null);
});

test("aujourd'hui = jour du Bénin (UTC+1), pas celui du navigateur ni UTC", async () => {
  const { beninDateKey } = await import(pathToFileURL(compiled).href);
  assert.equal(beninDateKey(new Date("2026-10-17T22:59:59Z")), "2026-10-17"); // 23 h 59 au Bénin
  assert.equal(beninDateKey(new Date("2026-10-17T23:00:00Z")), "2026-10-18"); // minuit au Bénin
  assert.equal(beninDateKey(new Date("2026-10-17T23:30:00Z")), "2026-10-18"); // départ à 00 h 30 : bon jour
  assert.equal(beninDateKey(new Date("2026-12-31T23:00:00Z")), "2027-01-01"); // changement d'année
});

test("date de recherche : vide, tapée à la main, passée ou invalide = message, sinon rien", async () => {
  const { searchDateError } = await import(pathToFileURL(compiled).href);
  const today = "2026-10-18";
  assert.equal(searchDateError("", today), "Choisissez une date de départ.");
  assert.equal(searchDateError("2026-10-17", today), "Choisissez une date à partir d’aujourd’hui.");
  assert.equal(searchDateError("2025-12-31", today), "Choisissez une date à partir d’aujourd’hui.");
  assert.equal(searchDateError("18/10/2026", today), "Date de départ invalide : choisissez-la dans le calendrier.");
  assert.equal(searchDateError("2026-13-45", today), "Date de départ invalide : choisissez-la dans le calendrier.");
  assert.equal(searchDateError("2026-10-18", today), null);
  assert.equal(searchDateError("2026-10-19", today), null);
});

test("guichet : seuls les départs à venir et vendables, du plus proche au plus lointain", async () => {
  const { upcomingSellableTrips } = await import(pathToFileURL(compiled).href);
  const now = new Date("2026-10-19T10:00:00Z");
  const trip = (id, departure_at, status = "SCHEDULED", active = true) => ({ id, departure_at, status, route_detail: { active } });
  const trips = [
    trip(1, "2026-10-21T08:00:00Z"),
    trip(2, "2026-10-19T08:00:00Z"), // déjà parti
    trip(3, "2026-10-20T08:00:00Z"),
    trip(4, "2026-10-22T08:00:00Z", "CANCELLED"),
    trip(5, "2026-10-23T08:00:00Z", "SCHEDULED", false),
    trip(6, "2026-10-19T10:30:00Z", "BOARDING"),
  ];
  assert.deepEqual(upcomingSellableTrips(trips, now).map((item) => item.id), [6, 3, 1]);
});

test("activation mot de passe : obligatoire, 8 caractères min, confirmation identique", async () => {
  const { activationPasswordError } = await import(pathToFileURL(compiled).href);
  assert.equal(activationPasswordError("", ""), "Saisissez un mot de passe.");
  assert.equal(activationPasswordError("court", "court"), "Le mot de passe doit comporter au moins 8 caractères.");
  assert.equal(activationPasswordError("motdepasse123", "motdepasse456"), "Les deux mots de passe ne correspondent pas.");
  assert.equal(activationPasswordError("motdepasse123", "motdepasse123"), null);
});

test("redirection portail personnel : adapté selon le rôle assigné", async () => {
  const { staffPortalLoginUrl } = await import(pathToFileURL(compiled).href);
  assert.equal(staffPortalLoginUrl("COUNTER"), "/guichet");
  assert.equal(staffPortalLoginUrl("CONTROLLER"), "/controleur");
  assert.equal(staffPortalLoginUrl("ADMIN"), "/admin");
  assert.equal(staffPortalLoginUrl(null), "/");
  assert.equal(staffPortalLoginUrl("CLIENT"), "/");
});

test("alignement car Yutong : 2 sièges à gauche, couloir central, 2 sièges à droite", async () => {
  const { groupSeatsYutong } = await import(pathToFileURL(compiled).href);
  const seats = [
    { id: 1, number: "1", status: "AVAILABLE" },
    { id: 2, number: "2", status: "AVAILABLE" },
    { id: 3, number: "3", status: "AVAILABLE" },
    { id: 4, number: "4", status: "AVAILABLE" },
    { id: 5, number: "5", status: "AVAILABLE" },
    { id: 6, number: "6", status: "AVAILABLE" },
    { id: 7, number: "7", status: "AVAILABLE" },
    { id: 8, number: "8", status: "AVAILABLE" },
  ];
  const rows = groupSeatsYutong(seats);
  assert.equal(rows.length, 2);
  assert.deepEqual(rows[0].left.map((s) => s.number), ["1", "2"]);
  assert.deepEqual(rows[0].right.map((s) => s.number), ["3", "4"]);
  assert.deepEqual(rows[1].left.map((s) => s.number), ["5", "6"]);
  assert.deepEqual(rows[1].right.map((s) => s.number), ["7", "8"]);
});

test("alignement car Yutong : tri naturel des numéros sans décalage 10 après 1", async () => {
  const { groupSeatsYutong } = await import(pathToFileURL(compiled).href);
  const seats = [
    { id: 10, number: "10", status: "AVAILABLE" },
    { id: 2, number: "2", status: "AVAILABLE" },
    { id: 1, number: "1", status: "AVAILABLE" },
    { id: 3, number: "3", status: "AVAILABLE" },
    { id: 4, number: "4", status: "AVAILABLE" },
  ];
  const rows = groupSeatsYutong(seats);
  assert.equal(rows[0].left[0].number, "1");
  assert.equal(rows[0].left[1].number, "2");
  assert.equal(rows[0].right[0].number, "3");
  assert.equal(rows[0].right[1].number, "4");
  assert.equal(rows[1].left[0].number, "10");
});



test("une liste paginée suit `next` jusqu'à la fin, plus de 50 résultats compris", () => {
  assert.equal(nextPagePath("/trips/?all=true", "https://api.test/api/v1/trips/?all=true&page=2"), "/trips/?all=true&page=2");
  assert.equal(nextPagePath("/trips/?all=true&page=2", "https://api.test/api/v1/trips/?all=true&page=3"), "/trips/?all=true&page=3");
  assert.equal(nextPagePath("/trips/?all=true&page=3", null), null);
});

test("tarif manquant : message clair pour le client et le guichet, sans texte technique", () => {
  const refused = { status: 400, message: "détail serveur", details: { code: "segment_fare_missing", detail: "détail serveur" } };
  assert.equal(isSegmentFareMissing(refused), true);
  assert.equal(actionErrorText(refused, "Vente impossible."), SEGMENT_FARE_MISSING_MESSAGE);
  assert.equal(isSegmentFareMissing({ status: 400, details: { detail: "Autre refus." } }), false);
  assert.equal(isSegmentFareMissing(null), false);
});

test("libellé du prochain départ d'un tronçon, à l'heure du Bénin, comme dans l'app", () => {
  assert.equal(
    segmentDepartureLabel({ next_departure: "2026-11-05T07:00:00Z", line_origin: "Parakou" }),
    "Prochain départ : jeu. 5 nov., départ de Parakou à 08:00",
  );
  assert.equal(segmentDepartureLabel({ next_departure: null, line_origin: "Parakou" }), "Aucun départ programmé");
});

test("recherche préremplie : jour du Bénin du prochain départ, sinon aujourd'hui", () => {
  assert.equal(segmentSearchDate({ next_departure: "2026-11-05T23:30:00Z" }), "2026-11-06");
  assert.equal(segmentSearchDate({ next_departure: null }, new Date("2026-11-03T10:00:00Z")), "2026-11-03");
});

test("double clic : une écriture identique en cours n'est envoyée qu'une fois", async () => {
  const pending = new Map();
  let sent = 0;
  let release;
  const start = () => { sent += 1; return new Promise((resolve) => { release = resolve; }); };
  const key = writeKey("POST", "/vehicles/", JSON.stringify({ name: "TEST" }));
  const first = shareInFlight(pending, key, start);
  const second = shareInFlight(pending, key, start);
  release({ id: 1 });
  assert.deepEqual(await first, { id: 1 });
  assert.deepEqual(await second, { id: 1 });
  assert.equal(sent, 1);
  // Une fois la réponse reçue, un nouvel ajout repart vers le serveur.
  const third = shareInFlight(pending, key, start);
  release({ id: 2 });
  assert.deepEqual(await third, { id: 2 });
  assert.equal(sent, 2);
});

test("double clic : une erreur libère l'écriture, une écriture différente n'est pas bloquée", async () => {
  const pending = new Map();
  await assert.rejects(shareInFlight(pending, "POST /x a", () => Promise.reject(new Error("TEST"))));
  assert.equal(pending.size, 0);
  let sent = 0;
  const start = () => { sent += 1; return Promise.resolve(null); };
  await Promise.all([shareInFlight(pending, writeKey("POST", "/x", "a"), start), shareInFlight(pending, writeKey("POST", "/x", "b"), start)]);
  assert.equal(sent, 2);
});

test("lectures et envois de fichier ne sont jamais regroupés", () => {
  assert.equal(writeKey(undefined, "/trips/", undefined), null);
  assert.equal(writeKey("GET", "/trips/", undefined), null);
  assert.equal(writeKey("POST", "/vehicles/1/photo/", { fichier: "TEST" }), null);
  assert.equal(writeKey("patch", "/users/1/", "{}"), "PATCH /users/1/ {}");
});

test("admin : ajout d'un moyen de paiement confirmé, avertissement sur « Ajouter un tarif »", () => {
  const admin = readFileSync(path.join(here, "../src/components/admin-portal.tsx"), "utf8");
  const addMethod = admin.slice(admin.indexOf("async function addMethod()"), admin.indexOf("const openPolicies"));
  assert.match(addMethod, /window\.confirm\(`Ajouter « \$\{label\} » \? Il sera proposé tout de suite/);
  assert.match(addMethod, /if \(!label\)/);
  assert.match(admin, /Ce tarif ne change pas le prix de vente d’un billet/);
});

test("bilan global : période valide, fin après début, pas de date future", async () => {
  const { reportPeriodError } = await import(pathToFileURL(compiled).href);
  assert.equal(reportPeriodError("2026-11-01", "2026-11-10", "2026-11-13"), null);
  assert.equal(reportPeriodError("2026-11-01", "2026-11-13", "2026-11-13"), null);
  assert.equal(reportPeriodError("2026-11-10", "2026-11-01", "2026-11-13"), "La date de fin doit être postérieure ou égale à la date de début.");
  assert.equal(reportPeriodError("2026-11-01", "2026-11-14", "2026-11-13"), "La date de fin ne peut pas dépasser aujourd'hui.");
  assert.equal(reportPeriodError("", "2026-11-13", "2026-11-13"), "Indiquez une date de début et une date de fin.");
});
