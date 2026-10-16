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

**Limite de connexion : fonctionnement et seuils proposés** (propositions techniques, pas des règles de la direction ; modifiables par les variables ci-dessus) :

- Seules les connexions échouées comptent. Une connexion réussie efface les échecs de son adresse, pas ceux des autres adresses.
- `10/hour` par identifiant et adresse : une personne qui se trompe de mot de passe s'arrête bien avant 10 essais en une heure ; une seule adresse ne peut pas tester plus de 10 mots de passe par heure sur un compte. Des échecs provoqués depuis une autre adresse ne bloquent pas le titulaire (par exemple un contrôleur).
- `50/hour` par identifiant, toutes adresses : 5 fois le seuil précédent, donc jamais atteint par un utilisateur seul ; limite une attaque répartie sur de nombreuses adresses à 50 essais par heure et par compte. Contrepartie : une attaque utilisant au moins 5 adresses peut encore bloquer un compte pendant au plus une heure.
- `30/min` par adresse, tous identifiants : inchangé ; élevé parce que beaucoup d'abonnés mobiles partagent la même adresse.
- Débloquer un compte (toutes adresses), sur le serveur : `docker compose --env-file .env.vps -f compose.vps.yaml exec backend python manage.py unblock_login <identifiant>` (majuscules et espaces ignorés). Il n'existe pas encore de bouton dans le portail `/admin`.
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

## 2 ter. Tarifs par tronçon (À CONFIRMER par la direction)

Ligne, dans l'ordre : Parakou, Savè, Kétou, Porto-Novo, Cotonou. Un prix par paire d'arrêts, le même dans les deux sens.
Ces dix prix ont été fournis par l'équipe et **restent à confirmer par la direction** :

| Tronçon | Prix (FCFA) |
|---|---|
| Parakou ↔ Cotonou | 7 500 |
| Parakou ↔ Porto-Novo | 7 500 |
| Parakou ↔ Kétou | 6 500 |
| Parakou ↔ Savè | 4 500 |
| Savè ↔ Cotonou | 6 500 |
| Savè ↔ Porto-Novo | 6 500 |
| Savè ↔ Kétou | 2 500 |
| Kétou ↔ Porto-Novo | 4 000 |
| Kétou ↔ Cotonou | 4 000 |
| Porto-Novo ↔ Cotonou | 1 500 |

- Chargement : commande `python manage.py load_segment_fares`, aussi lancée par `bootstrap_axis` à chaque démarrage. Elle n'ajoute que ce qui manque : un prix déjà présent (modifié par l'administrateur) n'est jamais écrasé. Les arrêts Savè, Kétou et Porto-Novo, s'ils n'existent pas, sont créés **inactifs** (invisibles des clients). Aucun compte n'est créé.
- Modification : portail `/admin`, onglet « Tarifs par tronçon » (administrateur uniquement), avec confirmation et historique (qui, quand, ancien et nouveau prix).
- **Prix de vente du trajet complet** (lot 2) : un départ se vend au prix du tronçon entre le départ et l'arrivée de son parcours (Parakou ↔ Cotonou : 7 500). La règle tarifaire du parcours (« Tarifs & règles ») ne fixe plus le prix ; elle reste enregistrée. Un parcours sans prix dans la grille n'est pas vendable. La vente d'un tronçon intermédiaire n'est pas ouverte (places par tronçon : étape 3).
- Les arrêts Savè, Kétou et Porto-Novo restent **inactifs** : absents des listes de villes lues par le site et les apps, jusqu'à ce que l'administrateur les active.
- Une réservation ou un billet garde le prix enregistré au moment de la vente, même si la grille change ensuite.

### Montant payé par le client (décision de la direction, lot 2)

- Le montant affiché au client est celui qu'il paie. Axis envoie à FedaPay exactement le prix du billet ; les frais FedaPay sont supportés par l'agence.
- Le taux de frais client de chaque moyen de paiement vaut 0 par défaut (migration `0012_client_fee_zero`, puis `bootstrap_axis`). Il reste modifiable par l'administrateur (`/django-admin/`, moyens de paiement) ; s'il est relevé, le bouton « Payer » affiche le montant réellement débité.
- Le web, les apps et le billet n'affichent plus de ligne « Frais de paiement » ni « Total ». L'API garde ses champs : `fee_amount` = 0 et `total` = prix.
- Une transaction FedaPay créée avant cette migration avec l'ancien total (prix + frais) ne correspond plus au montant dû : son paiement est refusé et inscrit dans les incidents de paiement, à rembourser à la main.

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

**Statut de cette section** : rédigée sans accès au serveur. Aucune commande n'a été lancée sur le VPS. Seule la syntaxe de `compose.vps.yaml` et des deux fichiers Caddy a été validée sur un PC. Tout le reste est à vérifier sur place ; la liste est au point 5.12.

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

### 5.1 Mesurer si le VPS tient

Mesure faite sur le PC de développement, services au repos (`docker stats`) :

| Service | Mémoire |
|---|---|
| `backend` (gunicorn, 3 processus) | 191 Mo |
| `frontend` | 113 Mo |
| `db` | 36 Mo |
| **Total mesuré** | **340 Mo** |

Non mesuré : les services `holds`, `payments` et `caddy`, la charge avec des visiteurs, et surtout **la construction du site sur le serveur** (`npm run build`), qui demande nettement plus de mémoire que le fonctionnement. Les caractéristiques du VPS ne sont pas connues ici. À faire sur le serveur :

```bash
free -h && nproc && df -h /        # mémoire, processeurs, disque disponibles
docker stats --no-stream            # après le démarrage (5.4)
```

Si la construction échoue faute de mémoire : ajouter un fichier d'échange (swap) ou construire les images ailleurs. Aucune des deux solutions n'est préparée.

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

Sauvegarde quotidienne de la base, à 3 h, gardée 14 jours (ces deux valeurs sont des propositions). Créer `~/axis/backup.sh` sur le serveur :

```bash
#!/bin/sh
set -eu
cd "$HOME/axis"
mkdir -p "$HOME/sauvegardes"
docker compose --env-file .env.vps -f compose.vps.yaml exec -T db pg_dump -U axis -Fc axis > "$HOME/sauvegardes/axis-$(date +%F).dump"
find "$HOME/sauvegardes" -name 'axis-*.dump' -mtime +14 -delete
```

Puis `chmod +x ~/axis/backup.sh` et, dans `crontab -e` : `0 3 * * * $HOME/axis/backup.sh`.

**Test de restauration**, à faire au moins une fois, dans une base à part (la base réelle n'est pas touchée) :

```bash
cd ~/axis && C="docker compose --env-file .env.vps -f compose.vps.yaml"
$C exec -T db createdb -U axis axis_essai_restauration
$C exec -T db pg_restore -U axis -d axis_essai_restauration < ~/sauvegardes/axis-AAAA-MM-JJ.dump
$C exec -T db psql -U axis -d axis_essai_restauration -c "select count(*) from core_ticket;"
$C exec -T db dropdb -U axis axis_essai_restauration
```

Limites : la sauvegarde reste sur le même serveur (une copie hors du serveur est à décider : où, par qui) ; les fichiers envoyés (volume `vps_media`) ne sont pas sauvegardés par ce script.

### 5.7 Aucune donnée de démonstration ; compte administrateur réel

- Ne jamais lancer `seed_demo` sur le serveur. La commande refuse de tourner quand le debug est coupé, et `compose.vps.yaml` le fixe à `false`.
- Au premier démarrage, `bootstrap_axis` crée seulement : les lieux Cotonou et Parakou, leurs deux itinéraires, le véhicule « Yutong » sans capacité, le moyen de paiement FedaPay sans frais client, des réglages vides, les arrêts de la ligne et la grille des 10 prix par tronçon (section 2 ter ; Savè, Kétou et Porto-Novo créés inactifs). Aucun compte de démonstration, aucun départ.
- Le compte administrateur est créé au premier démarrage à partir de `AXIS_ADMIN_USERNAME` et `AXIS_ADMIN_PASSWORD`, saisis dans `.env.vps` sur le serveur. Une fois connecté une première fois, vider `AXIS_ADMIN_PASSWORD` du fichier (le compte existe déjà, la variable ne sert plus).
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
- **Une mise à jour casse le site** : revenir au code précédent et reconstruire.
  ```bash
  cd ~/axis && git log --oneline -5        # repérer le commit précédent
  git checkout <COMMIT>
  docker compose --env-file .env.vps -f compose.vps.yaml up -d --build
  ```
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

### 5.12 Non vérifiable sans le serveur réel

- Les caractéristiques du VPS (mémoire, processeurs, disque) et donc sa capacité à construire et faire tourner le projet.
- La construction des images sur le serveur, en particulier celle du site.
- Le démarrage complet de `compose.vps.yaml` : les services n'ont jamais tourné ensemble derrière Caddy.
- Le routage par chemin de la variante A (`/api/`, `/django-admin/`, `/static/` vers l'API, le reste vers le site) et l'affichage de l'administration Django à travers le proxy.
- L'obtention des certificats par Caddy en variante B, et la redirection automatique du port 80.
- La lecture de la vraie adresse IP des visiteurs (`AXIS_NUM_PROXIES=1`) pour les limites de requêtes.
- La réception réelle d'un webhook FedaPay : jamais vue de bout en bout, sur aucun environnement.
- L'acceptation par FedaPay d'un webhook en HTTP sur une IP (variante A) ou d'un nom `sslip.io`.
- Les commandes de sécurisation SSH sur l'image Ubuntu 24.04 de Contabo (nom du service, fichiers de configuration déjà présents).
- Les sauvegardes, la restauration et le redémarrage automatique après `reboot`.
- Le comportement des apps mobiles en release contre une API distante.

## 6. À construire en étape 5 (notes, rien n'est codé)

- **Bouton « Débloquer un compte » dans le portail `/admin`.** Aujourd'hui, débloquer un identifiant bloqué après trop de connexions échouées demande une commande sur le serveur : `python manage.py unblock_login <identifiant>` (voir section 2). Le bouton appellerait le même code, réservé à l'administrateur, et resterait journalisé.
- **Supprimer les routes en double avant l'ouverture au public.** Les mêmes points d'accès répondent sous `/api/` et sous `/api/v1/` (`backend/config/urls.py`). Vérifier qu'aucun écran ni aucune app n'utilise plus `/api/` seul, puis retirer ce préfixe : une seule adresse par point d'accès, une seule surface à surveiller.
- **Réservations client ouvertes, protégées dans le code.** `/api/v1/client/bookings/` accepte toute demande (`AllowAny`, pour l'achat sans compte sur le web) ; l'accès à une réservation existante n'est protégé que par une vérification écrite dans la vue (propriétaire connecté ou jeton invité, `_assert_can_access` dans `backend/apps/core/urls_client.py`). Cette protection fonctionne et elle est testée, mais elle est fragile : une nouvelle action ajoutée sans cette vérification serait ouverte à tous. Garder les tests existants et en ajouter un pour chaque nouvelle action.
