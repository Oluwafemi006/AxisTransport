# TASKS.md — tâches en cours

Une ligne par tâche. Mettre à jour en début et en fin de tâche. Un seul outil par branche à la fois.
Statuts : à faire · en cours · à valider par Eddy · terminée · fusionnée dans main.

| Tâche | Branche | Outil | Statut |
| Conformité Play : pages /privacy et /suppression-compte (HTML sans script), redirection /confidentialite ; suppression de compte en attente de décision | `cc/conformite-play` | Claude Code | en cours |
| Profil client modifiable (nom, téléphone, e-mail) et barre du bas masquée sur les écrans secondaires, app 1.0.6+8 | `cc/profil-client` | Claude Code | à valider par Eddy |
| Admin : défauts restants de la revue (double envoi, moyen de paiement confirmé, avertissement tarif) | `cc/admin-defauts` | Claude Code | à valider par Eddy |
|---|---|---|---|
| Mon compte : e-mail du client et changement de mot de passe (app et site) | `cc/changer-mot-de-passe-v2` | Claude Code | à valider par Eddy |
| Couleur principale de l'app alignée sur le bleu du site (mise de côté, `git stash`) | `cc/couleur-primaire` | Claude Code | en attente |
| Nouvel axe Parakou–Savè–Glazoué–Dassa–Bohicon–Cotonou, tarifs, points, démarrage sans réécriture | `cc/nouvel-axe` | Claude Code | à valider par Eddy |
| Mot de passe oublié : code e-mail clients, réinitialisation admin, fermeture des sessions | `cc/mot-de-passe-oublie` | Claude Code | à valider par Eddy |
| Bandeau dynamique d'accueil (sens du bus), prochains départs tous sens et next_available | `ag/accueil-bandeau-sens-du-bus` | Antigravity | à valider par Eddy |
| Réservation multi-passagers, choix/attribution de places et paiements tardifs | `ag/reservation-places-attribution` | Antigravity | fusionnée dans main |
| Points d'embarquement et de débarquement par ville | `ag/points-embarquement` | Antigravity | fusionnée dans main |
| Vente par tronçon : réservation, tarification, montée/descente et billets de bout en bout | `ag/vente-par-troncon` | Antigravity | terminée, en attente de fusion sur GitHub |
| Escales ordonnées, sens de circulation et recherche multi-tronçons | `ag/feature-waypoint-direction-search` | Antigravity | fusionnée dans main |
| Planning hebdomadaire par défaut et validation des dates | `ag/fix-planning-and-dates` | Antigravity | fusionnée dans main |
| Multi-passagers, plan Yutong, retrait TVA et signature mobile | `ag/mobile-alignment` | Antigravity | fusionnée dans main |
| Frais FedaPay supportés par l'agence (montant net FedaPay) | `ag/fedapay-fees` | Antigravity | fusionnée dans main |
| Multi-passagers, alignement car Yutong et suppression TVA | `ag/seats-and-vat` | Antigravity | fusionnée dans main |
| Flux complet d'invitations du personnel (SMTP, backend, frontend) | `ag/admin-invitations` | Antigravity | fusionnée dans main |
| IFU de l'acheteur et partages de l'app du personnel | `ag/billet-personnel` | Antigravity | fusionnée dans main |
| Bouton « Vérifier mon paiement », rattrapage automatique en local, vérification patiente | `confirmation-paiement` | Claude Code | fusionnée dans main |
| Dates passées refusées (site, app et serveur), heure du Bénin | `cc/dates-passees` | Claude Code | fusionnée dans main |
| Planning quotidien à sens alterné et départs vendables au guichet | `cc/planning-guichet` | Claude Code | fusionnée dans main |
| Pages réservées : affichage strict 403 sans mention de rôle | `cc/page-403` | Claude Code | à faire |
| Corrections QA mobile : prix du tronçon, mentions légales, TVA, logo et notifications | `cc/corrections-qa-mobile` | Claude Code | à valider par Eddy |
| Espace contrôleur : tronçons, compteurs, arrivées, colis avec photos | `cc/controleur-fonctions` | Claude Code | à valider par Eddy |
| Accueil : un tronçon par carte et par sens, endpoint des tronçons, plus de prix de repli | `cc/accueil-tous-troncons` | Claude Code | à valider par Eddy |

---

## Point d'étape 19/10/2026

### 0. RÈGLES DE TRAVAIL (inchangées)
- Réponds en français, de façon concise. AUCUNE SUPPOSITION : lis le code, cite fichier:ligne, distingue « vérifié » et « non vérifié ».
- Quand Eddy propose une idée, expose d'abord ses limites. Ce qu'Eddy transmet du boss est « décision validée par le boss (transmise par Eddy) ». Une inconnue technique n'est pas une décision.
- Une branche par tâche (ag/<nom> pour toi, cc/<nom> pour Claude Code), un outil à la fois, dans un worktree (.worktrees/, ignoré par Git). Claude Code relit seulement les diffs (git diff main...ag/<nom>) pour économiser les jetons. Jamais de fusion ni de push sans l'accord d'Eddy.
- Secrets jamais dans le dépôt, les prompts ni les discussions. Données légales de l'agence (RCCM, IFU, raison sociale) : saisies uniquement dans la page admin « Agence et taxes ».
- Ne touche pas à la logique de paiement sans relecture. N'ajoute jamais AXIS_ENVIRONMENT, AXIS_PAYMENT_SIMULATION ou DJANGO_DEBUG dans .env.vps.

### 1. PROJET
Billetterie en ligne de bus Yutong (Parakou–Savè–Glazoué–Dassa–Bohicon–Cotonou), puis colis et location. Stack : Django 5.1/DRF + PostgreSQL, site Next.js, application Flutter unique (mobile-flutter). Dépôt GitHub Oluwafemi006/AxisTransport.

### 2. MISE EN LIGNE (VPS Contabo)
- Site https://axistransportlogistique.com ; API https://api.axistransportlogistique.com/api/v1 ; www redirige vers le domaine sans www. Docker Compose (compose.vps.yaml) + Caddy en HTTPS. Services : db, backend, holds, payments, frontend, caddy.
- FedaPay en SANDBOX (clés du compte d'Eddy). Aucune donnée de démonstration. Compte AXIS_ADMIN créé avec create_admin.
- Déploiement : sur le serveur (utilisateur axis) : cd ~/axis ; git pull ; C="docker compose --env-file .env.vps -f compose.vps.yaml" ; $C build backend holds payments frontend ; $C up -d. Dernière version déployée vérifiée : 38cbd6b.
- Sauvegarde quotidienne à 3 h (deploy/backup.sh). deploy/restore-test.sh pas encore lancé. Ces sauvegardes sont sur le même serveur.

### 3. DÉCISIONS VALIDÉES (boss, via Eddy)
- **Planning hebdomadaire du car unique** (validé le 19/10/2026) :
  - Dimanche 13h00 : Cotonou → Parakou
  - Lundi 13h00 : Parakou → Cotonou
  - Mardi 08h00 : Cotonou → Parakou
  - Mercredi : REPOS ET VISITE TECHNIQUE (aucun départ)
  - Jeudi 08h00 : Parakou → Cotonou
  - Vendredi 08h00 : Cotonou → Parakou
  - Samedi 08h00 : Parakou → Cotonou
  - Reprise Dimanche 13h00 Cotonou → Parakou, et ainsi de suite.
- **TVA retirée de la billetterie** (validé le 19/10/2026) : pas de TVA sur le billet ni sur la facture (seul le montant net TTC en FCFA apparaît, aucune TVA séparée).
- **Frais FedaPay à la charge de l'agence** (confirmé le 19/10/2026) : le client paie exactement le prix affiché (7 500 FCFA), l'agence absorbe les frais dans les paramètres de son compte FedaPay.
- **Prix par paire de villes**, identiques dans les deux sens (nouvel axe, validé par le boss) : Parakou–Cotonou 7500 ; Parakou–Bohicon 6000 ; Parakou–Glazoué 5000 ; Parakou–Dassa 5000 ; Parakou–Savè 3500 ; Savè–Cotonou 6000 ; Savè–Bohicon 3000 ; Bohicon–Cotonou 3000. Aucun autre tronçon n'a de tarif. Modifiables par l'administrateur (onglet « Tarifs par tronçon »).
- Billet : « Billet de transport », jamais « facture » ; FCFA (jamais XOF) ; aucun numéro de facture, NIM, code MeCeF/DGI ni QR DGI générés par Axis ; aucun compte bancaire imprimé.
- Embarquement = départ − 30 min. Heure du Bénin (UTC+1).
- Expiration du blocage de siège : 5 minutes (réglé dans l'admin).
- Paiement en ligne : FedaPay seulement (KKiaPay est inactif et non intégré). Le personnel encaisse en Espèces ou par Mobile Money.
- Comptes du personnel créés par l'admin, une seule application mobile, tableau de bord admin uniquement. Le boss aura un compte administrateur nominatif (pas de rôle « boss »).
- **Limite connue (vente par tronçon)** : le blocage et la vente de sièges restent globaux par trajet entier (un siège vendu sur un tronçon, ex. Parakou–Savè, bloque le siège pour tout le voyage du car et ne peut pas être revendu sur un autre tronçon du même départ). La réutilisation d'un même siège sur des tronçons disjoints fera l'objet d'une étape ultérieure.
- Kétou et Porto-Novo sont retirées de la ligne (désactivées, données conservées) ; le serveur refuse les nouvelles ventes vers ou depuis une ville inactive.

### 4. BRANCHES ET STATUTS
- `main` : fusions de `cc/dates-passees` et `cc/planning-guichet` intégrées.
- `cc/dates-passees` : dates passées refusées (site, app, serveur : réservation d'un départ parti refusée sauf vente du contrôleur à l'arrêt ; location au début passé refusée). 313 tests serveur. Fusionnée dans `main`.
- `cc/planning-guichet` : planning quotidien à sens alterné (1 à 90 jours, sans doublon) et tableau « Prochains départs » au guichet. Fusionnée dans `main`.
- `ag/billet-personnel` (0b7cd21) : relue par Claude Code, fusion possible APRÈS 3 corrections (tâche pour Antigravity) : (1) le partage du billet du personnel doit contenir aussi « Statut : Payé », « Vendeur », « Mode de paiement » et le bas de billet, comme le billet client (ticket_document.dart et frontend/src/lib/ticket-print.ts) ; (2) tests : IFU fait d'espaces, TVA à zéro, print_info nul, aucun « XOF », écran de fin de vente ; (3) ne pas afficher « Prix TTC 0 FCFA » si price_excl_tax est présent sans price_incl_tax (tenir compte de la suppression de la TVA décidée par le boss). Ne retouche pas le commit existant.
- `cc/page-403` : pages réservées (admin, guichet, etc.) doivent afficher uniquement « 403 / Accès interdit » à un compte sans le rôle, sans aucun texte sur l'administration ou le personnel. Statut : à faire.

### 5. À FAIRE, PAR PRIORITÉ
A. Déployer les fusions sur le VPS, puis tester dans le navigateur.
B. Configuration admin (Eddy) : blocage siège à 5 min ; capacité du Yutong ; moyen de paiement « Espèces » ; « Agence et taxes » ; WhatsApp ; planning quotidien selon la grille boss.
C. Serveur : restore-test.sh ; webhook FedaPay vers https://api.axistransportlogistique.com/api/v1/client/webhooks/fedapay/ ; test de paiement sandbox ; vérifier l'accès à /django-admin/.
D. Comptes du personnel, scénario A (environ 2 jours) : champ « doit changer son mot de passe », route « changer mon mot de passe », réinitialisation et désactivation par l'admin, écrans site et app. Plan écrit à faire valider d'abord.
E. Masquer ou retirer le formulaire « Ajouter un tarif » par parcours (obsolète).
F. Plus tard : réservation multi-passagers et plan de sièges web fidèle au car ; vente par tronçon (étape 3) ; recompiler l'APK avec l'adresse de l'API.

---

## Tâche suivante pour Antigravity
1. Reprendre `ag/billet-personnel` et appliquer les 3 corrections demandées au point 4 (en tenant compte de la décision du boss de ne plus afficher de TVA) ;
2. Ensuite seulement, proposer un plan écrit (sans code) pour le scénario A des comptes du personnel, à faire relire par Claude Code avant d'écrire du code.
