# DECISIONS.md — décisions validées par la direction

Seules les décisions validées par le boss, transmises par Eddy, et déjà appliquées dans le dépôt. Aucune autre.
Ne rien ajouter sans décision transmise par Eddy.

| Décision | Date | Où dans le dépôt |
|---|---|---|
| **Grille de prix par tronçon** : ligne Parakou, Savè, Kétou, Porto-Novo, Cotonou ; un prix par paire d'arrêts, le même dans les deux sens ; le trajet complet se vend au prix de son tronçon. Grille validée par la direction. | 17/10/2026 (validation transmise) | `load_segment_fares.py`, DEPLOY.md section 2 ter |
| **Prix affiché = montant payé** : Axis envoie à FedaPay exactement le prix du billet ; aucun frais ajouté côté client. | 16/10/2026 | `payments.py` (`payment_quote`), migration `0012_client_fee_zero` |
| **Frais FedaPay supportés par l'agence.** | 16/10/2026 | DEPLOY.md section 2 quinquies (réglage FedaPay à vérifier) |
| **TVA 18 % incluse dans des prix TTC** : rien ne s'ajoute au prix affiché ; taux transmis, non vérifié pour le transport de voyageurs, donc modifiable par l'admin. | 17/10/2026 | migration `0013_agency_taxes`, `services.tax_breakdown` |
| **Rôles** : client, guichet, contrôleur, administrateur ; pas de rôle « boss » (le boss a un compte administrateur nominatif). | date inconnue (pas de rôle boss : 17/10/2026) | `models.User.Role`, `permissions.py` |
| **Paiement : Espèces au guichet, Mobile Money en ligne** (FedaPay). | date inconnue | `payments.py`, moyens de paiement configurés par l'admin |
| **Comptes du personnel créés par l'administrateur** ; l'inscription publique ne crée que des comptes clients. | date inconnue | `RegisterView`, portail `/admin` « Équipe & rôles » |
| **Heure du Bénin (UTC+1)** pour toutes les dates et heures. | date inconnue | `settings.TIME_ZONE = "Africa/Porto-Novo"` |
| **Le billet est un titre de transport**, pas une facture (pas de numéro de facture, NIM, code MeCeF/DGI ni QR DGI). | date inconnue | `serializers.ticket_print_info`, DEPLOY.md section 2 quinquies |
| **Pas de SMS automatique.** | date inconnue | aucun envoi de SMS dans le code |
