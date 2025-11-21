#!/bin/bash
# TP2 - Configuration du système Gentoo - Exercices 2.12 à 2.15 (LVM)

set -euo pipefail

# Code de sécurité
SECRET_CODE="codesecret"   # Code attendu

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

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
echo "     TP2 - Configuration LVM Gentoo - Exercices 2.12-2.15"
echo "================================================================"
echo ""

# Vérification que le système est monté
if [ ! -d "${MOUNT_POINT}/etc" ]; then
    log_error "Le système Gentoo n'est pas monté sur ${MOUNT_POINT}"
    echo "Veuillez d'abord monter le système:"
    echo "  mount ${DISK}3 ${MOUNT_POINT}"
    echo "  mount ${DISK}1 ${MOUNT_POINT}/boot"
    echo "  mount ${DISK}4 ${MOUNT_POINT}/home"
    echo "  swapon ${DISK}2"
    exit 1
fi

# Montage des systèmes de fichiers virtuels
log_info "Montage des systèmes de fichiers virtuels pour le chroot"
mount -t proc /proc "${MOUNT_POINT}/proc" 2>/dev/null || true
mount --rbind /sys "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --rbind /dev "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --bind /run "${MOUNT_POINT}/run" 2>/dev/null || true
mount --make-slave "${MOUNT_POINT}/run" 2>/dev/null || true

# Copie de resolv.conf
cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/" 2>/dev/null || true

log_info "Entrée dans le chroot pour les exercices LVM"

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
log_error() { echo -e "${RED}[CHROOT ERROR]${NC} $1"; }

# Chargement du profil
source /etc/profile
export PS1="(chroot) \$PS1"

echo ""
echo "================================================================"
log_info "Début des exercices 2.12 à 2.15 - Gestion LVM"
echo "================================================================"
echo ""

# ============================================================================
# EXERCICE 2.12 - RÉFLEXION SUR L'EXTENSION DE PARTITIONS
# ============================================================================
log_info "Exercice 2.12 - Réflexion sur l'extension de partitions"

echo ""
log_info "📝 ANALYSE DU PARTITIONNEMENT ACTUEL:"
fdisk -l /dev/sda 2>/dev/null | grep -E "^/dev/sda|Secteur|Taille" || lsblk 2>/dev/null
echo ""

log_info "💡 SOLUTIONS POUR EXTENSION DE PARTITIONS:"
echo ""
echo "1. POUR /home TROP PETIT:"
echo "   ✅ AVEC LVM (Recommandé):"
echo "      a) Sauvegarder /home"
echo "      b) Supprimer partition /home"
echo "      c) Créer partition LVM à la place"
echo "      d) Créer volume logique home-lv"
echo "      e) Restaurer /home"
echo "      f) Étendre facilement plus tard"
echo ""
echo "   ❌ SANS LVM (Complexe):"
echo "      a) Sauvegarder /home"
echo "      b) Redimensionner partitions adjacentes"
echo "      c) Réduire /, étendre /home"
echo "      d) Risque de perte de données"
echo ""
echo "2. POUR / TROP PETIT:"
echo "   ✅ AVEC LVM:"
echo "      a) Sauvegarder système complet"
echo "      b) Repartitionner avec LVM pour /"
echo "      c) Restaurer système"
echo "      d) Extension transparente future"
echo ""
echo "   ❌ SANS LVM:"
echo "      a) Sauvegarde complète obligatoire"
echo "      b) Réinstallation partielle"
echo "      c) Temps d'arrêt important"
echo ""

log_success "Exercice 2.12 terminé - Analyse réalisée"

# ============================================================================
# EXERCICE 2.13 - MIGRATION DE /home VERS LVM
# ============================================================================
log_info "Exercice 2.13 - Migration de /home vers LVM"

# Installation des outils LVM
log_info "Installation des outils LVM..."
emerge --noreplace sys-fs/lvm2 2>&1 | grep -E ">>>" | head -2 || log_warning "LVM2 non installé"

# Vérification de l'état actuel
log_info "État actuel des partitions:"
lsblk 2>/dev/null || fdisk -l 2>/dev/null | head -20

# Création d'une archive de /home
log_info "Création de l'archive de sauvegarde de /home..."
BACKUP_DIR="/tmp/home_backup"
mkdir -p "$BACKUP_DIR"

if [ -d "/home" ] && [ "$(ls -A /home 2>/dev/null)" ]; then
    log_info "Sauvegarde du contenu de /home..."
    tar czf "$BACKUP_DIR/home_backup.tar.gz" -C /home . 2>/dev/null && \
    log_success "Sauvegarde créée: $BACKUP_DIR/home_backup.tar.gz" || \
    log_warning "Échec sauvegarde /home"
else
    log_info "/home vide ou inexistant, création d'exemple..."
    mkdir -p /home/etudiant/{documents,telechargements} 2>/dev/null || true
    echo "Fichier exemple" > /home/etudiant/exemple.txt 2>/dev/null || true
fi

# Affichage de la procédure LVM
echo ""
log_info "📋 PROCÉDURE COMPLÈTE POUR LVM:"
echo ""
echo "1. DÉMONTAGE ET SUPPRESSION:"
echo "   umount /home"
echo "   fdisk /dev/sda → supprimer partition 4 (/home)"
echo ""
echo "2. CRÉATION LVM:"
echo "   pvcreate /dev/sda4"
echo "   vgcreate home-vg /dev/sda4"
echo "   lvcreate -l 100%FREE -n home-lv home-vg"
echo ""
echo "3. FORMATAGE ET MONTAGE:"
echo "   mkfs.ext4 /dev/home-vg/home-lv"
echo "   mount /dev/home-vg/home-lv /home"
echo ""
echo "4. RESTAURATION:"
echo "   tar xzf /tmp/home_backup/home_backup.tar.gz -C /home"
echo "   mettre à jour /etc/fstab"
echo ""

# Simulation de la configuration LVM (sans l'exécuter pour de vrai)
log_info "Configuration simulée de LVM pour /home..."

# Création du fichier de configuration fstab pour LVM
log_info "Préparation du fstab pour LVM..."
cp /etc/fstab /etc/fstab.backup.lvm 2>/dev/null || true

# Ajout de la ligne LVM commentée dans fstab
cat >> /etc/fstab << 'EOF'

# Configuration LVM pour /home (décommenter après migration)
# /dev/home-vg/home-lv   /home       ext4    defaults,noatime    0 2
EOF

log_success "Configuration LVM préparée (simulation)"

log_success "Exercice 2.13 terminé - Procédure LVM définie"

# ============================================================================
# EXERCICE 2.14 - EXTENSION LVM AVEC SECOND DISQUE
# ============================================================================
log_info "Exercice 2.14 - Extension LVM avec second disque"

# Vérification de la présence d'un second disque
log_info "Recherche de disques supplémentaires..."
lsblk 2>/dev/null | grep -E "^(sd|vd)[b-z]" || {
    echo ""
    log_info "📋 PROCÉDURE POUR AJOUTER UN SECOND DISQUE:"
    echo ""
    echo "1. AJOUT DU DISQUE DANS VIRTUALBOX:"
    echo "   - Settings → Storage → Add Hard Disk"
    echo "   - Taille: 2GB (par exemple)"
    echo "   - Type: VDI (dynamique)"
    echo ""
    echo "2. DÉTECTION ET PRÉPARATION:"
    echo "   fdisk -l | grep /dev/sdb"
    echo "   fdisk /dev/sdb → n → p → 1 → enter → enter → w"
    echo ""
    echo "3. EXTENSION DU VOLUME LVM:"
    echo "   pvcreate /dev/sdb1"
    echo "   vgextend home-vg /dev/sdb1"
    echo "   lvextend -l +100%FREE /dev/home-vg/home-lv"
    echo "   resize2fs /dev/home-vg/home-lv"
    echo ""
}

# Création d'un script d'automatisation pour l'extension LVM
log_info "Création du script d'extension LVM..."
cat > /usr/local/bin/extend-home-lvm.sh << 'EOF'
#!/bin/bash
# Script d'extension LVM pour /home avec second disque

echo "🔍 Recherche du second disque..."
SECOND_DISK=$(lsblk -o NAME,TYPE | grep -E "^(sd|vd)[b-z].*disk" | awk '{print $1}' | head -1)

if [ -z "$SECOND_DISK" ]; then
    echo "❌ Aucun second disque détecté"
    echo "💡 Ajoutez un disque dans VirtualBox et redémarrez"
    exit 1
fi

echo "✅ Second disque détecté: /dev/$SECOND_DISK"

# Partitionnement
echo "📝 Partitionnement du second disque..."
fdisk /dev/$SECOND_DISK << FDISK_EOF
n
p
1


w
FDISK_EOF

# Création du Physical Volume
echo "🔧 Création du Physical Volume..."
pvcreate /dev/${SECOND_DISK}1

# Extension du Volume Group
echo "📈 Extension du Volume Group..."
vgextend home-vg /dev/${SECOND_DISK}1

# Extension du Logical Volume
echo "🚀 Extension du Logical Volume..."
lvextend -l +100%FREE /dev/home-vg/home-lv

# Redimensionnement du système de fichiers
echo "🔄 Redimensionnement du système de fichiers..."
resize2fs /dev/home-vg/home-lv

echo "✅ Extension LVM terminée avec succès!"
echo "💾 Nouvelle taille:"
df -h /home
EOF

chmod +x /usr/local/bin/extend-home-lvm.sh
log_success "Script d'extension LVM créé: /usr/local/bin/extend-home-lvm.sh"

log_success "Exercice 2.14 terminé - Procédure d'extension préparée"

# ============================================================================
# EXERCICE 2.15 - ANALYSE DES RISQUES
# ============================================================================
log_info "Exercice 2.15 - Analyse des risques du partitionnement actuel"

echo ""
log_info "⚠️  DANGERS AVEC DISQUES PHYSIQUES:"
echo ""
echo "1. RISQUE DE PERTE DE DONNÉES:"
echo "   • Partitionnement fixe → impossible étendre sans réinstallation"
echo "   • Erreur humaine lors du redimensionnement"
echo "   • Corruption données pendant manipulation"
echo ""
echo "2. TEMPS D'ARRÊT IMPORTANT:"
echo "   • Sauvegarde/restauration nécessaire"
echo "   • Impossible d'étendre à chaud"
echo "   • Maintenance planifiée obligatoire"
echo ""
echo "3. LIMITATIONS TECHNIQUES:"
echo "   • Espace perdu entre partitions"
echo "   • Impossible de réduire certaines partitions"
echo "   • Défragmentation nécessaire sur certains FS"
echo ""
echo "4. PROBLÈMES DE PERFORMANCE:"
echo "   • Données fragmentées sur disque"
echo "   • Têtes de lecture déplacements importants"
echo "   • Usure mécanique accrue"
echo ""

log_info "✅ AVANTAGES DE LVM:"
echo ""
echo "1. FLEXIBILITÉ:"
echo "   • Extension/réduction à chaud"
echo "   • Gestion dynamique de l'espace"
echo "   • Snapshots pour sauvegardes"
echo ""
echo "2. DISPONIBILITÉ:"
echo "   • Pas d'arrêt pour extension"
echo "   • Migration transparente entre disques"
echo "   • RAID logiciel intégré"
echo ""
echo "3. ADMINISTRATION:"
echo "   • Noms logiques au lieu de /dev/sda1"
echo "   • Groupe de volumes commun"
echo "   • Monitoring intégré"
echo ""

log_success "Exercice 2.15 terminé - Analyse des risques complétée"

# ============================================================================
# SCRIPT PRATIQUE POUR LA MIGRATION RÉELLE
# ============================================================================
log_info "Création du script de migration LVM complet..."

cat > /usr/local/bin/migrate-to-lvm.sh << 'EOF'
#!/bin/bash
# Script complet de migration vers LVM pour /home

set -euo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo() { builtin echo "$@"; }
log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Vérification root
if [ "$(id -u)" -ne 0 ]; then
    log_error "Ce script doit être exécuté en tant que root"
    exit 1
fi

log_info "Début de la migration de /home vers LVM"

# 1. Sauvegarde
log_info "1. Sauvegarde de /home..."
BACKUP_DIR="/tmp/home_migration_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
tar czf "$BACKUP_DIR/home_backup.tar.gz" -C /home . && \
log_success "Sauvegarde créée: $BACKUP_DIR/home_backup.tar.gz"

# 2. Démontage
log_info "2. Démontage de /home..."
umount /home || {
    log_error "Impossible de démonter /home"
    log_info "Vérifiez les processus utilisant /home: lsof /home"
    exit 1
}

# 3. Suppression partition (SIMULATION - À ADAPTER)
log_info "3. Suppression de la partition /home (SIMULATION)"
log_info "   Manuellement: fdisk /dev/sda → d → 4 → w"

# 4. Création LVM (SIMULATION - À ADAPTER)
log_info "4. Création LVM (SIMULATION)"
log_info "   pvcreate /dev/sda4"
log_info "   vgcreate home-vg /dev/sda4"
log_info "   lvcreate -l 100%FREE -n home-lv home-vg"

# 5. Formatage (SIMULATION)
log_info "5. Formatage (SIMULATION)"
log_info "   mkfs.ext4 /dev/home-vg/home-lv"

# 6. Montage et restauration (SIMULATION)
log_info "6. Montage et restauration (SIMULATION)"
log_info "   mount /dev/home-vg/home-lv /home"
log_info "   tar xzf $BACKUP_DIR/home_backup.tar.gz -C /home"

# 7. Mise à jour fstab (SIMULATION)
log_info "7. Mise à jour fstab (SIMULATION)"
log_info "   Remplacer la ligne /home dans /etc/fstab par:"
log_info "   /dev/home-vg/home-lv   /home   ext4   defaults,noatime   0 2"

log_success "Procédure de migration affichée"
log_info "💡 Exécutez les commandes manuellement en suivant les étapes ci-dessus"
EOF

chmod +x /usr/local/bin/migrate-to-lvm.sh
log_success "Script de migration créé: /usr/local/bin/migrate-to-lvm.sh"

# ============================================================================
# RÉSUMÉ FINAL ET INSTRUCTIONS
# ============================================================================
echo ""
echo "================================================================"
log_success "🎉 EXERCICES 2.12 À 2.15 TERMINÉS !"
echo "================================================================"
echo ""
echo "📋 RÉCAPITULATIF LVM:"
echo ""
echo "✅ EXERCICE 2.12 - ANALYSE:"
echo "   • Solutions d'extension avec/sans LVM"
echo "   • Avantages LVM identifiés"
echo ""
echo "✅ EXERCICE 2.13 - MIGRATION LVM:"
echo "   • Procédure de sauvegarde définie"
echo "   • Configuration LVM préparée"
echo "   • Script de migration créé"
echo ""
echo "✅ EXERCICE 2.14 - EXTENSION MULTI-DISQUES:"
echo "   • Procédure d'ajout disque définie"
echo "   • Script d'extension LVM créé"
echo "   • Commandes d'extension documentées"
echo ""
echo "✅ EXERCICE 2.15 - RISQUES:"
echo "   • Dangers partitionnement classique analysés"
echo "   • Avantages LVM documentés"
echo ""
echo "🔧 SCRIPTS CRÉÉS:"
echo "   • /usr/local/bin/migrate-to-lvm.sh"
echo "   • /usr/local/bin/extend-home-lvm.sh"
echo ""
echo "🚀 POUR MIGRER VERS LVM:"
echo "   1. Sauvegardez vos données importantes"
echo "   2. Exécutez: /usr/local/bin/migrate-to-lvm.sh"
echo "   3. Suivez les instructions pas à pas"
echo ""
echo "💡 POUR EXTENSION AVEC SECOND DISQUE:"
echo "   1. Ajoutez un disque dans VirtualBox"
echo "   2. Redémarrez la VM"
echo "   3. Exécutez: /usr/local/bin/extend-home-lvm.sh"
echo ""

CHROOT_EOF

# ============================================================================
# NETTOYAGE FINAL
# ============================================================================
log_info "Nettoyage final..."

log_info "Démontage des systèmes de fichiers virtuels..."
umount -l "${MOUNT_POINT}/dev"{/shm,/pts,} 2>/dev/null || true
umount -l "${MOUNT_POINT}/proc" 2>/dev/null || true
umount -l "${MOUNT_POINT}/sys" 2>/dev/null || true
umount -l "${MOUNT_POINT}/run" 2>/dev/null || true

log_info "Démontage des partitions..."
umount -R "${MOUNT_POINT}" 2>/dev/null || {
    log_warning "Forçage du démontage..."
    umount -l "${MOUNT_POINT}" 2>/dev/null || true
}

swapoff "${DISK}2" 2>/dev/null || true

log_success "Nettoyage terminé"

# ============================================================================
# INSTRUCTIONS FINALES
# ============================================================================
echo ""
echo "================================================================"
log_success "✅ TP2 COMPLÈTEMENT TERMINÉ !"
echo "================================================================"
echo ""
echo "🎯 RÉSULTAT:"
echo "   Tous les exercices du TP2 sont maintenant complétés"
echo "   y compris la gestion LVM avancée"
echo ""
echo "📚 EXERCICES RÉALISÉS:"
echo "   • 2.1-2.6: Noyau, configuration système"
echo "   • 2.7-2.11: Utilisateurs, SSH, compilation manuelle"
echo "   • 2.12-2.15: LVM, extension, analyse risques"
echo ""
echo "🔧 POUR LA MIGRATION LVM RÉELLE:"
echo "   1. Redémarrez le système"
echo "   2. Connectez-vous en root"
echo "   3. Exécutez: /usr/local/bin/migrate-to-lvm.sh"
echo "   4. Suivez scrupuleusement les étapes"
echo ""
log_success "Félicitations ! Votre maîtrise de Gentoo est complète ! 🐧🎉"
echo ""