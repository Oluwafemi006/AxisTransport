# Axis Transport — architecture mobile comparative

## Décision proposée

Construire un seul backend Django/DRF/PostgreSQL et deux prototypes mobiles limités au même parcours vertical :

```text
React Native + Expo ─┐
                     ├── API REST /api/v1 ── Django/DRF ── PostgreSQL
Flutter              ┘
```

Le parcours comparé sera strictement identique : restauration de session, accueil, recherche départ/destination/date, choix d'un voyage, affichage des sièges, blocage d'un siège, paiement de test, billet QR et consultation hors connexion du billet émis.

Les modules colis et location ne seront pas développés deux fois avant la décision. Après le prototype, un seul framework mobile sera retenu. La recommandation initiale est React Native + Expo, car le projet et l'équipe disposent déjà d'éléments React/TypeScript, mais Flutter doit être mesuré sur la même base avant la décision finale.

## 1. Architecture cible

### Surfaces séparées

- **Application client mobile** : uniquement les fonctions voyageur. Aucun lien, écran ou route vers l'administration, le guichet ou le contrôle.
- **Application/variante contrôleur** : surface séparée et protégée, avec contrôle serveur systématique du rôle et des permissions.
- **Back-office** : Django Admin au départ. Le frontend Next.js existant peut rester temporairement comme prototype d'exploitation, mais ne constitue plus l'application client cible.
- **API** : seule source de vérité pour les tarifs, horaires, disponibilités, sièges, paiements et transitions de statut.

### Backend modulaire

Le backend actuel peut être conservé. Il sera découpé progressivement, sans réécriture brutale, autour des domaines suivants :

- `accounts` : utilisateurs, profils, rôles, permissions, récupération de compte ;
- `network` : agences, lieux, parcours ;
- `fleet` : véhicules, configurations de sièges, maintenance ;
- `operations` : voyages et planning ;
- `booking` : sièges, réservations, billets et contrôle ;
- `payments` : moyens abstraits, transactions et webhooks ;
- `parcels` : colis, historique et remise sécurisée ;
- `rentals` : véhicules de location, calendrier et demandes ;
- `notifications` : appareils, préférences et événements ;
- `audit` : journal des actions sensibles.

Le découpage du monolithe `apps/core` ne doit commencer qu'après stabilisation du contrat `/api/v1` et maintien des tests existants.

## 2. Arborescence proposée

```text
AXIS/
├── backend/
│   ├── apps/
│   │   ├── core/                 # conservé pendant la migration progressive
│   │   ├── accounts/
│   │   ├── booking/
│   │   ├── operations/
│   │   ├── fleet/
│   │   ├── payments/
│   │   ├── parcels/
│   │   ├── rentals/
│   │   └── notifications/
│   ├── config/
│   └── tests/
├── mobile-expo/
│   ├── app/                       # Expo Router
│   │   ├── (auth)/
│   │   ├── (tabs)/
│   │   ├── booking/
│   │   └── ticket/
│   ├── src/
│   │   ├── core/                  # config, API, session, erreurs, stockage
│   │   ├── design-system/
│   │   ├── features/
│   │   │   ├── auth/
│   │   │   ├── home/
│   │   │   ├── trips/
│   │   │   ├── booking/
│   │   │   └── tickets/
│   │   └── shared/
│   └── tests/
├── mobile-flutter/
│   ├── lib/
│   │   ├── core/                  # Dio, config, stockage, erreurs
│   │   ├── shared/
│   │   └── features/
│   │       ├── auth/
│   │       ├── home/
│   │       ├── trips/
│   │       ├── booking/
│   │       └── tickets/
│   └── test/
├── backoffice-web/                # futur nom du frontend Next.js équipe
├── contracts/
│   └── openapi.yaml
├── docs/
└── scripts/
```

Dans chaque feature mobile, séparer présentation, état, accès aux données et modèles de transport, sans multiplier les couches qui n'apportent pas de valeur au MVP.

## 3. Éléments existants réutilisables

### Backend — forte réutilisation

Les modèles actuels couvrent déjà l'essentiel : `User`, `Location`, `Route`, `Vehicle`, `Trip`, `FareRule`, `Seat`, `Ticket`, `TicketStatusHistory`, `TicketControl`, `Parcel`, `ParcelStatusHistory`, `RentalBooking`, `PaymentMethod`, `Transaction`, `FeatureFlag` et `SystemSetting`.

Sont également réutilisables :

- JWT avec rotation et liste noire ;
- transactions et verrouillage du siège côté serveur ;
- expiration des blocages ;
- calcul tarifaire administrable ;
- cycles billet et colis ;
- validation QR et prévention d'une seconde utilisation ;
- séparation client/guichet/contrôleur/admin renforcée ;
- Django Admin et Docker Compose ;
- 14 tests métier et de permissions actuellement au vert.

### Design et flux

- palette, typographie, composants visuels et navigation à cinq onglets ;
- séquence recherche → voyage → siège → ticket ;
- cartes billet, suivi colis et location ;
- états chargement, vide et erreur du frontend web.

Ces éléments sont des références de produit. Le code HTML/React web ne doit pas être copié tel quel dans les applications natives.

### Prototype mobile existant

Le dossier `mobile/` contient des écrans React Native utiles comme référence visuelle, mais pas une base technique fiable : navigation manuelle dans `App.tsx`, données dans `src/mock.ts`, QR factice, aucune API, aucun stockage sécurisé et versions de dépendances incohérentes. Il pèse environ 500 Mo avec ses dépendances locales.

## 4. Éléments à supprimer, migrer ou conserver temporairement

| Élément | Décision | Motif |
|---|---|---|
| `backend/` | Conserver et faire évoluer | Métier, sécurité et tests déjà substantiels |
| `/api/` non versionnée | Migrer vers `/api/v1/` | Contrat stable pour deux clients mobiles |
| Rôles codés en ensembles Python | Compléter par permissions Django | Responsabilités futures configurables côté serveur |
| `frontend/src/components/client-portal.tsx` | Conserver comme harnais temporaire puis retirer | Le client final doit être natif |
| Portails Next admin/guichet/contrôleur | Conserver temporairement, renommer `backoffice-web` plus tard | Surface équipe déjà séparée et utile au test |
| `mobile/src/mock.ts` | Supprimer après validation visuelle | Valeurs commerciales et opérationnelles fictives |
| Ancien `mobile/` React Native CLI | Archiver puis remplacer par Expo Router | Structure et dépendances incompatibles avec la cible |
| Dossiers `android/` et `ios/` générés | Ne pas reprendre dans le prototype Expo managed | Réduire le coût natif tant qu'aucun module ne l'exige |
| Données DÉMO PostgreSQL | Garder uniquement en développement | Testables, signalées comme non validées, jamais production |

Aucune suppression ne doit être exécutée avant sauvegarde et validation explicite.

## 5. Contrat API principal

### Authentification

- `POST /api/v1/auth/register/`
- `POST /api/v1/auth/token/`
- `POST /api/v1/auth/token/refresh/`
- `POST /api/v1/auth/password/request/`
- `POST /api/v1/auth/password/confirm/`
- `GET|PATCH /api/v1/auth/me/`

### Billetterie

- `GET /api/v1/locations/`
- `GET /api/v1/trips/?origin=&destination=&date=&passengers=`
- `GET /api/v1/trips/{id}/`
- `GET /api/v1/trips/{id}/seats/`
- `POST /api/v1/bookings/holds/`
- `DELETE /api/v1/bookings/holds/{id}/`
- `POST /api/v1/tickets/{id}/payments/`
- `GET /api/v1/tickets/`
- `GET /api/v1/tickets/{id}/`
- `POST /api/v1/control/validate/` — contrôleur uniquement

### Colis, location et notifications

- `POST|GET /api/v1/parcels/`
- `GET /api/v1/parcels/{tracking}/events/`
- `GET /api/v1/rental-vehicles/?start=&end=`
- `POST|GET /api/v1/rentals/`
- `POST /api/v1/devices/` pour enregistrer un jeton de notification
- `POST /api/v1/payment-webhooks/{provider}/` avec signature vérifiée

Un schéma OpenAPI versionné doit devenir le contrat commun. Les types TypeScript et Dart seront générés ou validés à partir de ce schéma afin d'éviter la divergence entre clients.

## 6. Authentification et autorisations

- access token court conservé en mémoire ;
- refresh token dans `expo-secure-store` côté Expo et `flutter_secure_storage` côté Flutter ;
- restauration de session au lancement ;
- une seule tentative de refresh lors d'un `401`, avec verrou pour éviter plusieurs refresh simultanés ;
- rotation et révocation serveur déjà disponibles ;
- biométrie éventuelle uniquement pour déverrouiller le stockage local, jamais comme preuve serveur autonome ;
- permissions Django par action (`ticket.add`, `ticket.control`, `parcel.transition`, etc.) en complément du rôle général ;
- aucune confiance dans un masquage d'écran : l'API doit renvoyer `403` pour toute action non autorisée ;
- application client limitée au rôle `CLIENT` et surface contrôleur distribuée séparément.

## 7. Stratégie réseau faible et hors connexion

- mettre en cache lieux, parcours et derniers trajets avec date d'expiration ;
- toujours revalider disponibilité, tarif et siège avant le blocage ;
- ne jamais confirmer une réservation ou un paiement uniquement hors connexion ;
- conserver localement le dernier billet émis et son QR pour présentation sans réseau ;
- compresser les réponses et limiter les images ;
- afficher clairement `hors ligne`, `données anciennes` et `réessayer` ;
- rendre les mutations idempotentes avec une clé générée par le client ;
- pour le contrôle : télécharger avant départ un manifeste signé et limité au voyage, enregistrer les contrôles hors ligne dans une file locale, puis synchroniser avec détection des conflits. Ce mode doit faire l'objet d'une conception de sécurité dédiée avant activation.

## 8. Plan d'implémentation avec points d'arrêt

### Phase 0 — décision d'architecture

- valider le présent document ;
- figer le périmètre exact du vertical slice ;
- archiver l'ancien dossier `mobile/` ;
- définir les critères et appareils de test.

**Point d'arrêt : aucune migration massive avant validation.**

### Phase 1 — contrat backend

- introduire `/api/v1` tout en gardant temporairement `/api` ;
- générer OpenAPI ;
- ajouter recherche structurée, endpoint de blocage explicite et profil modifiable ;
- ajouter permissions Django configurables et tests de contrat ;
- documenter les données confirmées et les paramètres à valider.

### Phase 2 — socles mobiles

- créer `mobile-expo` et `mobile-flutter` propres ;
- configurer environnements, thèmes, navigation, API, stockage sécurisé et erreurs ;
- mettre en place tests, lint/analyse et builds Android de développement.

### Phase 3 — vertical slice comparable

- authentification et restauration ;
- accueil dynamique ;
- recherche ;
- sélection voyage/siège ;
- blocage concurrent sûr ;
- paiement de test confirmé par serveur ;
- billet et vrai QR ;
- cache du billet ;
- écran minimal de scan dans la variante contrôleur.

### Phase 4 — mesure et choix

Comparer sur le même téléphone :

- temps de développement et taux de réutilisation ;
- stabilité du build et facilité de débogage ;
- temps de démarrage, fluidité du plan de sièges et consommation mémoire ;
- taille de l'application ;
- qualité réseau faible/hors ligne ;
- caméra/QR, stockage sécurisé et notifications ;
- maintenabilité et disponibilité des compétences.

À l'issue, choisir Expo ou Flutter. Ne pas maintenir deux applications complètes.

### Phases 5 à 8 — framework retenu uniquement

- contrôle QR robuste ;
- colis ;
- location ;
- notifications ;
- administration renforcée ;
- sécurité, accessibilité, tests réels, sauvegardes et observabilité.

## Benchmark STM à intégrer sans copier

STM met en avant la recherche départ/arrivée/date/passagers dès l'accueil, l'achat avec ou sans compte, la reprogrammation, le suivi colis, les notifications, le support et plusieurs moyens de paiement. Axis doit prioriser :

1. recherche et prix disponibles avant création de compte ;
2. paiement invité ou création de compte différée, sous réserve de validation métier ;
3. report de billet encadré par une politique administrable ;
4. envoi du billet par application, SMS ou WhatsApp ;
5. notifications de départ et d'arrivée colis ;
6. aide, contact, agences et politique de remboursement visibles ;
7. Mobile Money via une abstraction et des webhooks, sans prestataire imposé ;
8. suivi colis par référence et secret de retrait, sans exposer les données personnelles.

La différenciation Axis doit rester locale et pragmatique : interface très légère, choix de siège explicite, billet accessible hors ligne, communication WhatsApp/SMS, statut opérationnel transparent et continuité possible entre le bus et la location à Parakou si cette règle est validée.

## Test physique Android

Pour l'application web actuelle, `scripts/android-usb.sh` transmet les ports `3000` et `8000` par USB. Pour le futur prototype Expo, il faudra transmettre `8081` et `8000`. Flutter utilisera `flutter run` sur l'appareil et le tunnel API `8000`.

Le poste dispose d'ADB, Node.js 22, Flutter et Dart. Le téléphone doit encore être autorisé via la fenêtre RSA du débogage USB. Java n'est pas actuellement disponible dans le `PATH` ; ce point devra être résolu avant les builds Android natifs locaux si l'outillage Flutter/Android Studio ne fournit pas son propre JDK.

