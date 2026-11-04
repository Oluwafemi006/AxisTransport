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
| `AXIS_LOGIN_RATE_ACCOUNT_ADDRESS` | Connexions **échouées** par identifiant et adresse IP ensemble. Au-delà : blocage temporaire de cet identifiant depuis cette adresse seulement, réponse « Trop de tentatives, réessayez dans X minutes ». | `10/hour` (proposition technique) |
| `AXIS_LOGIN_RATE_ACCOUNT` | Plafond de connexions **échouées** par identifiant, toutes adresses confondues (attaque répartie). Au-delà : blocage temporaire de l'identifiant depuis toutes les adresses. | `50/hour` (proposition technique) |
| `AXIS_LOGIN_RATE_ADDRESS` | Tentatives de connexion par adresse IP, tous identifiants confondus. Élevé à dessein : de nombreux abonnés mobiles peuvent partager une même adresse. | `30/min` (proposition) |
| `AXIS_REGISTER_RATE_ADDRESS` | Créations de compte client par adresse IP. | `10/hour` (proposition) |
| `AXIS_PASSWORD_RESET_RATE_EMAIL` | Mot de passe oublié : demandes de code par adresse e-mail. | `3/hour` (proposition) |
| `AXIS_PASSWORD_RESET_RATE_ADDRESS` | Mot de passe oublié : demandes de code par adresse IP. | `20/hour` (proposition) |
| `AXIS_PASSWORD_CHANGE_RATE` | Changement de mot de passe depuis le profil : essais par compte connecté. | `10/hour` (proposition) |
| `AXIS_PASSWORD_RESET_CONFIRM_RATE` | Mot de passe oublié : saisies du code par adresse IP. | `30/hour` (proposition) |

**Limite de connexion : fonctionnement et seuils proposés** (propositions techniques, pas des règles de la direction ; modifiables par les variables ci-dessus) :

- Seules les connexions échouées comptent. Une connexion réussie efface les échecs de son adresse, pas ceux des autres adresses.
- `10/hour` par identifiant et adresse : une personne qui se trompe de mot de passe s'arrête bien avant 10 essais en une heure ; une seule adresse ne peut pas tester plus de 10 mots de passe par heure sur un compte. Des échecs provoqués depuis une autre adresse ne bloquent pas le titulaire (par exemple un contrôleur).
- `50/hour` par identifiant, toutes adresses : 5 fois le seuil précédent, donc jamais atteint par un utilisateur seul ; limite une attaque répartie sur de nombreuses adresses à 50 essais par heure et par compte. Contrepartie : une attaque utilisant au moins 5 adresses peut encore bloquer un compte pendant au plus une heure.
- `30/min` par adresse, tous identifiants : inchangé ; élevé parce que beaucoup d'abonnés mobiles partagent la même adresse.
- Débloquer un compte (toutes adresses), sur le serveur : `docker compose --env-file .env.vps -f compose.vps.yaml exec backend python manage.py unblock_login <identifiant>` (majuscules et espaces ignorés). Il n'existe pas encore de bouton dans le portail `/admin`.
| `AXIS_PAYMENT_RECONCILE_ENABLED` | Interrupteur du rattrapage des paiements jamais confirmés (commande `reconcile_payments`). | `true` |
| `AXIS_PAYMENT_RECONCILE_WINDOW_MINUTES` | Durée pendant laquelle une transaction créée est réinterrogée chez FedaPay. | `1440` (24 h, durée de validité observée du lien de paiement) |
| `AXIS_PAYMENT_RECONCILE_BATCH` | Nombre maximal de transactions interrogées par passage. | `20` |
| `AXIS_PAYMENT_RECONCILE_INTERVAL_SECONDS` | Intervalle entre deux passages du rattrapage : service `payments` de `compose.vps.yaml` (et de `compose.yaml` en local), qui lance `reconcile_payments` en boucle. C'est le filet de sécurité si le webhook FedaPay n'arrive pas : un paiement accepté est confirmé au plus tard au passage suivant. | `60` (secondes) |
| `AXIS_PAYMENT_REFRESH_RATE` | Bouton « Vérifier mon paiement » (site et app) : demandes par adresse IP, chacune interroge FedaPay. | `20/min` (proposition) |
| `AXIS_CACHE_DIR` | Dossier du cache (compteurs de limite de requêtes). | Dossier accessible en écriture ; par défaut le dossier temporaire du système |
| `AXIS_NUM_PROXIES` | Nombre de proxys devant l'API, pour lire la vraie adresse IP du client. | `1` derrière un seul proxy |
| `AXIS_PAYMENT_SIMULATION` | Paiement simulé. Sans effet quand `DJANGO_DEBUG` est faux. | absente |
| `EMAIL_HOST` | Hôte SMTP pour l'envoi d'e-mails (invitations du personnel, codes « mot de passe oublié »). | `smtp.gmail.com` |
| `EMAIL_PORT` | Port SMTP. | `587` |
| `EMAIL_USE_TLS` | Activation du chiffrement TLS. | `true` |
| `EMAIL_HOST_USER` | Compte d'expédition Gmail pour les invitations. | `contact@exemple.test` |
| `EMAIL_HOST_PASSWORD` | Mot de passe d'application Gmail (16 caractères générés par Google). | Mot de passe d'application |
| `DEFAULT_FROM_EMAIL` | Adresse de l'expéditeur des e-mails. Par défaut `EMAIL_HOST_USER`. | `contact@exemple.test` |
| `FRONTEND_URL` | Adresse publique du site web utilisée pour les liens d'activation. Par défaut `PUBLIC_WEB_URL`. | `https://axis.exemple.test` |
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
| Limite de requêtes sur la réservation | Absente. La connexion, l'inscription, le suivi de colis et la page publique du billet sont limités. |
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
- **Pas de limite de requêtes** sur la réservation (la connexion et l'inscription sont limitées, voir section 2).

### Paiements : webhook, rattrapage, incidents

- **Webhook** : FedaPay désactive un webhook après 10 essais sans réponse 2xx. Le serveur répond donc 200 à un message authentique qu'il refuse pour une raison définitive, et enregistre un **incident de paiement** ; il répond 400 à une signature absente ou invalide, et 503 à une erreur passagère (FedaPay ou base injoignable) pour que FedaPay réessaie.
- **Rattrapage** : chaque transaction créée est enregistrée. `reconcile_payments` réinterroge FedaPay pour celles qui ne sont pas confirmées et émet le billet par le même chemin que le webhook (jamais deux billets pour un paiement ; un paiement après expiration reste « à rembourser »).
- **À surveiller par l'administrateur**, dans `/django-admin/` : « Payment incidents » (argent possiblement encaissé sans billet, à traiter à la main) et « Payment receipts » filtrés sur `refund_due`.
- **Limite du rattrapage** : une transaction n'est réinterrogée que pendant `AXIS_PAYMENT_RECONCILE_WINDOW_MINUTES` (24 h). Un paiement fait plus tard n'est vu que si FedaPay envoie le webhook ; s'il ne peut pas être transformé en billet, il apparaît comme incident de paiement.
- **Réservation annulée par le client** : ses transactions FedaPay sont marquées « abandonnée – réservation annulée » mais restent réinterrogées pendant les 24 h, pour voir un paiement fait malgré l'annulation (il part alors « à rembourser », sans billet). Coût : environ 60 appels par transaction sur 24 h, toujours plafonnés par le lot de `AXIS_PAYMENT_RECONCILE_BATCH` (20) par minute.
- **Remboursements : procédure non définie.** Le serveur signale ce qui est à rembourser (reçus `refund_due`, incidents de paiement) mais ne rembourse rien. Qui rembourse, par quel moyen et sous quel délai : question ouverte, à trancher par la direction d'Axis.
- **Incidents dans le portail** : onglet « Incidents de paiement » de `/admin` (administrateur seulement), en lecture seule avec une case « traité ».
- La documentation FedaPay ne publie aucune limite de débit pour son API. Le rattrapage se borne lui-même : au plus `AXIS_PAYMENT_RECONCILE_BATCH` appels par passage, relectures espacées (chaque passage pendant 30 min, puis toutes les 10 min jusqu'à 2 h, puis chaque heure), arrêt du passage dès une réponse 429 ou 5xx.

## 2 ter. Axe et tarifs par tronçon (validés par le boss, transmis par Eddy)

Ligne, de Parakou vers Cotonou : **Parakou, Savè, Glazoué, Dassa, Bohicon, Cotonou** ; le retour suit l'ordre inverse. L'ordre de Savè, Glazoué et Dassa vient de Google et doit encore être confirmé par le boss. Un prix par paire d'arrêts, le même dans les deux sens :

| Tronçon | Prix (FCFA) |
|---|---|
| Parakou ↔ Cotonou | 7 500 |
| Parakou ↔ Bohicon | 6 000 |
| Parakou ↔ Glazoué | 5 000 |
| Parakou ↔ Dassa | 5 000 |
| Parakou ↔ Savè | 3 500 |
| Savè ↔ Cotonou | 6 000 |
| Savè ↔ Bohicon | 3 000 |
| Bohicon ↔ Cotonou | 3 000 |

- **Aucun autre tronçon n'a de tarif** (Savè–Glazoué, Savè–Dassa, Glazoué–Dassa, départs depuis Glazoué ou Dassa…) : il n'est ni affiché ni vendable, et figure dans la liste « tronçons sans tarif » de l'admin.
- Points d'embarquement : Parakou « Parc ALBARIKA », Bohicon « Bohicon », Cotonou « Calavi » et « Agontikon » (choix obligatoire, à la montée comme à la descente). Savè, Glazoué et Dassa : aucun point connu.
- **Kétou et Porto-Novo** sont retirées : villes désactivées, arrêts retirés des parcours, rangs repoussés hors de la ligne (au-delà de 100). Leurs tarifs, billets, réservations et colis sont conservés. Le serveur refuse toute **nouvelle** vente vers ou depuis une ville inactive ; un billet déjà émis ne change pas.
- Source unique dans le code : `backend/apps/core/axis.py` (arrêts, tarifs, points).
- Modification d'un prix : portail `/admin`, onglet « Tarifs par tronçon », avec historique (qui, quand, ancien et nouveau prix).
- Une réservation ou un billet garde le prix enregistré au moment de la vente.
- **Montée en ligne au terminus seulement** (validé par le boss) : à l'aller depuis Parakou, au retour depuis Cotonou, seules montées dont l'heure affichée est exacte. Les montées à Savè, Glazoué, Dassa et Bohicon se vendent à bord, par le contrôleur (et au guichet) ; l'accueil (site et app) ne les propose plus et une réservation en ligne est refusée (« La montée à … se fait à bord, auprès du contrôleur. »). La descente à un arrêt intermédiaire reste achetable en ligne.
- Sièges : toujours bloqués pour tout le voyage (un siège vendu sur un tronçon n'est pas revendu au-delà de l'arrêt de descente).

### Démarrage : ce qui est réécrit ou non

- `bootstrap_axis` (à chaque démarrage) appelle `load_segment_fares`, `init_weekly_schedule` et `load_boarding_points`. Aucune ne réécrit ce qui existe :
  - `load_segment_fares` n'ajoute que les tarifs manquants. Sur une base encore à l'**ancien axe**, elle s'arrête avec un avertissement (« lancez apply_axis ») sans empêcher le démarrage du backend.
  - `init_weekly_schedule` crée les parcours et leurs arrêts seulement s'ils n'existent pas, et seulement les jours de planning absents : **un horaire ou un jour saisi dans l'admin n'est jamais réécrit**. Aucune heure aux escales (`offset_minutes` vides).
  - `load_boarding_points` crée les points de l'axe uniquement pour une ville qui n'a **aucun** point (actif ou non) : un point renommé, désactivé ou supprimé dans l'admin n'est jamais recréé.
- Le passage d'une base existante au nouvel axe se fait **uniquement** par les deux commandes ci-dessous, jamais au démarrage.

### Mise en production du nouvel axe (une seule fois, sur le VPS, dans `~/axis`)

```bash
# 0. Sauvegarde de la base avant toute modification
./deploy/backup.sh

# 1. Code à jour, image reconstruite, migrations et démarrage
git pull
docker compose --env-file .env.vps -f compose.vps.yaml up -d --build
docker compose --env-file .env.vps -f compose.vps.yaml exec backend python manage.py showmigrations core

# 2. Axe : villes, ordre de la ligne et des deux parcours, Kétou et Porto-Novo désactivées
docker compose --env-file .env.vps -f compose.vps.yaml exec backend python manage.py apply_axis

# 3. Tarifs : met à jour Parakou–Savè (4 500 → 3 500) et Savè–Cotonou (6 500 → 6 000), crée les 5 manquants,
#    affiche ancien et nouveau prix, ne touche à aucun autre tarif
docker compose --env-file .env.vps -f compose.vps.yaml exec backend python manage.py apply_axis_fares

# 4. Points d'embarquement (Bohicon, Calavi, Agontikon ; Parakou déjà équipé reste inchangé)
docker compose --env-file .env.vps -f compose.vps.yaml exec backend python manage.py load_boarding_points
```

- `apply_axis` et `apply_axis_fares` peuvent être relancées sans effet (« inchangé »).
- Au démarrage qui précède l'étape 2, le journal du backend affiche « Grille des tronçons non chargée… lancez apply_axis » : c'est attendu.
- Vérification : onglet « Tarifs par tronçon » (8 tarifs de l'axe), onglet « Points d'embarquement », recherche Parakou → Bohicon sur le site.
- Ne jamais lancer `docker compose up -d` sans `--env-file .env.vps -f compose.vps.yaml` sur le VPS : la commande lirait `compose.yaml`, prévu pour le poste de développement.

### Montant payé par le client (décision de la direction, lot 2)

- Le montant affiché au client est celui qu'il paie. Axis envoie à FedaPay exactement le prix du billet ; les frais FedaPay sont supportés par l'agence.
- Le taux de frais client de chaque moyen de paiement vaut 0 par défaut (migration `0012_client_fee_zero`, puis `bootstrap_axis`). Il reste modifiable par l'administrateur (`/django-admin/`, moyens de paiement) ; s'il est relevé, le bouton « Payer » affiche le montant réellement débité.
- Le web, les apps et le billet n'affichent plus de ligne « Frais de paiement » ni « Total ». L'API garde ses champs : `fee_amount` = 0 et `total` = prix.
- Une transaction FedaPay créée avant cette migration avec l'ancien total (prix + frais) ne correspond plus au montant dû : son paiement est refusé et inscrit dans les incidents de paiement, à rembourser à la main.

## 2 quinquies. Billet de transport, agence et taxes (lot 4)

- **Prix affiché TTC** : rien ne s'ajoute au prix de la grille. Taxe initiale : TVA 18 %, incluse, seule taxe. Ce taux est une valeur transmise, **non vérifiée pour le transport de voyageurs** : modifiable dans `/admin`, onglet « Agence et taxes ». Un billet déjà vendu garde son taux et ses montants (HT et TVA figés à la vente).
- **Informations de l'agence** (raison sociale, IFU, RCCM, capital, adresse, téléphones, e-mail, comptes bancaires) : vides au départ, **saisies uniquement dans `/admin`**, jamais dans le code ni les fichiers de configuration. Chaque modification est journalisée (compte, date, ancien et nouveau contenu). Les comptes bancaires ne sont jamais imprimés ni exposés publiquement.
- Le bas du billet affiche ces informations, ou « À renseigner » si elles sont vides. La ligne HT / TVA / TTC n'apparaît que si l'IFU de l'agence est renseigné.
- **Compte du boss** : aucun rôle « boss » n'existe. Le boss reçoit un compte **administrateur nominatif** (à son nom, créé par `create_admin` ou dans « Équipe & rôles ») ; le journal de « Agence et taxes » et celui des tarifs indiquent qui a modifié quoi.
- **Mode de paiement imprimé** : pour un paiement FedaPay, le billet imprime le moyen réellement renvoyé par FedaPay (champ `mode` de la transaction). Seule la valeur `momo_test` (sandbox) a été observée, imprimée « Mobile Money (test) » ; toute autre valeur s'imprime « Paiement en ligne » jusqu'à ce qu'elle soit constatée sur une transaction réelle et ajoutée (`FEDAPAY_MODE_LABELS` dans `backend/apps/core/serializers.py`). Au guichet, c'est le nom du moyen de paiement configuré qui s'imprime : le renommer « Espèces » dans `/django-admin/` → « Payment methods » → le moyen du guichet → champ « Label » (le portail `/admin` n'a pas d'écran pour renommer un moyen de paiement).
- **Frais FedaPay constatés en sandbox** : sur la transaction de test du 17/10/2026 (1 000 FCFA), FedaPay a débité **1 042** au client et versé 1 000 à l'agence. Le compte sandbox fait donc payer les frais au client, contrairement à la décision. À régler dans le tableau de bord FedaPay (qui supporte les frais) puis à revérifier sur une transaction, en sandbox et en live.
- **Facturation normalisée e-MECeF : obligation à confirmer avec le boss et son comptable avant les premières ventes réelles ; hors périmètre actuel.** Le billet ne porte ni numéro de facture, ni NIM, ni code MeCeF/DGI, ni QR de la DGI.

## 2 quater. Une seule application mobile (clients et personnel)

L'application « Axis Transport » (`mobile-flutter`, identifiant Android `com.axistransport.axis_transport_flutter`) sert désormais aux clients et au personnel. Après connexion, l'interface dépend uniquement du rôle renvoyé par le serveur : client → billets, colis, location ; guichet, contrôleur ou administrateur → Accueil, Scanner, Vendre, Profil. L'inscription ne crée que des comptes clients.

**APK déjà installés**

- Les clients mettent à jour « Axis Transport » à la place de l'ancienne version.
- L'ancienne application « Axis Staff » (`com.axistransport.staff`) reste installée et continue de fonctionner : l'API n'a pas changé. Le personnel installe « Axis Transport », s'y connecte, puis **désinstalle « Axis Staff » à la main**.
- Le dossier `mobile-staff` est conservé tant que l'application unique n'a pas été essayée sur téléphone.

**Invitation du personnel**

- Un seul lien de téléchargement pour tout le monde.
- Le serveur n'envoie aujourd'hui **aucun e-mail**. L'administrateur crée le compte (portail `/admin`, « Équipe & rôles ») et transmet lui-même l'identifiant et le mot de passe.

**À corriger avant publication sur le Play Store**

| Point | État |
|---|---|
| HTTP non chiffré autorisé (`android:usesCleartextTraffic="true"` dans `mobile-flutter/android/app/src/main/AndroidManifest.xml`) | À passer à `false` une fois l'API en HTTPS |
| Signature avec la clé de débogage (`signingConfig = signingConfigs.getByName("debug")` dans `mobile-flutter/android/app/build.gradle.kts`) | Une vraie clé de signature est nécessaire |
| Permission caméra déclarée pour tous les utilisateurs | Demandée seulement à l'ouverture du scanner (personnel) ; visible sur la fiche Play Store |

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

## 5. VPS : tout le projet sur un serveur (procédure écrite, jamais exécutée)

Tout tourne sur le VPS : API, PostgreSQL, site Next.js, et un proxy Caddy devant. Vercel (offre Hobby, usage non commercial) ne sert plus qu'aux démonstrations.

**Statut de cette section** : rédigée sans accès au serveur. Aucune commande n'a été lancée sur le VPS. Seule la syntaxe de `compose.vps.yaml` et des deux fichiers Caddy a été validée sur un PC. Tout le reste est à vérifier sur place ; la liste est au point 5.13.

Notations : `<IP>` = adresse du serveur, `<DOMAINE>` = nom de domaine (pas encore choisi ; il n'est écrit nulle part dans le code, il vient de la variable `AXIS_DOMAIN`), `<UTILISATEUR>` = compte non-root créé au point 5.2.

Fichiers utilisés :

| Fichier | Rôle |
|---|---|
| `compose.vps.yaml` | Les services : `db`, `backend`, `holds` (expiration des sièges), `payments` (rattrapage), `frontend`, `caddy` |
| `deploy/Caddyfile.http` | Variante A : HTTP sur l'adresse IP |
| `deploy/Caddyfile.https` | Variante B : domaine et HTTPS |
| `vps.env.example` | Modèle du fichier `.env.vps`, à remplir sur le serveur |

### Les deux variantes

| | A — test technique en HTTP sur l'IP | B — domaine et HTTPS |
|---|---|---|
| But | Vérifier que le projet démarre et fonctionne sur le serveur | Version utilisable par de vrais clients |
| Données | Fictives uniquement | Réelles |
| FedaPay | `sandbox` | `sandbox`, puis `live` à l'ouverture |
| Adresse du site | `http://<IP>/` | `https://<DOMAINE>/` |
| Adresse de l'API | `http://<IP>/api/v1` (même hôte, routée par chemin) | `https://api.<DOMAINE>/api/v1` |
| Administration Django | `http://<IP>/django-admin/` | `https://api.<DOMAINE>/django-admin/` |
| Certificats | Aucun : rien n'est chiffré, mots de passe compris | Obtenus et renouvelés par Caddy |
| Ports ouverts | 22, 80 | 22, 80, 443 |
| Fichier Caddy | `Caddyfile.http` | `Caddyfile.https` |

**Réglages Django à assouplir pour la variante A : aucun.** Le code ne contient aujourd'hui ni redirection HTTPS, ni cookies « Secure », ni HSTS, ni lecture de l'en-tête du proxy (`SECURE_SSL_REDIRECT`, `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE`, `SECURE_HSTS_SECONDS`, `SECURE_PROXY_SSL_HEADER` sont absents de `settings.py`). Il n'y a donc rien à désactiver pour un essai en HTTP, et rien de « caché » à remettre : ce qui change entre A et B, ce sont les variables du point 5.9.

**Ce qui manque pour la variante B et demande une modification du code avant l'ouverture réelle** (non faite, à décider) :

| Manque | Effet aujourd'hui |
|---|---|
| Cookies de session et CSRF marqués « Secure », HSTS | La redirection HTTP → HTTPS est faite par Caddy, mais Django ne l'impose pas lui-même |
| `SECURE_PROXY_SSL_HEADER` | Django se croit en HTTP derrière Caddy. L'API (jetons JWT) n'en dépend pas ; `/django-admin/` fonctionne grâce à `DJANGO_CSRF_TRUSTED_ORIGINS` |
| Refus de démarrer sans clé secrète | Couvert sur le VPS : `compose.vps.yaml` refuse de démarrer si `DJANGO_SECRET_KEY` est vide |
| Limite de requêtes sur la réservation | Absente (la connexion et l'inscription sont limitées, voir section 2) |
| Fichiers envoyés (`/media/`) | Enregistrés dans un volume, mais servis par personne hors debug : les pièces d'identité de location ne sont pas consultables |
| HTTP non chiffré autorisé dans les deux apps mobiles | Voir 5.10 |

**HTTPS avant l'achat du domaine (nom de type `sslip.io`) : non vérifié.** En principe `<IP>.sslip.io` désigne l'adresse du serveur et Caddy pourrait demander un certificat pour ce nom. Rien ne garantit ici que l'autorité de certification l'accorde (quotas partagés par tous les utilisateurs de ce service), ni que FedaPay accepte une telle adresse pour le webhook. À essayer sur le serveur avant d'y compter.

### 5.0 Mise en ligne pas à pas — variante B, `axistransportlogistique.com`

Procédure complète, à copier-coller **dans l'ordre**, une commande à la fois. Après chaque commande : le **résultat attendu**. Si le résultat diffère, s'arrêter et ne pas passer à la suite. Domaine : `axistransportlogistique.com` (site), `api.axistransportlogistique.com` (API), `www.` redirigé vers l'adresse sans `www`. Rien de cette procédure n'a encore été exécuté sur le serveur.

**Avant l'étape 1** : serveur sécurisé (5.2), Docker installé (5.3), connexion en `ssh <UTILISATEUR>@<IP>`. Chez le fournisseur du domaine, trois enregistrements DNS de type A vers `<IP>` :

| Type | Nom | Valeur |
|---|---|---|
| A | `axistransportlogistique.com` (souvent noté `@`) | `<IP>` |
| A | `api` | `<IP>` |
| A | `www` | `<IP>` |

**1. DNS**
```bash
dig +short axistransportlogistique.com api.axistransportlogistique.com www.axistransportlogistique.com
```
Attendu : trois lignes, toutes égales à `<IP>`. Sinon : attendre la propagation DNS (jusqu'à plusieurs heures) avant de continuer.

**2. Mémoire de construction** (voir 5.1)
```bash
free -h
```
Attendu : colonne « total » de la ligne « Mem » d'au moins 4 Go, ou une ligne « Swap » d'au moins 2 Go. Sinon : créer le swap de 5.1 avant l'étape 6.

**3. Code** (clé de déploiement en lecture seule, 5.3)
```bash
GIT_SSH_COMMAND="ssh -i ~/.ssh/axis_deploy" git clone git@github.com:Oluwafemi006/AxisTransport.git ~/axis
cd ~/axis && git log -1 --oneline | tee -a ~/versions-deployees.txt
```
Attendu : le clonage se termine sans erreur, puis une ligne `<commit> <message>` : la version déployée, notée dans `~/versions-deployees.txt`.

**4. Fichier des variables**
```bash
cp vps.env.example .env.vps && chmod 600 .env.vps && nano .env.vps
```
Attendu : l'éditeur s'ouvre. Saisir les valeurs sur le serveur (noms ci-dessous ; jamais de valeur dans le dépôt ni dans une discussion), puis Ctrl+O, Entrée, Ctrl+X.

| Variable | Qui la saisit | Contenu attendu |
|---|---|---|
| `AXIS_CADDYFILE` | Eddy | `Caddyfile.https` |
| `AXIS_DOMAIN` | Eddy | `axistransportlogistique.com` (sans `https://` ni `www`) |
| `DJANGO_SECRET_KEY` | **Eddy (secret)** | sortie de `python3 -c "import secrets; print(secrets.token_urlsafe(64))"` lancée sur le serveur |
| `DJANGO_ALLOWED_HOSTS` | Eddy | `api.axistransportlogistique.com` |
| `DJANGO_CORS_ALLOWED_ORIGINS` | Eddy | `https://axistransportlogistique.com` |
| `DJANGO_CSRF_TRUSTED_ORIGINS` | Eddy | `https://api.axistransportlogistique.com` |
| `PUBLIC_WEB_URL` | Eddy | `https://axistransportlogistique.com` |
| `AXIS_NUM_PROXIES` | déjà `1` | un seul proxy (Caddy) devant l'API |
| `POSTGRES_PASSWORD` | **Eddy (secret)** | lettres et chiffres seulement |
| `NEXT_PUBLIC_API_URL` | Eddy | `https://api.axistransportlogistique.com/api/v1` (avec `/api/v1` : le site y ajoute directement `/client/…`) |
| `AXIS_ADMIN_USERNAME`, `AXIS_ADMIN_PASSWORD`, `AXIS_ADMIN_EMAIL` | **laisser vides** | l'admin se crée à l'étape 10 |
| `FEDAPAY_ENVIRONMENT` | Eddy | `sandbox` pour le scénario de test (5 ter), `live` à l'ouverture réelle |
| `FEDAPAY_SECRET_KEY` | **Eddy (secret)** | clé du même environnement |
| `FEDAPAY_WEBHOOK_SECRET` | **Eddy (secret)** | laissé vide pour l'instant, rempli à l'étape 11 |
| `FEDAPAY_CALLBACK_URL` | Eddy | `https://axistransportlogistique.com/paiement/retour` |
| autres (`AXIS_*_RATE`, `AXIS_PAYMENT_RECONCILE_*`, `FEDAPAY_WEBHOOK_TOLERANCE_SECONDS`) | valeurs proposées dans le modèle | à garder sauf décision |

Ne jamais ajouter `AXIS_ENVIRONMENT`, `AXIS_PAYMENT_SIMULATION` ni `DJANGO_DEBUG` dans `.env.vps`.

**5. Vérifier la configuration**
```bash
C="docker compose --env-file .env.vps -f compose.vps.yaml"
$C config --quiet && echo CONFIG-OK
```
Attendu : `CONFIG-OK`. Sinon le message nomme la variable manquante (« … doit être définie dans .env.vps ») : la remplir (étape 4) et recommencer. Dans tout nouveau terminal, relancer d'abord la ligne `C=…`.

**6. Construire**
```bash
$C build
```
Attendu : plusieurs minutes, puis aucune ligne `ERROR` ; la dernière étape du site affiche une ligne `Compiled successfully` ou `✓`. Si le serveur se fige ou affiche `Killed` / `JavaScript heap out of memory` : mémoire insuffisante, voir 5.1.

**7. Démarrer**
```bash
$C up -d && sleep 30 && $C ps --format "table {{.Service}}\t{{.Status}}"
```
Attendu : six lignes `db`, `backend`, `holds`, `payments`, `frontend`, `caddy`, toutes `Up` (`db` : `Up … (healthy)`).

**8. Migrations** (appliquées automatiquement par `backend` au démarrage, dont `0011` à `0014`)
```bash
$C exec -T backend python manage.py showmigrations core | tail -4
```
Attendu : quatre lignes commençant par `[X]`, la dernière `[X] 0014_receipt_provider_mode` (ou une migration plus récente). Aucune ligne `[ ]`.

**9. Grille de prix** (chargée automatiquement par `bootstrap_axis`)
```bash
$C exec -T backend python manage.py load_segment_fares
```
Attendu : `Lieux créés (inactifs) : aucun. Tarifs créés : 0. Tarifs déjà présents, laissés tels quels : 10.` La grille est celle de la section 2 ter ; un prix déjà présent n'est jamais modifié.

**10. Compte ADMIN réel** (interactif : pas de `-T`)
```bash
$C exec backend python manage.py create_admin
```
Attendu : questions « Identifiant », « E-mail », puis deux fois « Mot de passe (saisie masquée) » ; rien ne s'affiche pendant la frappe. Dernière ligne : `Administrateur « … » créé.` Le boss reçoit son propre compte administrateur nominatif, créé de la même façon.

**11. FedaPay** (tableau de bord FedaPay, environnement choisi à l'étape 4)
- Webhook à déclarer : `https://api.axistransportlogistique.com/api/v1/client/webhooks/fedapay/` ; copier le secret affiché dans `FEDAPAY_WEBHOOK_SECRET` (`nano .env.vps`).
- Adresse de retour : `https://axistransportlogistique.com/paiement/retour` (déjà dans `FEDAPAY_CALLBACK_URL`).
- Vérifier qui supporte les frais (décision : l'agence) ; en sandbox le 17/10/2026, ils étaient facturés au client (section 2 quinquies).
```bash
$C up -d backend payments holds
```
Attendu : `Container … Started` (ou `Running`) pour les trois services.

**12. HTTPS**
```bash
curl -s https://api.axistransportlogistique.com/api/v1/health/
curl -sI https://axistransportlogistique.com | head -1
curl -sI http://axistransportlogistique.com | grep -i '^location'
curl -sI https://www.axistransportlogistique.com | grep -i '^location'
```
Attendu, dans l'ordre : `{"status":"ok","service":"axis-transport-api"}` ; `HTTP/2 200` ; `location: https://axistransportlogistique.com/` ; `location: https://axistransportlogistique.com/`. Si `curl` signale une erreur de certificat : attendre une minute (Caddy obtient le certificat au premier appel) et lire `$C logs --tail 50 caddy`.

**13. Sauvegardes**
```bash
deploy/backup.sh && deploy/restore-test.sh
(crontab -l 2>/dev/null; echo '0 3 * * * $HOME/axis/deploy/backup.sh >> $HOME/sauvegardes/journal.log 2>&1') | crontab -
crontab -l
```
Attendu : `Sauvegarde : /home/<UTILISATEUR>/sauvegardes/axis-….dump (…)`, puis `Restauration réussie ; la base d'essai est supprimée.`, puis la ligne cron affichée par `crontab -l`.

**14. Contrôles** : section 5.12, puis le scénario de test (5 ter) avec FedaPay en `sandbox`.

### 5.1 Mesurer si le VPS tient

Mesure faite sur le PC de développement, services au repos (`docker stats`) :

| Service | Mémoire |
|---|---|
| `backend` (gunicorn, 3 processus) | 191 Mo |
| `frontend` | 113 Mo |
| `db` | 36 Mo |
| **Total mesuré** | **340 Mo** |

**Construction du site** (`next build`), mesurée le 17/10/2026 sur le PC de développement (4 processeurs, Node 22) : **pic de 803 Mo** de mémoire au total (tous les processus de la construction), durée 2 min 33 s. Non mesurés : l'installation des dépendances (`npm install`) dans l'image, la construction dans Docker avec Node 20, et la construction en même temps des images de l'API (`$C build` construit plusieurs images en parallèle).

**Estimation pour un VPS de 4 Go** : la construction du site (≈ 0,8 Go mesuré) plus le système et les autres constructions devraient tenir, mais sans grande marge si des services tournent déjà (≈ 340 Mo au repos, plus `holds`, `payments`, `caddy` non mesurés). Par prudence, **ajouter 2 Go de swap avant la première construction** et construire le site seul :

```bash
free -h && nproc && df -h /                          # mémoire, processeurs, disque disponibles
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab     # garde le swap après redémarrage
free -h                                               # attendu : ligne « Swap » d'environ 2,0Gi
C="docker compose --env-file .env.vps -f compose.vps.yaml"
$C build frontend && $C build                         # le site d'abord, seul, puis le reste
docker stats --no-stream                              # après le démarrage (5.0, étape 7)
```

Si la construction échoue quand même (`Killed`, `JavaScript heap out of memory`) : construire les images sur un autre poste puis les transférer (`docker save` / `docker load`) ; cette solution n'est pas préparée.

### 5.2 Sécuriser le serveur AVANT tout déploiement

Ordre à respecter. **Garder la première session root ouverte jusqu'à la fin de cette partie** : c'est le filet de sécurité.

1. **Mises à jour** (session root) :
   ```bash
   apt update && apt upgrade -y
   ```
2. **Utilisateur non-root avec sudo** :
   ```bash
   adduser <UTILISATEUR>
   usermod -aG sudo <UTILISATEUR>
   ```
3. **Clé SSH**, depuis le PC (pas depuis le serveur) :
   ```bash
   ssh-keygen -t ed25519            # si le PC n'a pas encore de clé
   ssh-copy-id <UTILISATEUR>@<IP>
   ```
4. **Vérification dans une DEUXIÈME session**, sans fermer la première :
   ```bash
   ssh <UTILISATEUR>@<IP>           # doit entrer sans demander le mot de passe du compte
   sudo -v                          # doit accepter le mot de passe de <UTILISATEUR>
   ```
   Ne pas continuer tant que ces deux commandes ne passent pas.
5. **Pare-feu**, en autorisant SSH avant de l'activer :
   ```bash
   sudo ufw allow 22/tcp
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   sudo ufw enable
   sudo ufw status
   ```
   Ouvrir une TROISIÈME session `ssh <UTILISATEUR>@<IP>` pour vérifier que SSH passe toujours.
6. **Couper le mot de passe et le compte root en SSH**. Créer `/etc/ssh/sshd_config.d/00-axis.conf` :
   ```
   PasswordAuthentication no
   PermitRootLogin no
   ```
   Puis :
   ```bash
   sudo grep -ri "passwordauthentication\|permitrootlogin" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/
   sudo sshd -t                     # ne doit rien afficher
   sudo systemctl reload ssh
   ```
   La première commande sert à repérer un autre fichier qui remettrait le mot de passe en service (sur les images de certains hébergeurs, un fichier `50-cloud-init.conf` le fait) : le corriger aussi. Le nom du service (`ssh`) et la présence de ce fichier sur l'image Contabo sont **non vérifiés**.
7. **Vérification dans une nouvelle session**, les anciennes toujours ouvertes :
   ```bash
   ssh <UTILISATEUR>@<IP>                                    # doit entrer
   ssh -o PubkeyAuthentication=no <UTILISATEUR>@<IP>         # doit être refusé
   ssh root@<IP>                                             # doit être refusé
   ```
   Si la première échoue : revenir dans une session restée ouverte, supprimer le fichier `00-axis.conf`, relancer `sudo systemctl reload ssh`.
8. **Mises à jour automatiques de sécurité** :
   ```bash
   sudo apt install -y unattended-upgrades
   sudo dpkg-reconfigure -plow unattended-upgrades
   ```
9. Seulement maintenant, fermer la session root d'origine.

Attention : **un port publié par Docker contourne `ufw`**. `compose.vps.yaml` ne publie que les ports 80 et 443 de Caddy ; ne jamais y ajouter de ligne `ports:` pour la base ou l'API.

### 5.3 Installer Docker et récupérer le code

Docker, depuis le dépôt officiel de Docker pour Ubuntu (suivre la page d'installation de la documentation Docker : les commandes exactes n'ont pas été vérifiées ici), puis :

```bash
sudo usermod -aG docker <UTILISATEUR>     # se reconnecter ensuite
docker compose version                    # doit répondre
sudo systemctl enable docker              # Docker démarre avec le serveur
```

Le code, sans aucun secret (le dépôt n'en contient pas ; les fichiers `.env*` sont ignorés par Git). Deux façons :

- **Clé de déploiement en lecture seule** : sur le serveur, `ssh-keygen -t ed25519 -f ~/.ssh/axis_deploy`, puis ajouter la clé *publique* dans les réglages du dépôt GitHub (« Deploy keys », sans droit d'écriture). Ensuite :
  ```bash
  GIT_SSH_COMMAND="ssh -i ~/.ssh/axis_deploy" git clone git@github.com:Oluwafemi006/AxisTransport.git ~/axis
  ```
- **Copie depuis le PC**, sans donner d'accès GitHub au serveur :
  ```bash
  git archive --format=tar.gz -o axis.tar.gz HEAD          # sur le PC, dans le dossier du projet
  scp axis.tar.gz <UTILISATEUR>@<IP>:~                     # puis, sur le serveur :
  mkdir -p ~/axis && tar -xzf ~/axis.tar.gz -C ~/axis
  ```
  `git archive` ne prend que ce qui est commité : ni `.env`, ni secrets.

### 5.4 Fichier `.env.vps` et démarrage

Sur le serveur, dans `~/axis` :

```bash
cp vps.env.example .env.vps
chmod 600 .env.vps
nano .env.vps                              # les secrets sont saisis ici, sur le serveur, et nulle part ailleurs
docker compose --env-file .env.vps -f compose.vps.yaml up -d --build
docker compose --env-file .env.vps -f compose.vps.yaml ps
```

Toutes les variables (S = secret, saisi sur le serveur) :

| Variable | Variante A | Variante B |
|---|---|---|
| `AXIS_CADDYFILE` | `Caddyfile.http` | `Caddyfile.https` |
| `AXIS_DOMAIN` | vide | `<DOMAINE>` (sans `https://`) |
| `DJANGO_SECRET_KEY` (S) | chaîne aléatoire longue | une AUTRE chaîne aléatoire (celle de A a circulé en clair) |
| `DJANGO_DEBUG` | fixée à `false` dans `compose.vps.yaml`, non modifiable par `.env.vps` | idem |
| `DJANGO_ALLOWED_HOSTS` | `<IP>` | `api.<DOMAINE>` |
| `DJANGO_CORS_ALLOWED_ORIGINS` | `http://<IP>` | `https://<DOMAINE>` |
| `DJANGO_CSRF_TRUSTED_ORIGINS` | `http://<IP>` | `https://api.<DOMAINE>` |
| `PUBLIC_WEB_URL` | `http://<IP>` | `https://<DOMAINE>` |
| `AXIS_NUM_PROXIES` | `1` | `1` |
| `POSTGRES_PASSWORD` (S) | lettres et chiffres | un autre mot de passe (voir 5.9) |
| `NEXT_PUBLIC_API_URL` | `http://<IP>/api/v1` | `https://api.<DOMAINE>/api/v1` |
| `AXIS_ADMIN_USERNAME`, `AXIS_ADMIN_EMAIL` | compte réel | compte réel |
| `AXIS_ADMIN_PASSWORD` (S) | mot de passe fort | mot de passe fort, différent |
| `FEDAPAY_ENVIRONMENT` | `sandbox` | `sandbox`, puis `live` |
| `FEDAPAY_SECRET_KEY` (S) | clé sandbox | clé du même environnement |
| `FEDAPAY_WEBHOOK_SECRET` (S) | secret du webhook déclaré pour `http://<IP>/api/v1/client/webhooks/fedapay/` | secret du webhook `https://api.<DOMAINE>/api/v1/client/webhooks/fedapay/` |
| `FEDAPAY_CALLBACK_URL` | `http://<IP>/paiement/retour` | `https://<DOMAINE>/paiement/retour` |
| `FEDAPAY_WEBHOOK_TOLERANCE_SECONDS` | `300` | `300` |
| `AXIS_PARCEL_TRACKING_RATE`, `AXIS_PUBLIC_TICKET_RATE` | `20/min`, `60/min` | idem |
| `AXIS_PAYMENT_RECONCILE_ENABLED`, `_WINDOW_MINUTES`, `_BATCH`, `_INTERVAL_SECONDS` | `true`, `1440`, `20`, `60` | idem |

Variables du code volontairement absentes du serveur : `AXIS_PAYMENT_SIMULATION` (sans effet hors debug), `USE_SQLITE` (tests), `AXIS_FRONTEND_ORIGINS` (propre à `compose.yaml` de développement : sur le VPS, les origines se mettent directement dans `DJANGO_CORS_ALLOWED_ORIGINS`), `AXIS_CACHE_DIR` et `ACTIVE_PAYMENT_PROVIDER` (fixées dans `compose.vps.yaml`).

Que FedaPay accepte de déclarer un webhook en HTTP sur une adresse IP (variante A) est **non vérifié**. Si ce n'est pas le cas, le paiement reste testable en A : le client vérifie lui-même au retour, et le service `payments` rattrape en une minute.

### 5.5 Redémarrage automatique

Chaque service de `compose.vps.yaml` porte `restart: unless-stopped`, et Docker démarre avec le serveur (`systemctl enable docker`, point 5.3). À vérifier une fois, sur le serveur :

```bash
sudo reboot
# puis, après reconnexion :
docker compose --env-file .env.vps -f compose.vps.yaml ps      # tous les services doivent être « Up »
```

### 5.6 Sauvegardes

Sauvegarde quotidienne de la base à 3 h, gardée 14 jours (deux valeurs proposées ; la durée se change avec `AXIS_BACKUP_KEEP_DAYS`). Le script est dans le dépôt : `deploy/backup.sh`. Il écrit `~/sauvegardes/axis-AAAA-MM-JJ-HHMM.dump` (droits 600), ne remplace jamais une bonne sauvegarde par une sauvegarde interrompue, et supprime les plus anciennes.

```bash
~/axis/deploy/backup.sh                       # essai à la main : « Sauvegarde : … »
crontab -e                                    # puis ajouter la ligne :
0 3 * * * $HOME/axis/deploy/backup.sh >> $HOME/sauvegardes/journal.log 2>&1
```

**Test de restauration** (script `deploy/restore-test.sh`), à faire après la première sauvegarde puis une fois par mois. Il restaure la sauvegarde la plus récente dans une base **à part**, compte quelques tables, puis supprime cette base ; la base réelle n'est pas touchée :

```bash
~/axis/deploy/restore-test.sh                 # ou : deploy/restore-test.sh ~/sauvegardes/<fichier>.dump
```

Les deux scripts ont été essayés sur la base PostgreSQL du PC de développement (sauvegarde, rotation, restauration à part). Ils n'ont jamais tourné sur le VPS.

Limites : la sauvegarde reste sur le même serveur (une copie hors du serveur est à décider : où, par qui) ; les fichiers envoyés (volume `vps_media`) ne sont pas sauvegardés par ce script.

### 5.7 Aucune donnée de démonstration ; compte administrateur réel

- Ne jamais lancer `seed_demo` sur le serveur. La commande refuse de tourner si `DJANGO_DEBUG` n'est pas `true` **ou** si `AXIS_ENVIRONMENT` ne vaut pas `local` ; `compose.vps.yaml` fixe le debug à `false` et ne définit pas `AXIS_ENVIRONMENT`. Ne jamais ajouter `AXIS_ENVIRONMENT` dans `.env.vps`.
- Au premier démarrage, `bootstrap_axis` crée seulement : les lieux Cotonou et Parakou, leurs deux itinéraires, le véhicule « Yutong » sans capacité, le moyen de paiement FedaPay sans frais client, des réglages vides, les arrêts de la ligne et les 8 prix par tronçon (section 2 ter ; Savè, Glazoué, Dassa et Bohicon créés inactifs, à activer avec `apply_axis`). Aucun compte de démonstration, aucun départ.
- Le compte administrateur réel se crée sur place avec `create_admin` (5.0, étape 5) : mot de passe saisi masqué, jamais écrit dans un fichier. Laisser `AXIS_ADMIN_USERNAME` et `AXIS_ADMIN_PASSWORD` vides. (Ces variables restent possibles, mais elles obligent à écrire le mot de passe dans `.env.vps` puis à l'en retirer.)
- Ne pas utiliser `createsuperuser` : le compte serait créé avec le rôle « Client » et refusé par le portail `/admin`.
- À saisir ensuite dans le portail `/admin` avant toute vente : capacité du véhicule, départs, durée de blocage d'un siège (`ticket_hold_minutes`), téléphone et WhatsApp de contact.

### 5.8 Le site est servi par le VPS ; et le site Vercel de démonstration ?

Le site officiel est le service `frontend` du VPS. Pour que le site Vercel puisse aussi appeler cette API (variante B uniquement : un site en HTTPS ne peut pas appeler une API en HTTP) :

1. Ajouter l'adresse du site Vercel à `DJANGO_CORS_ALLOWED_ORIGINS` (séparée par une virgule), puis `docker compose --env-file .env.vps -f compose.vps.yaml up -d backend`.
2. Sur Vercel : `NEXT_PUBLIC_API_URL` = `https://api.<DOMAINE>/api/v1`, puis redéployer.

Limite connue : `FEDAPAY_CALLBACK_URL` n'a qu'une valeur. Un paiement lancé depuis le site Vercel renverra donc l'acheteur sur le site du VPS, qui ne connaît pas sa réservation (elle est gardée dans le navigateur, par site). Le billet est quand même émis par le serveur, mais l'acheteur sans compte ne le retrouve pas à l'écran. Le site Vercel convient donc pour montrer, pas pour vendre.

### 5.9 Passer de A à B

Prérequis : le domaine est acheté, et les enregistrements DNS de `<DOMAINE>` et de `api.<DOMAINE>` pointent vers `<IP>` (à vérifier avec `dig +short <DOMAINE>` et `dig +short api.<DOMAINE>`).

1. `sudo ufw allow 443/tcp` (déjà fait au point 5.2 si la liste complète a été appliquée).
2. Sauvegarde : `~/axis/backup.sh`.
3. Dans `.env.vps`, changer exactement ces lignes :

   | Variable | Nouvelle valeur |
   |---|---|
   | `AXIS_CADDYFILE` | `Caddyfile.https` |
   | `AXIS_DOMAIN` | `<DOMAINE>` |
   | `DJANGO_ALLOWED_HOSTS` | `api.<DOMAINE>` |
   | `DJANGO_CORS_ALLOWED_ORIGINS` | `https://<DOMAINE>` |
   | `DJANGO_CSRF_TRUSTED_ORIGINS` | `https://api.<DOMAINE>` |
   | `PUBLIC_WEB_URL` | `https://<DOMAINE>` |
   | `NEXT_PUBLIC_API_URL` | `https://api.<DOMAINE>/api/v1` |
   | `FEDAPAY_CALLBACK_URL` | `https://<DOMAINE>/paiement/retour` |
   | `FEDAPAY_WEBHOOK_SECRET` | secret du nouveau webhook (étape 5) |
   | `DJANGO_SECRET_KEY` | nouvelle valeur (toutes les sessions ouvertes sont déconnectées) |

4. Changer aussi tout ce qui a circulé en clair pendant la variante A : le mot de passe du compte administrateur (dans `/django-admin/`, une fois en HTTPS) et la clé secrète ci-dessus. `POSTGRES_PASSWORD` n'a pas circulé sur le réseau ; le changer demande une commande dans la base (`ALTER USER`), ce n'est pas indispensable.
5. Chez FedaPay : déclarer le webhook `https://api.<DOMAINE>/api/v1/client/webhooks/fedapay/`, retirer l'ancien.
6. Appliquer (le site doit être reconstruit, son adresse d'API est fixée au build) :
   ```bash
   docker compose --env-file .env.vps -f compose.vps.yaml up -d --build
   ```
7. Vérifier : section 4 de ce document, avec les nouvelles adresses.

Si les données de la variante A étaient fictives, repartir d'une base vide est plus propre : avant l'étape 6, `docker compose --env-file .env.vps -f compose.vps.yaml down` puis `docker volume rm axis_vps_postgres_data` (**efface la base** ; le nom exact du volume est à lire avec `docker volume ls`).

### 5.10 Reconstruire les applications mobiles

Sur le PC, une fois l'API en HTTPS :

```bash
cd mobile-flutter && flutter build apk --release --dart-define=AXIS_API_URL=https://api.<DOMAINE>/api/v1
cd ../mobile-staff && flutter build apk --release --dart-define=AXIS_API_URL=https://api.<DOMAINE>/api/v1
```

Les APK sont dans `build/app/outputs/flutter-apk/app-release.apk` de chaque dossier.

**Avant toute publication**, deux points non traités :
- Les deux apps autorisent encore le HTTP non chiffré (`android:usesCleartextTraffic="true"` dans `android/app/src/main/AndroidManifest.xml` de `mobile-flutter` et de `mobile-staff`). À passer à `false` : c'est une modification du code, non faite.
- Les APK release sont signés avec la clé de débogage (`signingConfig = signingConfigs.getByName("debug")`). Une publication demande une vraie clé de signature.

Pour un essai sur la variante A seulement : `--dart-define=AXIS_API_URL=http://<IP>/api/v1` (fonctionne parce que le HTTP non chiffré est encore autorisé).

### 5.11 Retour arrière

- **Le premier déploiement échoue** : `docker compose --env-file .env.vps -f compose.vps.yaml down`. Rien d'autre n'a été touché sur le serveur ; les volumes restent. Les journaux se lisent avec `... logs backend` (ou `frontend`, `caddy`).
- **Avant chaque mise à jour**, toujours dans cet ordre :
  ```bash
  cd ~/axis && C="docker compose --env-file .env.vps -f compose.vps.yaml"
  deploy/backup.sh                                          # sauvegarde juste avant
  git log -1 --oneline | tee -a ~/versions-deployees.txt    # version qui tourne encore
  git pull && $C up -d --build                              # mise à jour
  ```
- **Une mise à jour casse le site** : revenir à la version notée juste avant et reconstruire.
  ```bash
  cd ~/axis && tail -2 ~/versions-deployees.txt            # la ligne précédente = version qui marchait
  git checkout <COMMIT>
  docker compose --env-file .env.vps -f compose.vps.yaml up -d --build
  ```
  Si la mise à jour contenait une migration, le code précédent peut ne pas comprendre la base modifiée : restaurer alors aussi la sauvegarde faite juste avant (point suivant).
  Avec la copie par archive (5.3), garder l'archive précédente et la redéployer dans un dossier à part.
- **Une migration a modifié la base** : restaurer la sauvegarde faite juste avant (toujours lancer `~/axis/backup.sh` avant une mise à jour) :
  ```bash
  C="docker compose --env-file .env.vps -f compose.vps.yaml"
  $C stop backend holds payments
  $C exec -T db pg_restore -U axis -d axis --clean --if-exists < ~/sauvegardes/axis-AAAA-MM-JJ.dump
  $C up -d
  ```
  Tout ce qui a été vendu ou payé depuis la sauvegarde est alors perdu en base : à ne faire qu'en dernier recours, et à rapprocher ensuite des paiements visibles chez FedaPay.
- **Le passage de A à B échoue** (certificat refusé, DNS pas encore propagé) : remettre les anciennes valeurs dans `.env.vps` et relancer la commande de l'étape 6 ; le site revient en HTTP sur l'IP.

### 5.12 Contrôles après le déploiement

1. `$C ps` : les six services sont « Up » ; `$C logs --tail 50 backend` sans erreur.
2. `https://axistransportlogistique.com` s'ouvre avec le cadenas ; `http://` redirige vers `https://`.
3. `https://api.axistransportlogistique.com/api/v1/health/` répond.
4. Depuis un autre PC, les ports 5432 et 8000 du serveur sont fermés (`nc -zv <IP> 5432` et `nc -zv <IP> 8000` échouent).
5. Connexion au portail `/admin` avec le compte de l'étape 5 ; l'onglet « Tarifs par tronçon » montre les 10 prix ; aucun compte `demo_*` dans « Équipe & rôles ».
6. Onglet « Agence et taxes » rempli par l'administrateur ; un billet de test affiche ces informations.
7. Un paiement sandbox de bout en bout : billet émis au prix affiché, webhook reçu (onglet « Incidents de paiement » vide).
8. `deploy/backup.sh` puis `deploy/restore-test.sh` réussissent ; la ligne cron est en place (`crontab -l`).
9. `sudo reboot`, puis `$C ps` : tout redémarre seul.

### 5.12 bis Mise à jour vers les migrations 0020 à 0022

La production s'arrête à `0019`. Ces trois migrations n'ajoutent que des tables et des colonnes vides ou facultatives :

| Migration | Contenu |
|---|---|
| `0020_boarding_points` | Table des points d'embarquement ; colonnes facultatives sur les réservations et les billets |
| `0021_trip_stop_arrival` | Table des arrivées confirmées par le contrôleur |
| `0022_parcel_photo` | Table des photos de colis |

1. Sauvegarder avant tout : `deploy/backup.sh`, et vérifier que le fichier existe.
2. Renseigner `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY` et `CLOUDINARY_API_SECRET` dans `.env.vps` (à la main, jamais dans le dépôt). Sans elles, l'enregistrement d'un colis est refusé.
3. Construire, démarrer, puis appliquer : `$C exec backend python manage.py migrate`.
4. Vérifier : `$C exec backend python manage.py showmigrations core | tail -4` affiche `[X]` jusqu'à `0022`.
5. Créer le prix de base des colis (2 000 FCFA, annoncé par Eddy ; à confirmer en réunion). Sans ce réglage, un colis est enregistré sans prix et le guichet doit le fixer :

```bash
$C exec backend python manage.py shell -c "from apps.core.models import SystemSetting; SystemSetting.objects.get_or_create(key='parcel_base_price_fcfa', defaults={'value': 2000})"
```

Un tronçon sans tarif renvoie désormais une erreur 400 `segment_fare_missing`, sans prix de repli : contrôler l'avertissement de l'onglet « Tarifs par tronçon » après le déploiement.

### 5.13 Non vérifiable sans le serveur réel

- Les caractéristiques du VPS (mémoire, processeurs, disque) et donc sa capacité à construire et faire tourner le projet.
- La construction des images sur le serveur, en particulier celle du site.
- Le démarrage complet de `compose.vps.yaml` : les services n'ont jamais tourné ensemble derrière Caddy.
- Le routage par chemin de la variante A (`/api/`, `/django-admin/`, `/static/` vers l'API, le reste vers le site) et l'affichage de l'administration Django à travers le proxy.
- L'obtention des certificats par Caddy en variante B, et la redirection automatique du port 80.
- La lecture de la vraie adresse IP des visiteurs (`AXIS_NUM_PROXIES=1`) pour les limites de requêtes.
- La réception réelle d'un webhook FedaPay : jamais vue de bout en bout, sur aucun environnement.
- L'acceptation par FedaPay d'un webhook en HTTP sur une IP (variante A) ou d'un nom `sslip.io`.
- Les commandes de sécurisation SSH sur l'image Ubuntu 24.04 de Contabo (nom du service, fichiers de configuration déjà présents).
- Les sauvegardes et la restauration sur le serveur (scripts essayés seulement sur le PC), le redémarrage automatique après `reboot`.
- L'interface du tableau de bord FedaPay (où se déclarent le webhook et l'adresse de retour) et l'acceptation de ces adresses.
- Le comportement des apps mobiles en release contre une API distante.

## 5 ter. Scénario de test pour le boss (serveur vide, FedaPay en mode test)

But : sur le serveur fraîchement installé (5.0 terminé, `FEDAPAY_ENVIRONMENT=sandbox`), obtenir un départ réservable et payer un billet en mode test. **Aucune donnée de démonstration** : `seed_demo` n'est ni nécessaire ni autorisé (il refuse de tourner sur le serveur). Tout se crée dans le portail `https://axistransportlogistique.com/admin`, avec le compte administrateur de l'étape 10.

**Ce qui existe déjà après le premier démarrage** : les villes Cotonou et Parakou (actives), les parcours Parakou → Cotonou et Cotonou → Parakou, le car « Yutong » sans capacité, les 8 prix par tronçon (Parakou ↔ Cotonou : 7 500 FCFA), le moyen de paiement FedaPay, la TVA 18 % incluse. Savè, Glazoué, Dassa et Bohicon sont créées inactives : `apply_axis` les active (section 2 ter).

**À créer dans `/admin`** (valeurs réelles décidées par l'agence ; rien n'est proposé ici) :

1. **Tarifs & règles** → délai de blocage d'un siège pendant le paiement (`ticket_hold_minutes`, en minutes) : **obligatoire**, sans lui aucune réservation n'est possible.
2. **Flotte** → car « Yutong » : saisir sa capacité réelle (et son plan de sièges s'il est connu), enregistrer.
3. **Agence et taxes** → informations de l'agence (sinon le billet affiche « À renseigner »).
4. **Trajets & planning** → ajouter **un départ de test** : parcours Parakou → Cotonou, car Yutong, date et heure de départ dans le futur, note « Départ de test ». Ce départ est visible des clients : faire le scénario **avant d'annoncer le site**, puis l'annuler (étape 9).
5. Facultatif : téléphone et WhatsApp de contact (Tarifs & règles).

**Réserver et payer en mode test** (téléphone ou PC, navigateur ordinaire) :

6. Ouvrir `https://axistransportlogistique.com`, « Créer un compte » (compte client de test), rechercher Parakou → Cotonou à la date du départ de test, choisir un siège. Le bouton doit afficher **« Payer 7 500 FCFA »** (prix affiché = montant payé).
7. Sur la page FedaPay de test, choisir le Mobile Money et utiliser un numéro de test. Numéros communiqués par Eddy (documentation FedaPay, non vérifiés ici) :

   | Numéro | Opérateur | Résultat attendu |
   |---|---|---|
   | `66000001` | MTN | paiement réussi : billet émis, QR affiché |
   | `66000000` | MTN | paiement refusé : aucun billet, siège libéré à la fin du délai |
   | `64000001` | Moov | paiement réussi |
   | `64000000` | Moov | paiement refusé |

8. Vérifications après un paiement réussi : le billet affiche « Payé », 7 500 FCFA, la vente « Vente en ligne », le mode de paiement ; il apparaît dans « Vos billets » ; dans `/admin`, l'onglet « Incidents de paiement » reste vide (webhook bien reçu). Si le billet reste « réservé » : bouton « Vérifier mon paiement » ; le rattrapage automatique le confirme aussi en moins d'une minute. Contrôle : depuis l'app du contrôleur (compte créé par l'admin dans « Équipe & rôles »), scanner le QR le jour du départ.
9. Fin du test : **Trajets & planning** → « Annuler » sur le départ de test ; il n'est plus proposé aux clients. Les billets et paiements de test restent en base (sandbox : aucun argent réel).
10. Avant l'ouverture réelle : passer `FEDAPAY_ENVIRONMENT=live` avec la clé et le webhook live (étape 11 de 5.0), vérifier chez FedaPay que les frais sont supportés par l'agence, puis créer les vrais départs.

## 5 bis. À faire avant ouverture au public

### Pièces déposées pour la location (pièce d'identité, permis) et preuves de dépôt des colis

Ce que fait le code aujourd'hui (constaté en lisant le code, non essayé sur le VPS) :

- Les fichiers sont enregistrés dans `/app/media` (volume `vps_media` sur le VPS), sous `rental-documents/identity/`, `rental-documents/licence/` et `parcel-proofs/`, avec le nom d'origine du fichier.
- Django ne sert `/media/` **que si `DEBUG` est activé** (`backend/config/urls.py`). Sur le VPS, `DJANGO_DEBUG` est fixé à `false` : une adresse `/media/...` répond 404. WhiteNoise ne sert que les fichiers statiques (`/static/`), et `deploy/Caddyfile.https` n'a aucune règle `/media` : il transmet tout `api.<DOMAINE>` à Django, qui répond 404. Les pièces ne sont donc **pas publiques** sur le VPS… mais **personne ne peut les consulter**, administrateur compris.
- L'API de location renvoie l'adresse de ces fichiers (`identity_document`, `driving_licence`) au client propriétaire et au personnel autorisé.
- **En local** (`compose.yaml`, `DEBUG` activé), `/media/` est servi **sans contrôle d'accès** : quiconque connaît l'adresse peut ouvrir le fichier.

Non vérifié : le comportement réel derrière Caddy sur le VPS, et les adresses renvoyées par l'API en production.

Solution proposée (non faite) : une vue Django protégée, par exemple `/api/v1/documents/<id>/<champ>/`, réservée aux administrateurs (et au client propriétaire si c'est décidé), qui lit le fichier sur le disque et le renvoie ; l'API ne renverrait plus l'adresse `/media/` directe ; noms de fichiers remplacés par un identifiant aléatoire à l'enregistrement ; chaque consultation journalisée (compte, date, document). Garder `/media/` jamais servi, ni par Django ni par Caddy.

## 6. À construire en étape 5 (notes, rien n'est codé)

- **Bouton « Débloquer un compte » dans le portail `/admin`.** Aujourd'hui, débloquer un identifiant bloqué après trop de connexions échouées demande une commande sur le serveur : `python manage.py unblock_login <identifiant>` (voir section 2). Le bouton appellerait le même code, réservé à l'administrateur, et resterait journalisé.
- **Supprimer les routes en double avant l'ouverture au public.** Les mêmes points d'accès répondent sous `/api/` et sous `/api/v1/` (`backend/config/urls.py`). Vérifier qu'aucun écran ni aucune app n'utilise plus `/api/` seul, puis retirer ce préfixe : une seule adresse par point d'accès, une seule surface à surveiller.
- **Réservations client ouvertes, protégées dans le code.** `/api/v1/client/bookings/` accepte toute demande (`AllowAny`, pour l'achat sans compte sur le web) ; l'accès à une réservation existante n'est protégé que par une vérification écrite dans la vue (propriétaire connecté ou jeton invité, `_assert_can_access` dans `backend/apps/core/urls_client.py`). Cette protection fonctionne et elle est testée, mais elle est fragile : une nouvelle action ajoutée sans cette vérification serait ouverte à tous. Garder les tests existants et en ajouter un pour chaque nouvelle action.

## Colis : départ et destination (lot cc/colis-depart-destination)

- Ordre de déploiement : **serveur d'abord**, puis la nouvelle version de l'app.
- Serveur : `/staff/sales/parcel/` accepte un `trip` facultatif. Avec un départ, le départ et la destination du colis doivent être sur son trajet, dans le sens du bus, et le colis est rattaché à ce départ. Sans départ (app publiée), le colis reste accepté s'il relie deux villes actives distinctes.
- App : l'écran colis affiche le bus, le départ (par défaut l'arrêt où se trouve le bus) et la destination (arrêts suivants), puis un récapitulatif avant l'envoi.

