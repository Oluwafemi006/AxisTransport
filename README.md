# Axis Transport — MVP web et mobile

Monorepo du MVP Axis Transport : application cliente responsive, deux applications mobiles de comparaison et espaces équipe séparés pour l’administration, le guichet et le contrôle/PWA. Le backend Django/DRF est la seule source de vérité métier ; les clients ne contiennent ni prix, ni horaire, ni capacité commerciale en dur.

## Architecture

```text
AXIS/
├── backend/
│   ├── apps/core/             # modèles, services métier, API, RBAC et tests
│   ├── config/                # configuration Django
│   ├── manage.py
│   └── requirements.txt
├── frontend/
│   ├── src/app/               # routes client, admin et contrôleur
│   ├── src/components/        # portails fonctionnels
│   ├── src/lib/               # client API et types TypeScript
│   └── public/                # manifeste et service worker PWA
├── mobile-expo/               # client React Native avec Expo Router
├── mobile-flutter/            # client Flutter/Riverpod/GoRouter
├── compose.yaml               # PostgreSQL + API + frontend
└── .env.example
```

### Modèle de données

- `User` porte l’un des rôles `CLIENT`, `COUNTER`, `CONTROLLER`, `ADMIN`.
- `Location` et `Route` décrivent les parcours ; aucun sens de circulation n’est déduit automatiquement.
- `Vehicle` représente aussi bien un bus qu’un véhicule de location. Sa capacité et son `seat_configuration` JSON sont administrables.
- `Trip` est un enregistrement de planning modifiable et persistant. Une annulation ne recalcule pas les trajets suivants.
- `Seat`, `Ticket`, `TicketStatusHistory` et `TicketControl` gèrent le verrouillage temporaire, le paiement, le QR unique et l’audit des contrôles.
- `Parcel` et `ParcelStatusHistory` imposent les neuf étapes confirmées du cycle colis.
- `RentalBooking` gère les disponibilités de location indépendamment du planning du bus.
- `FareRule`, `PaymentMethod`, `FeatureFlag` et `SystemSetting` rendent les valeurs et options commerciales administrables.
- `Transaction` rattache chaque encaissement à exactement un billet, un colis ou une location.

## Démarrage recommandé avec Docker

Prérequis : Docker avec Compose.

```bash
cp .env.example .env
# Remplacer au minimum DJANGO_SECRET_KEY et AXIS_ADMIN_PASSWORD dans .env.
docker compose up --build
```

Accès locaux :

- application cliente : <http://localhost:3000>
- back-office administrateur : <http://localhost:3000/admin>
- guichet : <http://localhost:3000/guichet>
- contrôleur/PWA : <http://localhost:3000/controleur>
- API versionnée : <http://localhost:8000/api/v1/>
- administration Django de secours : <http://localhost:8000/django-admin/>

Le bootstrap crée seulement les informations confirmées : Cotonou, Parakou/Okédama, les deux sens de la ligne, un bus Yutong sans capacité et toutes les fonctions « à valider » désactivées. Il ne crée aucune activité, aucun prix et aucun horaire fictif.

## Configuration obligatoire avant l’ouverture des ventes

Dans `/admin`, effectuer dans cet ordre :

1. ouvrir **Flotte**, compléter l’immatriculation, la capacité et le plan de sièges du Yutong ;
2. ouvrir **Tarifs & règles**, créer au moins un tarif standard par parcours ;
3. définir le délai de blocage temporaire d’un siège ;
4. ajouter au moins un moyen de paiement réellement accepté ;
5. ouvrir **Trajets & planning** et créer les départs confirmés ;
6. ajouter les comptes guichetier et contrôleur dans **Équipe & rôles**.

Les options tarification temporelle, fidélité, Mobile Money, entreprises/ONG, continuité Bus → Voiture et wallet restent désactivées tant que l’administrateur ne les active pas explicitement.

## Développement sans Docker

Backend (Python 3.12 et PostgreSQL) :

```bash
python -m venv .venv
. .venv/bin/activate
pip install -r backend/requirements.txt
cp .env.example .env
python backend/manage.py migrate
python backend/manage.py bootstrap_axis
python backend/manage.py runserver
```

Frontend (Node.js 20+) :

```bash
cd frontend
npm install
npm run dev
```

Pour un test local ponctuel sans PostgreSQL, préfixer les commandes Django avec `USE_SQLITE=true`. PostgreSQL reste la base cible et celle utilisée par Compose.

## Tester sur un téléphone Android par câble USB

Le frontend et l’API peuvent être transmis au téléphone avec ADB, sans les exposer sur Internet :

1. activer **Options pour les développeurs**, puis **Débogage USB** sur le téléphone ;
2. connecter le câble et accepter l’empreinte RSA affichée sur le téléphone ;
3. démarrer l’application avec `docker compose up -d` ;
4. exécuter `./scripts/android-usb.sh` ;
5. ouvrir <http://localhost:3000> dans Chrome sur le téléphone.

Le script crée les tunnels USB pour les ports `3000` (interface web), `8000` (API) et `8081` (Expo/Metro). Ils restent locaux à l’ordinateur et au téléphone connecté. Pour les retirer : `adb reverse --remove-all`.

### Application Expo / React Native

Prérequis : Node.js 20.19.4 ou plus récent et Expo Go sur le téléphone.

```bash
docker compose up -d
./scripts/android-usb.sh
cd mobile-expo
npm install
npm start -- --localhost
```

Ouvrir ensuite `exp://127.0.0.1:8081` dans Expo Go. La variable `EXPO_PUBLIC_API_URL` est documentée dans `mobile-expo/.env.example` et doit pointer vers `http://127.0.0.1:8000/api/v1` pour le tunnel USB.

### Application Flutter

```bash
docker compose up -d
./scripts/android-usb.sh
cd mobile-flutter
flutter pub get
flutter run -d <identifiant-adb> --dart-define=AXIS_API_URL=http://127.0.0.1:8000/api/v1
```

Pour produire un APK de développement :

```bash
flutter build apk --debug --dart-define=AXIS_API_URL=http://127.0.0.1:8000/api/v1
```

L’APK est généré dans `mobile-flutter/build/app/outputs/flutter-apk/app-debug.apk`. La compilation Android utilise `compileSdk 37`, requis par le stockage sécurisé.

### Utiliser Flutter sans laisser le câble branché

Le téléphone et l’ordinateur doivent être connectés au même réseau Wi-Fi. Le script suivant détecte l’adresse locale de l’ordinateur, démarre le backend avec cette adresse autorisée et génère un APK qui l’utilise :

```bash
./scripts/flutter-wifi.sh build
```

Installer l’APK généré une fois sur le téléphone, puis le câble peut être retiré. L’ordinateur doit rester allumé, connecté au même Wi-Fi et les conteneurs Docker doivent rester démarrés. Si l’adresse Wi-Fi de l’ordinateur change, reconstruire puis réinstaller l’APK avec la même commande.

Pour lancer directement l’application sur un téléphone encore relié pendant l’installation :

```bash
./scripts/flutter-wifi.sh run <identifiant-adb>
```

## API principale

- `POST /api/v1/auth/token/`, `POST /api/v1/auth/token/refresh/`, `GET /api/v1/auth/me/`
- `GET /api/v1/trips/`, `GET /api/v1/seats/?trip=<id>`
- `POST /api/v1/tickets/`, `POST /api/v1/tickets/<id>/pay/`
- `POST /api/v1/tickets/validate-qr/` (contrôleur/admin)
- `GET|POST /api/v1/parcels/`, `POST /api/v1/parcels/<id>/transition/`
- `GET|POST /api/v1/rentals/`
- CRUD admin : `locations`, `routes`, `vehicles`, `fare-rules`, `feature-flags`, `settings`, `payment-methods`, `users`, `trips`
- `GET /api/dashboard/?start=AAAA-MM-JJ&end=AAAA-MM-JJ`

## Automatisation de l’expiration des sièges

Les lectures de trajets/sièges libèrent les blocages arrivés à expiration. En production, exécuter aussi la commande suivante chaque minute via Railway Cron, Celery Beat ou le planificateur de la plateforme :

```bash
python backend/manage.py expire_ticket_holds
```

## Tests

```bash
USE_SQLITE=true python backend/manage.py test apps.core.tests
cd frontend && npm run typecheck && npm run build
cd mobile-expo && ./node_modules/.bin/tsc --noEmit
cd mobile-flutter && flutter analyze && flutter test
```

Les tests backend couvrent le cycle complet du billet, le paiement et l’émission, le contrôle QR et l’anti-réutilisation, l’expiration du siège, le cycle colis strict et les restrictions de rôles sur les tarifs et la vente.

## Points volontairement non figés

Les réponses métier encore ouvertes dans le cahier des charges ne sont pas transformées en règles implicites : heure exacte, capacité/plan du Yutong, prix, jours de repos, bagages, annulation/report, tarif colis, preuve exacte de retrait, caution/location et moyens de paiement. Les champs et mécanismes sont présents, mais attendent une configuration ou une validation Axis.
