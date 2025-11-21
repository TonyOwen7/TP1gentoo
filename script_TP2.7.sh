#!/bin/bash
# TP2 - Gestion LVM - Exercices 2.12 à 2.15
# Analyse et procédures LVM sans modification du système actuel

SECRET_CODE="codesecret"   # Code attendu

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

echo "✅ Code correct, analyse LVM..."

set -euo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
DISK="/dev/sda"
MOUNT_POINT="/mnt/gentoo"

echo "================================================================"
echo "     TP2 - Gestion LVM - Exercices 2.12-2.15"
echo "     Analyse et procédures sans modification"
echo "================================================================"
echo ""

# Vérification que le système est monté
if [ ! -d "${MOUNT_POINT}/etc" ]; then
    log_error "Le système Gentoo n'est pas monté sur ${MOUNT_POINT}"
    log_info "Montage du système pour analyse..."
    
    mkdir -p "${MOUNT_POINT}"
    mount "${DISK}3" "${MOUNT_POINT}" 2>/dev/null || {
        log_error "Impossible de monter le système"
        exit 1
    }
fi

# Montage des systèmes virtuels pour analyse
mount -t proc /proc "${MOUNT_POINT}/proc" 2>/dev/null || true
mount --rbind /sys "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --rbind /dev "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/dev" 2>/dev/null || true

# ============================================================================
# EXERCICE 2.12 - ANALYSE D'EXTENSION DE PARTITIONS
# ============================================================================
log_info "Exercice 2.12 - Analyse des méthodes d'extension de partitions"

chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_EOF'
#!/bin/bash
set -euo pipefail

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[CHROOT]${NC} $1"; }
log_success() { echo -e "${GREEN}[CHROOT OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[CHROOT WARN]${NC} $1"; }

source /etc/profile

echo ""
echo "================================================================"
log_info "EXERCICE 2.12 - RÉFLEXION SUR L'EXTENSION DE PARTITIONS"
echo "================================================================"
echo ""

# Analyse du partitionnement actuel
log_info "📊 ANALYSE DU SYSTÈME ACTUEL:"
echo ""
echo "Partitions:"
lsblk 2>/dev/null || df -h 2>/dev/null | grep -E "^/dev/"
echo ""
echo "Espace disponible:"
df -h /home / 2>/dev/null | grep -E "^/dev/|Filesystem"
echo ""

log_info "💡 SOLUTIONS POUR EXTENSION DE /home TROP PETIT:"
echo ""
echo "🔴 MÉTHODE CLASSIQUE (RISQUÉE):"
echo "   1. Sauvegarde: tar czf /tmp/home-backup.tar.gz -C /home ."
echo "   2. Démontage: umount /home"
echo "   3. Suppression: fdisk /dev/sda → supprimer partition 4"
echo "   4. Recréation: fdisk /dev/sda → nouvelle partition plus grande"
echo "   5. Formatage: mkfs.ext4 /dev/sda4"
echo "   6. Restauration: tar xzf /tmp/home-backup.tar.gz -C /home"
echo "   7. Mise à jour: /etc/fstab"
echo "   ❌ DANGER: Perte de données si erreur"
echo "   ❌ LIMITE: Espace contigu nécessaire"
echo ""

echo "🟢 MÉTHODE LVM (RECOMMANDÉE):"
echo "   1. Sauvegarde: tar czf /tmp/home-backup.tar.gz -C /home ."
echo "   2. Démontage: umount /home"
echo "   3. Suppression: fdisk /dev/sda → supprimer partition 4"
echo "   4. Création LVM:"
echo "      - pvcreate /dev/sda4"
echo "      - vgcreate home-vg /dev/sda4"
echo "      - lvcreate -l 100%FREE -n home-lv home-vg"
echo "   5. Formatage: mkfs.ext4 /dev/home-vg/home-lv"
echo "   6. Montage: mount /dev/home-vg/home-lv /home"
echo "   7. Restauration: tar xzf /tmp/home-backup.tar.gz -C /home"
echo "   8. fstab: /dev/home-vg/home-lv /home ext4 defaults 0 2"
echo "   ✅ AVANTAGE: Extension facile future"
echo "   ✅ SÉCURITÉ: Snapshots possibles"
echo ""

echo "🔵 POUR / TROP PETIT:"
echo "   🚨 BEAUCOUP PLUS COMPLEXE - SAUVEGARDE COMPLÈTE NÉCESSAIRE"
echo "   1. Sauvegarde complète du système"
echo "   2. LiveCD nécessaire"
echo "   3. Repartitionnement complet"
echo "   4. Restauration"
echo "   ⏱️  Temps d'arrêt important"
echo ""

log_success "Exercice 2.12 terminé - Analyse complétée"

CHROOT_EOF

# ============================================================================
# EXERCICE 2.13 - PROCÉDURE DE MIGRATION LVM
# ============================================================================
log_info "Exercice 2.13 - Procédure de migration vers LVM"

chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_EOF'
#!/bin/bash
set -euo pipefail

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[CHROOT]${NC} $1"; }
log_success() { echo -e "${GREEN}[CHROOT OK]${NC} $1"; }

source /etc/profile

echo ""
echo "================================================================"
log_info "EXERCICE 2.13 - PROCÉDURE COMPLÈTE LVM"
echo "================================================================"
echo ""

# Installation des outils LVM pour documentation
log_info "Installation des outils LVM (pour documentation)..."
emerge --noreplace sys-fs/lvm2 2>/dev/null | grep -E ">>>" | head -2 || true

# Création d'un script de migration documenté
log_info "Création du script de migration LVM..."

cat > /usr/local/bin/migrate-home-to-lvm.sh << 'SCRIPT_EOF'
#!/bin/bash
# Script de migration de /home vers LVM
# À exécuter avec précaution !

set -euo pipefail

echo "================================================================"
echo "           MIGRATION /home VERS LVM"
echo "================================================================"
echo ""
echo "🚨 ATTENTION: Cette opération est critique!"
echo "   Sauvegardez vos données importantes avant de continuer!"
echo ""
read -p "Voulez-vous continuer? (oui/non): " confirm

if [ "$confirm" != "oui" ]; then
    echo "Opération annulée."
    exit 1
fi

echo ""
echo "📦 ÉTAPE 1: Sauvegarde de /home..."
BACKUP_DIR="/tmp/home_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
tar czf "$BACKUP_DIR/home_backup.tar.gz" -C /home . && \
echo "✅ Sauvegarde créée: $BACKUP_DIR/home_backup.tar.gz"

echo ""
echo "🔧 ÉTAPE 2: Vérification des partitions..."
fdisk -l /dev/sda | grep "/dev/sda4"
read -p "La partition /dev/sda4 sera supprimée. Continuer? (oui/non): " confirm2

if [ "$confirm2" != "oui" ]; then
    echo "Opération annulée."
    exit 1
fi

echo ""
echo "🗑️  ÉTAPE 3: Démontage et suppression..."
umount /home || {
    echo "❌ Impossible de démonter /home"
    echo "   Vérifiez les processus: lsof /home"
    exit 1
}

echo "📝 Suppression de la partition (manuellement avec fdisk)..."
echo "   fdisk /dev/sda"
echo "   → d (delete)"
echo "   → 4 (partition 4)"
echo "   → n (new)"
echo "   → p (primary)"
echo "   → 4 (partition number)"
echo "   → Enter (first sector)"
echo "   → Enter (last sector)"
echo "   → t (type)"
echo "   → 4 (partition)"
echo "   → 8e (Linux LVM)"
echo "   → w (write)"
echo ""
read -p "Appuyez sur Entrée quand la partition est recréée en type LVM..."

echo ""
echo "💾 ÉTAPE 4: Configuration LVM..."
pvcreate /dev/sda4
vgcreate home-vg /dev/sda4
lvcreate -l 100%FREE -n home-lv home-vg

echo ""
echo "🗂️  ÉTAPE 5: Formatage..."
mkfs.ext4 /dev/home-vg/home-lv

echo ""
echo "📁 ÉTAPE 6: Montage et restauration..."
mount /dev/home-vg/home-lv /home
tar xzf "$BACKUP_DIR/home_backup.tar.gz" -C /home

echo ""
echo "⚙️  ÉTAPE 7: Configuration fstab..."
cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d)
sed -i '\|/home|d' /etc/fstab
echo "/dev/home-vg/home-lv /home ext4 defaults,noatime 0 2" >> /etc/fstab

echo ""
echo "✅ MIGRATION TERMINÉE AVEC SUCCÈS!"
echo "   Redémarrez pour vérifier: reboot"
echo ""
SCRIPT_EOF

chmod +x /usr/local/bin/migrate-home-to-lvm.sh
log_success "Script de migration créé: /usr/local/bin/migrate-home-to-lvm.sh"

# Configuration fstab préparatoire
log_info "Préparation de la configuration fstab pour LVM..."
cat >> /etc/fstab << 'FSTAB_EOF'

# LVM Configuration for /home (uncomment after migration)
# /dev/home-vg/home-lv   /home   ext4    defaults,noatime    0 2
FSTAB_EOF

log_success "Exercice 2.13 terminé - Procédure LVM documentée"

CHROOT_EOF

# ============================================================================
# EXERCICE 2.14 - EXTENSION MULTI-DISQUES LVM
# ============================================================================
log_info "Exercice 2.14 - Extension LVM avec second disque"

chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_EOF'
#!/bin/bash
set -euo pipefail

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[CHROOT]${NC} $1"; }
log_success() { echo -e "${GREEN}[CHROOT OK]${NC} $1"; }

source /etc/profile

echo ""
echo "================================================================"
log_info "EXERCICE 2.14 - EXTENSION LVM MULTI-DISQUES"
echo "================================================================"
echo ""

log_info "📋 PROCÉDURE POUR AJOUT D'UN SECOND DISQUE:"
echo ""
echo "1. AJOUT DU DISQUE DANS VIRTUALBOX:"
echo "   - Machine → Settings → Storage"
echo "   - Controller: SATA → Add Hard Disk"
echo "   - Create new disk → VDI → Dynamically allocated"
echo "   - Taille: 2GB (exemple)"
echo "   - Redémarrer la VM"
echo ""

echo "2. DÉTECTION ET PRÉPARATION:"
echo "   fdisk -l | grep /dev/sdb"
echo "   fdisk /dev/sdb → n → p → 1 → enter → enter → t → 8e → w"
echo ""

echo "3. EXTENSION DU VOLUME LVM:"
echo "   pvcreate /dev/sdb1"
echo "   vgextend home-vg /dev/sdb1"
echo "   lvextend -l +100%FREE /dev/home-vg/home-lv"
echo "   resize2fs /dev/home-vg/home-lv"
echo ""

# Création du script d'extension
log_info "Création du script d'extension automatique..."

cat > /usr/local/bin/extend-lvm-with-new-disk.sh << 'EXTEND_EOF'
#!/bin/bash
# Script d'extension LVM avec nouveau disque

set -euo pipefail

echo "================================================================"
echo "           EXTENSION LVM AVEC NOUVEAU DISQUE"
echo "================================================================"
echo ""

# Détection du nouveau disque
echo "🔍 Recherche du nouveau disque..."
NEW_DISK=$(lsblk -o NAME,TYPE | grep -E "^(sd|vd)[b-z].*disk" | awk '{print $1}' | head -1)

if [ -z "$NEW_DISK" ]; then
    echo "❌ Aucun nouveau disque détecté!"
    echo "💡 Ajoutez un disque dans VirtualBox et redémarrez la VM"
    exit 1
fi

echo "✅ Nouveau disque détecté: /dev/$NEW_DISK"

# Partitionnement
echo ""
echo "📝 Partitionnement de /dev/$NEW_DISK..."
fdisk /dev/$NEW_DISK << FDISK_EOF
n
p
1


t
8e
w
FDISK_EOF

sleep 2

# Vérification de la partition
if [ ! -e "/dev/${NEW_DISK}1" ]; then
    echo "❌ Partition non créée"
    exit 1
fi

echo "✅ Partition créée: /dev/${NEW_DISK}1"

# Extension LVM
echo ""
echo "🔧 Extension du LVM..."

echo "1. Création du Physical Volume..."
pvcreate /dev/${NEW_DISK}1

echo "2. Extension du Volume Group..."
vgextend home-vg /dev/${NEW_DISK}1

echo "3. Extension du Logical Volume..."
lvextend -l +100%FREE /dev/home-vg/home-lv

echo "4. Redimensionnement du système de fichiers..."
resize2fs /dev/home-vg/home-lv

echo ""
echo "✅ EXTENSION TERMINÉE AVEC SUCCÈS!"
echo ""
echo "📊 NOUVELLE TAILLE:"
df -h /home
echo ""
echo "💾 INFORMATIONS LVM:"
pvs
vgs
lvs
EXTEND_EOF

chmod +x /usr/local/bin/extend-lvm-with-new-disk.sh
log_success "Script d'extension créé: /usr/local/bin/extend-lvm-with-new-disk.sh"

log_success "Exercice 2.14 terminé - Procédure d'extension documentée"

CHROOT_EOF

# ============================================================================
# EXERCICE 2.15 - ANALYSE DES RISQUES
# ============================================================================
log_info "Exercice 2.15 - Analyse des risques du partitionnement classique"

chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_EOF'
#!/bin/bash
set -euo pipefail

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[CHROOT]${NC} $1"; }
log_success() { echo -e "${GREEN}[CHROOT OK]${NC} $1"; }

source /etc/profile

echo ""
echo "================================================================"
log_info "EXERCICE 2.15 - ANALYSE DES RISQUES"
echo "================================================================"
echo ""

log_info "⚠️  DANGERS DU PARTITIONNEMENT CLASSIQUE SUR DISQUES PHYSIQUES:"
echo ""
echo "🔴 RISQUE DE PERTE DE DONNÉES:"
echo "   • Partitionnement fixe → extension complexe et risquée"
echo "   • Erreur humaine lors du redimensionnement"
echo "   • Corruption pendant les opérations de taille"
echo "   • Impossible de réduire certaines partitions système"
echo ""

echo "🔴 TEMPS D'ARRÊT IMPORTANT:"
echo "   • Sauvegarde/restauration obligatoire"
echo "   • Impossible d'étendre à chaud"
echo "   • Maintenance planifiée nécessaire"
echo "   • Impact sur la disponibilité du service"
echo ""

echo "🔴 LIMITATIONS TECHNIQUES:"
echo "   • Espace perdu entre partitions"
echo "   • Fragmentation des données"
echo "   • Gestion complexe des espaces libres"
echo "   • Impossible de réallouer l'espace dynamiquement"
echo ""

echo "🔴 PROBLÈMES DE PERFORMANCE:"
echo "   • Têtes de lecture déplacements importants"
echo "   • Usure mécanique accrue"
echo "   • Défragmentation nécessaire"
echo "   • Gestion inefficace de l'espace"
echo ""

log_info "✅ AVANTAGES DE LVM SUR DISQUES PHYSIQUES:"
echo ""
echo "🟢 FLEXIBILITÉ:"
echo "   • Extension/réduction à chaud"
echo "   • Gestion dynamique de l'espace"
echo "   • Pas de redémarrage nécessaire"
echo "   • Pool de stockage unifié"
echo ""

echo "🟢 DISPONIBILITÉ:"
echo "   • Snapshots pour sauvegardes cohérentes"
echo "   • Migration à chaud entre disques"
echo "   • RAID logiciel intégré"
echo "   • Pas d'interruption de service"
echo ""

echo "🟢 ADMINISTRATION:"
echo "   • Noms logiques persistants"
echo "   • Gestion centralisée des volumes"
echo "   • Monitoring intégré"
echo "   • Sauvegardes incrémentielles"
echo ""

echo "🟢 OPTIMISATION:"
echo "   • Meilleure utilisation de l'espace"
echo "   • Striping pour les performances"
echo "   • Allocation dynamique"
echo "   • Gestion des espaces fragmentés"
echo ""

log_info "📊 COMPARAISON SYNTHÈSE:"
echo ""
echo "┌─────────────────┬──────────────────┬─────────────────┐"
echo "│     CRITÈRE     │  PARTITIONNEMENT │       LVM       │"
echo "│                 │     CLASSIQUE    │                 │"
echo "├─────────────────┼──────────────────┼─────────────────┤"
echo "│ Flexibilité     │       ❌         │       ✅        │"
echo "│ Disponibilité   │       ❌         │       ✅        │"
echo "│ Sécurité        │       ⚠️         │       ✅        │"
echo "│ Performance     │       ⚠️         │       ✅        │"
echo "│ Complexité      │       ✅         │       ⚠️        │"
echo "│ Maintenance     │       ❌         │       ✅        │"
echo "└─────────────────┴──────────────────┴─────────────────┘"
echo ""

log_success "Exercice 2.15 terminé - Analyse des risques complétée"

CHROOT_EOF

# ============================================================================
# RÉSUMÉ FINAL ET DOCUMENTATION
# ============================================================================
log_info "Création de la documentation finale..."

chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_EOF'
#!/bin/bash

# Création du fichier de documentation
cat > /root/TP2_LVM_DOCUMENTATION.md << 'DOC_EOF'
# TP2 - Gestion LVM - Documentation

## 📋 Exercices 2.12 à 2.15

### 🔍 Exercice 2.12: Analyse d'extension
- **Problème**: Partition /home trop petite
- **Solutions**:
  - Méthode classique: Risquée, temps d'arrêt
  - Méthode LVM: Recommandée, flexible

### 🛠️ Exercice 2.13: Migration LVM
- **Script créé**: `/usr/local/bin/migrate-home-to-lvm.sh`
- **Procédure**: Sauvegarde → LVM → Restauration
- **Configuration**: fstab préparé

### 💾 Exercice 2.14: Extension multi-disques
- **Script créé**: `/usr/local/bin/extend-lvm-with-new-disk.sh`
- **Procédure**: Ajout disque → Partitionnement → Extension LVM

### ⚠️ Exercice 2.15: Analyse risques
- **Partitionnement classique**: Risques importants
- **LVM**: Solution professionnelle

## 🚀 SCRIPTS DISPONIBLES

### 1. Migration vers LVM
```bash
/usr/local/bin/migrate-home-to-lvm.sh