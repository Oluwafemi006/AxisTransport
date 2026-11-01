# AGENTS.md — règles communes (Claude Code et Antigravity)

Projet AXIS Transport : vente de billets de car au Bénin (web, application mobile, portails du personnel).
Toutes les réponses, rapports, messages de commit et textes d'interface sont en **français**.

## 1. Règles absolues

- **Aucune supposition.** Une règle, un contact, un tarif, un domaine, un horaire ou un chemin inconnu s'écrit « À renseigner » ou « inconnu », et on le signale dans le rapport. Ne jamais inventer.
- Les décisions validées sont dans `DECISIONS.md`. Ne rien y ajouter sans décision transmise par Eddy.
- **Interdits :**
  - pousser (`git push`) : Eddy pousse lui-même ;
  - lancer une commande autre que les tests (ci-dessous) sans accord d'Eddy : conteneurs, compilation d'APK, tunnels, scripts ;
  - lire, modifier ou commiter `.env`, `.env.*`, une clé, un keystore, `key.properties`, un dump de base ;
  - se connecter au VPS (SSH ou autre commande distante) ;
  - mettre un secret, un mot de passe ou une donnée d'agence (raison sociale, IFU, RCCM, comptes bancaires, téléphones…) dans le code, les migrations, les fixtures, les tests, la documentation ou un message : ces informations se saisissent uniquement dans le portail `/admin` ;
  - générer un numéro de facture, un NIM, un code MeCeF/DGI ou un QR de la DGI, ou toute mention suggérant une facture normalisée (e-MECeF hors périmètre) ;
  - modifier la logique de paiement, de webhook, de sécurité ou une migration existante sans l'avoir expliqué à Eddy et obtenu son accord ;
  - lancer `seed_demo` ailleurs que sur le poste de développement (refusé hors `DJANGO_DEBUG=true` et `AXIS_ENVIRONMENT=local`).
- Valeurs fictives dans les tests : toujours visiblement marquées `TEST`.

## 2. Travail à deux outils

- **Une branche par tâche** : `cc/<nom>` pour Claude Code, `ag/<nom>` pour Antigravity, partie de `main`.
- **Un seul outil par branche à la fois.** Ne jamais modifier la branche de l'autre outil.
- La tâche en cours, sa branche, l'outil responsable et son statut sont dans `TASKS.md` : le mettre à jour en début et en fin de tâche.
- Commits locaux, petits, en français, sans squash. Fusion dans `main` (locale, `--no-ff`) seulement si tous les tests passent, et seulement sur demande d'Eddy. Ne jamais supprimer une branche.

## 3. Tests (commandes exactes)

Base PostgreSQL de test : conteneur `axis-db-1` (réseau Docker `axis_default`). Le démarrer seulement avec l'accord d'Eddy : `docker compose up -d db`.

**Serveur** (Django, sur PostgreSQL), depuis la racine du dépôt :

```bash
docker run --rm --network axis_default -v "$PWD/backend:/app:ro" -e PYTHONDONTWRITEBYTECODE=1 \
  -e DATABASE_URL=postgresql://axis:axis@db:5432/axis_transport -w /app axis-backend:latest \
  sh -c "python manage.py makemigrations --check --dry-run --settings=config.settings_test && \
         python manage.py test apps.core.tests --settings=config.settings_test --noinput"
```

**Application mobile** (Flutter) :

```bash
cd mobile-flutter && flutter test && flutter analyze
```

**Site** (Next.js, vérification des types) :

```bash
cd frontend && npm run typecheck
```

(`npm run lint` ne fonctionne pas : `next lint` n'existe plus dans cette version de Next.)

## 4. Rapport de fin de tâche

10 lignes maximum, en français : ce qui a été fait (fichiers), résultat réel de chaque suite de tests (nombre de tests, OK/échec), ce qui n'a pas été vérifié, décisions nécessaires. Ne jamais affirmer un résultat non exécuté.

## 5. Structure du dépôt

| Dossier | Contenu |
|---|---|
| `backend/` | API Django 5 / Django REST Framework, une seule application `apps/core` : `models.py`, `views.py` (personnel et admin), `urls_client.py` (espace client), `urls_staff.py`, `serializers.py`, `services.py` (réservation, prix, taxes), `payments.py` (FedaPay, reçus, rattrapage), `permissions.py`, `management/commands/`, `tests/` |
| `frontend/` | Site Next.js : `src/app` (pages `admin`, `guichet`, `controleur`, `paiement/retour`, `t/[reference]` = billet public), `src/components` (portails), `src/lib` (`api.ts`, `types.ts`, `ticket-print.ts`) |
| `mobile-flutter/` | Application unique clients et personnel (Riverpod, go_router) : `lib/core` (API, modèles, session), `lib/features/<domaine>`, `lib/shared`, `test/` |
| `mobile-staff/` | Ancienne application du personnel, gardée jusqu'à l'essai de l'application unique sur téléphone. Ne pas la supprimer. |
| `mobile/`, `mobile-expo/` | Anciennes applications (React Native, Expo), non utilisées |
| `deploy/` | Caddy (`Caddyfile.http`, `Caddyfile.https`), `backup.sh`, `restore-test.sh` |
| `compose.yaml` | Poste de développement ; `compose.vps.yaml` : serveur ; `compose.recette.yaml` : recette |
| `DEPLOY.md` | Déploiement, variables, procédure VPS, points à faire avant ouverture |

## 6. Conventions constatées dans le code

- **Le serveur décide, les clients affichent.** Prix, frais, taxes, disponibilité, statut de paiement et lignes du billet (`print_info`) sont calculés côté serveur ; le site et l'app n'en recalculent aucun.
- Prix en francs CFA entiers ; affichage « FCFA », jamais « XOF ». Prix affiché TTC = montant payé.
- Une donnée absente : masquée si elle est facultative, « À renseigner » sinon ; jamais une valeur inventée.
- Les mentions de l'agence (raison sociale, IFU, RCCM, adresse, contacts, conditions) sont toujours masquées si elles sont vides, et apparaissent dès leur saisie dans `/admin`.
- Aucune mention « TVA », « TTC » ou « taxe » visible par les clients ni sur le billet ; seuls les champs fiscaux en base et la page admin des taxes les gardent.
- Aucun billet n'est émis sans reçu de paiement vérifié (`PaymentReceipt`) ; webhook, rattrapage et vérification client passent par le même chemin (`payments._settle`).
- Permissions par rôle : `CLIENT`, `COUNTER` (guichet), `CONTROLLER`, `ADMIN` (`permissions.py`) ; l'inscription ne crée que des clients.
- Toute modification sensible par l'admin est journalisée (tarifs par tronçon, agence et taxes, statut manuel d'un billet).
- Seuils et réglages par variables d'environnement documentées dans `DEPLOY.md` ; jamais de valeur réelle dans le dépôt.
- Commentaires et docstrings en français, courts, qui expliquent le pourquoi ; noms de code en anglais.
- Chaque changement de comportement s'accompagne de tests (`backend/apps/core/tests/test_*.py`, `mobile-flutter/test/*_test.dart`).
