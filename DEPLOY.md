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
| `DJANGO_CSRF_TRUSTED_ORIGINS` | Adresses HTTPS depuis lesquelles les formulaires de `/django-admin/` sont acceptés, séparées par des virgules. | `https://api.exemple.test` |
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
| `AXIS_PUBLIC_TICKET_RATE` | Limite de lecture de la page publique d'un billet par adresse IP. La page appelle l'API depuis le navigateur du visiteur, pas depuis le serveur du site. | `60/min` |
| `AXIS_PAYMENT_RECONCILE_ENABLED` | Interrupteur du rattrapage des paiements jamais confirmés (commande `reconcile_payments`). | `true` |
| `AXIS_PAYMENT_RECONCILE_WINDOW_MINUTES` | Durée pendant laquelle une transaction créée est réinterrogée chez FedaPay. | `1440` (24 h, durée de validité observée du lien de paiement) |
| `AXIS_PAYMENT_RECONCILE_BATCH` | Nombre maximal de transactions interrogées par passage. | `20` |
| `AXIS_PAYMENT_RECONCILE_INTERVAL_SECONDS` | Intervalle entre deux passages (profil de recette). | `60` |
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
| Réglages HTTPS (`SECURE_PROXY_SSL_HEADER`, redirection HTTPS, HSTS, cookies `Secure`) | Aucun n'est défini. |
| Fichiers envoyés (`/media/`) | Servis uniquement en debug. Les pièces d'identité de location demandent un stockage privé. |
| Cache partagé entre machines | Le cache est un dossier local (`AXIS_CACHE_DIR`), commun aux processus d'une même machine. Si l'API tourne sur plusieurs machines, chaque machine compte la limite du suivi de colis séparément : il faudra alors un cache commun (Redis). |
| Limite de requêtes sur la connexion, l'inscription et la réservation | Absente : seul le suivi de colis est limité. |
| Expiration des sièges | La commande `expire_ticket_holds` doit être planifiée chaque minute. |
| Rattrapage des paiements | La commande `reconcile_payments` doit être planifiée (chaque minute). Sans elle, un paiement dont le webhook est perdu n'est confirmé que si le client revient. |
| Configuration de lancement | `compose.yaml` est une configuration de développement (`DEBUG=true`, `ALLOWED_HOSTS` contenant `*`, mot de passe PostgreSQL `axis`). Ne pas l'utiliser telle quelle. |

### Commandes au déploiement

```bash
python manage.py migrate
python manage.py collectstatic --noinput
python manage.py bootstrap_axis
gunicorn config.wsgi:application --bind 0.0.0.0:8000 --workers 3
```

## 2 bis. Recette : backend local joignable en HTTPS par un tunnel

But unique : vérifier le webhook FedaPay (payer, fermer l'onglet, le billet doit sortir). Essai court.
**Aucun tunnel ne se lance sans l'accord explicite du responsable du projet, donné au moment voulu.**

Le profil de recette est `compose.recette.yaml`, distinct de `compose.yaml` :

| | Développement (`compose.yaml`) | Recette (`compose.recette.yaml`) |
|---|---|---|
| Debug | activé | coupé |
| Base de données | `axis_transport`, avec comptes de démonstration | `axis_recette`, séparée, un seul compte administrateur |
| Clé secrète, mots de passe | valeurs locales connues | obligatoires, lus dans `.env.recette` |
| Sites autorisés (CORS), hôtes, CSRF | localhost | lus dans `.env.recette` |
| Fichiers statiques de `/django-admin/` | servis | servis (`collectstatic` au démarrage) |
| Expiration des sièges | à la main | service `holds`, chaque minute |
| Rattrapage des paiements | à la main (`reconcile_payments`) | service `payments`, chaque minute |
| Ports | API 8000, site 3000 | API 8100, site 3100 |

Seul le backend (port 8100) est exposé par le tunnel. Le site de recette reste local (port 3100) et appelle l'API locale.

### Préparation (sans tunnel)

```bash
cp recette.env.example .env.recette        # puis remplir ; ce fichier n'est jamais commité
docker compose -p axis-recette --env-file .env.recette -f compose.recette.yaml up -d --build
```

La base de recette démarre presque vide : lieux Cotonou et Parakou, véhicule « Yutong » sans capacité, moyen de paiement FedaPay. Avant un achat il faut saisir, avec le compte administrateur, sur `http://localhost:3100/admin` : la capacité du véhicule, un départ, un tarif, et la durée de blocage d'un siège.

### Au moment du tunnel

`TUNNEL` désigne l'adresse HTTPS fournie par l'outil de tunnel (exemple : `https://xxxx.exemple.test`).

1. Dans `.env.recette` : ajouter le nom d'hôte du tunnel à `DJANGO_ALLOWED_HOSTS` (sans `https://`), mettre `TUNNEL` dans `DJANGO_CSRF_TRUSTED_ORIGINS`.
2. Chez FedaPay (compte sandbox) : déclarer le webhook `TUNNEL/api/v1/client/webhooks/fedapay/`. Recopier son secret dans le fichier local `.env.recette`, sur la ligne `FEDAPAY_WEBHOOK_SECRET=` (et la clé secrète sandbox sur `FEDAPAY_SECRET_KEY=`). Ce fichier est ignoré par Git ; ces valeurs ne se collent ni dans une discussion ni dans un commit.
3. Relancer la commande `up -d` ci-dessus, ouvrir le tunnel vers le port 8100, vérifier `GET TUNNEL/api/v1/health/`.
4. Essai : acheter sur `http://localhost:3100`, payer, fermer l'onglet sans cliquer sur « vérifier ». Le billet doit passer à « émis » par le seul webhook.
5. Fermer le tunnel, retirer le webhook chez FedaPay, puis `docker compose -p axis-recette --env-file .env.recette -f compose.recette.yaml down`.

Pour appeler ce backend depuis le site Vercel (hors du but de cet essai) : ajouter l'adresse Vercel à `DJANGO_CORS_ALLOWED_ORIGINS`, mettre `NEXT_PUBLIC_API_URL` = `TUNNEL/api/v1` sur Vercel et redéployer.

### Risques

- **Adresse changeante** : avec un tunnel gratuit, l'adresse change à chaque lancement ; il faut refaire les étapes 1 à 3.
- **PC allumé** : PC éteint, en veille ou sans réseau = webhook perdu. FedaPay peut le renvoyer, sans garantie de délai.
- **API publique pendant l'essai** : toute personne connaissant l'adresse peut appeler l'API et tenter de se connecter à l'administration. D'où le mot de passe fort et la durée courte.
- **Pas de limite de requêtes** sur la connexion, l'inscription et la réservation.

### Paiements : webhook, rattrapage, incidents

- **Webhook** : FedaPay désactive un webhook après 10 essais sans réponse 2xx. Le serveur répond donc 200 à un message authentique qu'il refuse pour une raison définitive, et enregistre un **incident de paiement** ; il répond 400 à une signature absente ou invalide, et 503 à une erreur passagère (FedaPay ou base injoignable) pour que FedaPay réessaie.
- **Rattrapage** : chaque transaction créée est enregistrée. `reconcile_payments` réinterroge FedaPay pour celles qui ne sont pas confirmées et émet le billet par le même chemin que le webhook (jamais deux billets pour un paiement ; un paiement après expiration reste « à rembourser »).
- **À surveiller par l'administrateur**, dans `/django-admin/` : « Payment incidents » (argent possiblement encaissé sans billet, à traiter à la main) et « Payment receipts » filtrés sur `refund_due`.
- **Limite du rattrapage** : une transaction n'est réinterrogée que pendant `AXIS_PAYMENT_RECONCILE_WINDOW_MINUTES` (24 h). Un paiement fait plus tard n'est vu que si FedaPay envoie le webhook ; s'il ne peut pas être transformé en billet, il apparaît comme incident de paiement.
- **Réservation annulée par le client** : ses transactions FedaPay sont marquées « abandonnée – réservation annulée » mais restent réinterrogées pendant les 24 h, pour voir un paiement fait malgré l'annulation (il part alors « à rembourser », sans billet). Coût : environ 60 appels par transaction sur 24 h, toujours plafonnés par le lot de `AXIS_PAYMENT_RECONCILE_BATCH` (20) par minute.
- **Remboursements : procédure non définie.** Le serveur signale ce qui est à rembourser (reçus `refund_due`, incidents de paiement) mais ne rembourse rien. Qui rembourse, par quel moyen et sous quel délai : question ouverte, à trancher par la direction d'Axis.
- **Incidents dans le portail** : onglet « Incidents de paiement » de `/admin` (administrateur seulement), en lecture seule avec une case « traité ».
- La documentation FedaPay ne publie aucune limite de débit pour son API. Le rattrapage se borne lui-même : au plus `AXIS_PAYMENT_RECONCILE_BATCH` appels par passage, relectures espacées (chaque passage pendant 30 min, puis toutes les 10 min jusqu'à 2 h, puis chaque heure), arrêt du passage dès une réponse 429 ou 5xx.

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
