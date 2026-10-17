# TASKS.md — tâches en cours

Une ligne par tâche. Mettre à jour en début et en fin de tâche. Un seul outil par branche à la fois.
Statuts : à faire · en cours · à valider par Eddy · terminée.

| Tâche | Branche | Outil | Statut |
|---|---|---|---|
| IFU de l'acheteur et lignes HT / TVA dans le partage de l'app du personnel | `ag/billet-personnel` | Antigravity | à valider par Eddy |
| Bouton « Vérifier mon paiement », rattrapage automatique en local, vérification patiente | `confirmation-paiement` | Claude Code | à valider par Eddy (non fusionnée, 3 conflits à résoudre) |

## Tâche `ag/billet-personnel` (Antigravity)

**But** : ajouter l'IFU de l'acheteur et les lignes HT / TVA du billet dans le partage de l'app du personnel. Le serveur fournit déjà les données : champ `print_info` de chaque billet (`buyer_ifu`, `price_excl_tax`, `tax_lines`, `price_incl_tax`, `paid`, `sale`, `payment_mode`, `agency`).

**Fichiers concernés** (`mobile-flutter/`) :
- `lib/features/sales/sale_models.dart` : `SaleTicket` (lecture de `print_info`) et `saleShareText` (texte partagé) ;
- `lib/features/sales/sell_ticket_screen.dart` : affichage après la vente, si nécessaire ;
- à lire pour reprendre les mêmes règles : `lib/core/models.dart` (`TicketPrintInfo`) et `lib/features/tickets/ticket_document.dart` (`ticketFields`, `ticketFooter`) ;
- tests : `test/sale_controller_test.dart` et un test du texte partagé.

**Règles d'affichage** (identiques au billet client) : montants en « FCFA » ; IFU de l'acheteur seulement s'il est rempli ; lignes Prix HT / TVA / Prix TTC seulement si `price_excl_tax` n'est pas nul (le serveur ne l'envoie que si l'IFU de l'agence est renseigné) ; aucune donnée inventée ; jamais de comptes bancaires.

**Tests à lancer** : `cd mobile-flutter && flutter test && flutter analyze` ; si un fichier serveur est touché, la suite serveur d'`AGENTS.md`.

**Interdit dans cette tâche** : paiements, webhook, sécurité, permissions, migrations, fichiers `.env`, compilation d'APK, push.
