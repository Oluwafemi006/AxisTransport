# Axis Transport — application Flutter

Application mobile cliente Axis Transport. Elle couvre la consultation et la réservation des trajets, les billets avec QR code, l'envoi et le suivi des colis, la location de véhicules et le profil client. Les outils du personnel restent dans des applications séparées.

## Prérequis

- Flutter avec un SDK Android fonctionnel ;
- un téléphone Android avec le débogage USB activé, ou un émulateur ;
- l'API Axis Transport démarrée sur le port `8000`.

Depuis la racine du dépôt, démarrer les services et établir le tunnel USB :

```bash
docker compose up -d
./scripts/android-usb.sh
```

## Lancer sur un téléphone Android

Connecter le téléphone, accepter l'empreinte RSA, puis vérifier son identifiant :

```bash
adb devices
```

Lancer ensuite l'application :

```bash
cd mobile-flutter
flutter pub get
flutter run -d <identifiant-adb> --dart-define=AXIS_API_URL=http://127.0.0.1:8000/api/v1
```

Le tunnel `adb reverse` permet à l'application du téléphone de joindre l'API de l'ordinateur à l'adresse `127.0.0.1`. Sur l'émulateur Android, l'adresse par défaut est `http://10.0.2.2:8000/api/v1`.

## Fonctionner sans câble USB

Le téléphone et l'ordinateur doivent être sur le même réseau Wi-Fi. Depuis la racine du dépôt :

```bash
./scripts/flutter-wifi.sh build
```

Le script détecte l'adresse locale de l'ordinateur, démarre Docker avec cette adresse autorisée par Django et compile l'APK avec la bonne URL d'API. Installer ensuite `build/app/outputs/flutter-apk/app-debug.apk` sur le téléphone. Après l'installation, le câble peut être retiré ; l'ordinateur, le Wi-Fi et le backend doivent rester actifs.

Si le réseau attribue une nouvelle adresse à l'ordinateur, reconstruire et réinstaller l'APK. Une adresse peut aussi être imposée explicitement :

```bash
AXIS_LAN_IP=192.168.1.20 ./scripts/flutter-wifi.sh build
```

## Vérifier et construire

```bash
flutter analyze
flutter test
flutter build apk --debug --dart-define=AXIS_API_URL=http://127.0.0.1:8000/api/v1
```

L'APK de développement est généré dans `build/app/outputs/flutter-apk/app-debug.apk`.

## Billets hors connexion

Après synchronisation, seuls les billets émis (`ISSUED`, `CHECKED` ou `COMPLETED`) sont enregistrés dans SQLite sur le téléphone. Le trajet, la date, l'heure, le passager, le siège et le QR restent consultables sans connexion, même après redémarrage de l'application. Les billets sont séparés par compte localement et ne sont plus visibles après déconnexion. Une nouvelle consultation en ligne met à jour le cache et retire les billets annulés ou remboursés.

L'ancien cache JSON n'est pas repris automatiquement : son propriétaire n'était pas identifié. Une connexion au backend est nécessaire une fois après cette mise à jour pour récupérer les billets existants. La recherche de nouvelles places, la réservation et le paiement exigent toujours une connexion Internet.

La création d'une réservation, le paiement et la confirmation exigent toujours une connexion Internet. Une fois les billets émis, ils sont stockés localement et restent consultables hors connexion. Le paiement actuel reste un mécanisme de test tant que le prestataire réel n'est pas branché.

## Recherche de trajets

L'accueil propose maintenant la recherche par point de départ, destination, date et nombre de voyageurs, avec inversion des villes. L'onglet Billets donne également accès à ce formulaire. La page de résultats utilise les filtres publics de l'API (`origin`, `destination`, `date`) et affiche les disponibilités et tarifs renvoyés par Django, sans inventer de départs. Elle permet de changer de jour et de trier les résultats. La recherche et les nouveaux achats nécessitent une connexion Internet.

## Passagers et sièges

Après le choix du voyage, le client renseigne chaque passager avant d'accéder au plan de sièges. Un brouillon Riverpod conserve le trajet, les passagers et l'affectation unique de chaque siège jusqu'au récapitulatif. Le plan privilégie une disposition 2+2 avec une allée et utilise les lignes et colonnes fournies par l'API lorsqu'elles existent.

Le parcours accepte jusqu'à huit voyageurs. Le récapitulatif appelle l'API `/bookings/` pour créer une réservation groupée atomique : tous les sièges sont bloqués ensemble ou rien n'est créé. La réservation fonctionne avec compte client ou sans compte ; dans le cas invité, l'API renvoie un jeton d'accès temporaire utilisé pour payer la réservation.

Les règles de placement viennent du champ `allowed_passenger_types` renvoyé avec les sièges. Un siège sans règle accepte tous les passagers ; un siège limité devient non sélectionnable pour un type incompatible. Aucune règle d'exemple issue de Stitch n'est codée en dur.

## Organisation

- `lib/core/` : configuration, client API authentifié, session et modèles partagés ;
- `lib/features/` : fonctionnalités clientes, dont `trips/` pour la recherche et les résultats, `passengers/`, `seats/` et `bookings/` pour le parcours de réservation, et `offline/data/` pour le stockage SQLite des billets confirmés ;
- `lib/router.dart` : navigation persistante à cinq onglets avec GoRouter ;
- `assets/axis-logo-transparent.png` : logo officiel Axis Transport.

Les horaires, tarifs, sièges, véhicules, colis et locations proviennent de l'API. Si aucun véhicule de location ou trajet n'est affiché, il doit d'abord être publié et configuré dans le back-office web de l'agence.
