# TP6 - RAPPORT DE SAUVEGARDE ET RESTAURATION

## Exercice 6.1 - Sauvegarde incrémentale
Une sauvegarde incrémentale ne sauvegarde que les données modifiées depuis la dernière sauvegarde (qu'elle soit complète ou incrémentale). Elle utilise un fichier d'index (.sn) pour suivre les modifications.

**Avantages:**
- Rapide (peu de données à sauvegarder)
- Économe en espace de stockage
- Faible impact sur les performances

**Inconvénients:**
- Restauration plus complexe (nécessite la dernière full + toutes les incrémentales)
- Risque de corruption en chaîne

## Exercice 6.2 - Planning de sauvegarde
**Planning adopté:**
- **Dimanche 2h00:** Sauvegarde complète (full)
- **Lundi-Samedi 2h00:** Sauvegarde incrémentale (incremental)
- **1er du mois 3h00:** Sauvegarde différentielle (differential)

**Justification des horaires:**
- 2h00: Heure de faible activité utilisateur
- Dimanche: Jour de maintenance traditionnel
- Différentielle mensuelle pour récupération rapide

## Exercice 6.3 - Contenus et volumes
| Service | Contenu | Volume estimé | Méthode |
|---------|---------|---------------|---------|
| Homes | /home/* | 10-50 GB | tar avec snapshots LVM |
| MySQL | Bases de données | 5-20 GB | mysqldump --single-transaction |
| LDAP | Annuaire utilisateurs | 1-5 GB | slapcat/ldapsearch |
| WordPress | Fichiers + DB | 2-10 GB | tar + mysqldump |

## Exercice 6.4 - Supports de sauvegarde
| Support | Avantages | Inconvénients |
|---------|-----------|---------------|
| Disque dur | Rapide, réinscriptible, capacité élevée | Mécanique, sensible aux chocs |
| SSD | Très rapide, pas de pièces mobiles | Coût élevé, durée de vie limitée |
| Bandes | Faible coût/Go, durable, portable | Lent, accès séquentiel |
| Cloud | Accès distant, redondance | Dépendance réseau, coût récurrent |

## Exercice 6.5 - Stockage des supports
1. **Localisation physique:** Stocker hors site (protection incendie/vol)
2. **Contrôle d'accès:** Restreindre l'accès physique et logique
3. **Conditions environnementales:** Température/humidité contrôlées
4. **Rotation:** Remplacer périodiquement les supports
5. **Test de restauration:** Vérifier régulièrement l'intégrité

## Exercice 6.8 - Critique du stockage sur disque
**Avantages:**
- Installation simple et rapide
- Performances élevées
- Coût modéré

**Inconvénients:**
- Pas de protection contre les sinistres locaux
- Vulnérable aux pannes matérielles
- Nécessite une réplication pour la redondance

**Recommandation:** Ajouter une copie sur bande ou cloud.

## Exercice 6.9 - Organisation des fichiers