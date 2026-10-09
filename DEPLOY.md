# Déploiement — Axis Transport

> **À savoir avant de déployer le site sur Vercel.** Le site n'affichera ni villes ni départs tant que
> l'API n'est pas déployée **en HTTPS**, avec l'adresse Vercel du site dans `DJANGO_CORS_ALLOWED_ORIGINS`.
> D'ici là, `NEXT_PUBLIC_API_URL` peut porter une valeur d'exemple pour que le build passe ;
> il faudra la corriger puis redéployer quand l'API sera en ligne.

Ce document ne contient aucun secret. Les valeurs données sont des exemples : `exemple.test` n'est pas un vrai domaine.

## 1. Frontend web sur Vercel

| Réglage Vercel | Valeur |
|---|---|
| Root Directory | `frontend` |
| Framework | Next.js (détecté automatiquement) |
| Build Command | `npm run build` (par défaut) |
| Node.js | 20 ou plus récent |

### Variables d'environnement du frontend

| Nom | Rôle | Exemple |
|---|---|---|
| `NEXT_PUBLIC_API_URL` | Adresse de l'API, **terminée par `/api/v1`**, sans barre finale. Obligatoire : le build échoue si elle manque. | `https://api.exemple.test/api/v1` |

C'est la seule variable. Elle est lue au moment du build : après l'avoir changée, il faut redéployer.

`VERCEL` est définie automatiquement par Vercel : il n'y a rien à saisir. Quand elle est présente,
`next.config.ts` n'active pas la sortie `standalone`, réservée à l'image Docker.

Points d'attention :

- Vercel sert le site en HTTPS : l'API doit aussi être en HTTPS, sinon le navigateur bloque les appels.
- L'adresse Vercel du site doit être ajoutée à `DJANGO_CORS_ALLOWED_ORIGINS` côté backend.
- En local, `next dev` lit `frontend/.env.development` (API sur `localhost:8000`). Ce fichier n'est jamais utilisé par `next build`.

## 2. Backend (à déployer plus tard)

### Variables qui existent déjà

| Nom | Rôle | Valeur en production |
|---|---|---|
| `DJANGO_DEBUG` | Mode debug. | `false` (ou absente) |
| `DJANGO_SECRET_KEY` | Clé secrète Django. | Longue chaîne aléatoire, propre à la production |
| `DJANGO_ALLOWED_HOSTS` | Noms d'hôte acceptés, séparés par des virgules. | `api.exemple.test` (jamais `*`) |
| `DJANGO_CORS_ALLOWED_ORIGINS` | Sites autorisés à appeler l'API, séparés par des virgules. | `https://axis.exemple.test` |
| `DATABASE_URL` | Base PostgreSQL. | `postgresql://UTILISATEUR:MOT_DE_PASSE@HOTE:5432/BASE` |
| `PUBLIC_WEB_URL` | Adresse publique du site, utilisée dans les liens de billets partagés. Vide = aucun lien généré. | `https://axis.exemple.test` une fois le domaine acheté |
| `FEDAPAY_CALLBACK_URL` | Page où FedaPay renvoie après un paiement. Par défaut : `PUBLIC_WEB_URL` + `/paiement/retour`. | `https://axis.exemple.test/paiement/retour` |
| `FEDAPAY_SECRET_KEY` | Clé secrète FedaPay. Sans elle, tout paiement est refusé. | Clé **live** |
| `FEDAPAY_WEBHOOK_SECRET` | Secret du webhook FedaPay (propre à chaque endpoint). Sans lui, le webhook répond 503. | Secret du webhook **live** |
| `FEDAPAY_ENVIRONMENT` | `sandbox` ou `live`. | `live` |
| `FEDAPAY_WEBHOOK_TOLERANCE_SECONDS` | Écart accepté sur l'horodatage du webhook. | `300` |
| `ACTIVE_PAYMENT_PROVIDER` | Prestataire activé au premier démarrage. | `fedapay` |
| `AXIS_ADMIN_USERNAME`, `AXIS_ADMIN_PASSWORD`, `AXIS_ADMIN_EMAIL` | Compte administrateur créé au premier `bootstrap_axis`. | Mot de passe fort, unique |
| `AXIS_PARCEL_TRACKING_RATE` | Limite du suivi de colis par adresse IP. | `20/min` |
| `AXIS_CACHE_DIR` | Dossier du cache (compteurs de limite de requêtes). | Dossier accessible en écriture ; par défaut le dossier temporaire du système |
| `AXIS_NUM_PROXIES` | Nombre de proxys devant l'API, pour lire la vraie adresse IP du client. | `1` derrière un seul proxy |
| `AXIS_PAYMENT_SIMULATION` | Paiement simulé. Sans effet quand `DJANGO_DEBUG` est faux. | absente |
| `USE_SQLITE` | Base SQLite pour les tests. | absente |

URL du webhook à déclarer chez FedaPay : `https://api.exemple.test/api/v1/client/webhooks/fedapay/`.

### Ce qui manque encore pour la production

Ces points ne sont pas implémentés. Ils sont à traiter avant d'ouvrir le backend au public.

| Manque | Conséquence aujourd'hui |
|---|---|
| Refus de démarrer avec la clé secrète par défaut | Si `DJANGO_SECRET_KEY` est oubliée, Django démarre avec `unsafe-development-key`. |
| `CSRF_TRUSTED_ORIGINS` | Non configurable. L'administration Django (`/django-admin/`) refusera les formulaires en HTTPS derrière un proxy. |
| Réglages HTTPS (`SECURE_PROXY_SSL_HEADER`, redirection HTTPS, HSTS, cookies `Secure`) | Aucun n'est défini. |
| Fichiers statiques | Rien ne les sert sous gunicorn (pas de WhiteNoise ni de `collectstatic` au démarrage) : l'administration Django s'affiche sans style. |
| Fichiers envoyés (`/media/`) | Servis uniquement en debug. Les pièces d'identité de location demandent un stockage privé. |
| Cache partagé entre machines | Le cache est un dossier local (`AXIS_CACHE_DIR`), commun aux processus d'une même machine. Si l'API tourne sur plusieurs machines, chaque machine compte la limite du suivi de colis séparément : il faudra alors un cache commun (Redis). |
| Limite de requêtes sur la connexion, l'inscription et la réservation | Absente : seul le suivi de colis est limité. |
| Expiration des sièges | La commande `expire_ticket_holds` doit être planifiée chaque minute. |
| Configuration de lancement | `compose.yaml` est une configuration de développement (`DEBUG=true`, `ALLOWED_HOSTS` contenant `*`, mot de passe PostgreSQL `axis`). Ne pas l'utiliser telle quelle. |

### Commandes au déploiement

```bash
python manage.py migrate
python manage.py bootstrap_axis
gunicorn config.wsgi:application --bind 0.0.0.0:8000 --workers 3
```

## 2 bis. Backend local joignable en HTTPS par un tunnel (procédure préparée, jamais exécutée)

Sert uniquement à un essai court : le site Vercel appelle le backend resté sur le PC. À ne lancer qu'avec l'accord explicite du responsable du projet.
`TUNNEL` désigne ci-dessous l'adresse HTTPS fournie par l'outil de tunnel (exemple : `https://xxxx.exemple.test`).

### Avant d'ouvrir le tunnel

Trois points de l'état actuel rendent l'essai dangereux ou impossible ; ils ne sont pas corrigés :

| Point | Conséquence |
|---|---|
| `compose.yaml` lance le backend avec `DJANGO_DEBUG=true` | Les pages d'erreur détaillées et le paiement simulé (si activé) deviennent accessibles depuis Internet. |
| Comptes de démonstration (`demo_admin`, `demo_guichet`…) au mot de passe connu | N'importe qui connaissant l'adresse peut entrer dans l'administration. Les supprimer ou changer leur mot de passe avant. |
| `DJANGO_CORS_ALLOWED_ORIGINS` est écrit en dur dans `compose.yaml` et l'en-tête `X-Booking-Token` n'est pas autorisé | Le site Vercel ne peut pas appeler l'API ; l'achat sans compte échoue au paiement. |

`CSRF_TRUSTED_ORIGINS` n'existe pas dans `settings.py` : l'API (jetons JWT) fonctionne sans, mais `/django-admin/` refusera ses formulaires à travers le tunnel.

### Variables à poser

Côté backend (fichier `.env` local, jamais commité) :

| Nom | Valeur |
|---|---|
| `DJANGO_DEBUG` | `false` |
| `DJANGO_SECRET_KEY` | Chaîne aléatoire longue |
| `DJANGO_ALLOWED_HOSTS` | Nom d'hôte du tunnel, sans `https://` (pas de `*`) |
| `DJANGO_CORS_ALLOWED_ORIGINS` | `https://axis-transport.vercel.app` |
| `CSRF_TRUSTED_ORIGINS` | `TUNNEL` — à ajouter d'abord dans `settings.py` |
| `PUBLIC_WEB_URL` | `https://axis-transport.vercel.app` |
| `FEDAPAY_CALLBACK_URL` | `https://axis-transport.vercel.app/paiement/retour` |
| `FEDAPAY_SECRET_KEY`, `FEDAPAY_WEBHOOK_SECRET`, `FEDAPAY_ENVIRONMENT` | Clés `sandbox`, `sandbox` |

Côté Vercel : `NEXT_PUBLIC_API_URL` = `TUNNEL/api/v1`, puis redéployer (la variable est lue au build).

Chez FedaPay (compte sandbox) : déclarer le webhook `TUNNEL/api/v1/client/webhooks/fedapay/` et recopier son secret dans `FEDAPAY_WEBHOOK_SECRET`.

### Ordre des opérations

1. Poser les variables backend, redémarrer le backend, vérifier `GET http://localhost:8000/api/v1/health/`.
2. Ouvrir le tunnel vers le port 8000 ; vérifier `GET TUNNEL/api/v1/health/`.
3. Déclarer le webhook chez FedaPay, poser `NEXT_PUBLIC_API_URL` sur Vercel, redéployer.
4. Faire l'essai, puis fermer le tunnel et retirer le webhook.

### Risques

- **Adresse changeante** : avec un tunnel gratuit, l'adresse change à chaque lancement. Il faut alors refaire `DJANGO_ALLOWED_HOSTS`, le webhook FedaPay, `NEXT_PUBLIC_API_URL` et un redéploiement Vercel.
- **PC allumé** : PC éteint, en veille ou sans réseau = site sans données et paiements non confirmés. Un paiement fait pendant une coupure n'est rattrapé que si le client revient vérifier ou si FedaPay renvoie le webhook.
- **Base de données locale exposée à travers l'API** : toutes les données du PC (comptes, billets de démonstration) deviennent visibles par l'API publique.
- **Expiration des sièges** : la commande `expire_ticket_holds` n'est pas planifiée ; à lancer à la main pendant l'essai.

## 3. À ne jamais faire en production

- **Ne jamais lancer `seed_demo`.** Elle crée des comptes au mot de passe connu, un tarif et des voyages fictifs. Elle refuse de tourner quand `DJANGO_DEBUG` est faux : ne pas activer le debug pour la contourner.
- Ne jamais mettre `DJANGO_DEBUG=true`.
- Ne jamais activer `AXIS_PAYMENT_SIMULATION`.
- Ne jamais utiliser les clés FedaPay `sandbox` avec `FEDAPAY_ENVIRONMENT=live`, ni l'inverse.
- Ne jamais committer un fichier `.env`.

## 4. Vérifications après déploiement

1. `GET https://api.exemple.test/api/v1/health/` répond `{"status": "ok"}`.
2. La page d'accueil du site affiche les villes (sinon : vérifier `NEXT_PUBLIC_API_URL` et CORS).
3. Un paiement de test aboutit et le billet s'affiche.
4. Le webhook FedaPay répond 200 à un événement signé, 400 sans signature.
