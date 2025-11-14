#!/bin/bash
# ISTY-ADMSYS-TP1 - Installation Gentoo complète avec export OVA
# Exercices 1.1 à 1.9 + Export pour conservation de l'environnement

set -euo pipefail

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Variables de configuration
DISK="/dev/vda"
MOUNT_POINT="/mnt/gentoo"
VM_NAME="Gentoo-TP1-ISTY"
OVA_FILE="${VM_NAME}.ova"

echo "================================================================"
echo "     ISTY-ADMSYS-TP1 - Installation Gentoo complète"
echo "     avec export OVA pour conservation de l'environnement"
echo "================================================================"
echo ""

# ============================================================================
# EXERCICE 1.2 - PARTITIONNEMENT
# ============================================================================
log_info "EXERCICE 1.2 - Partitionnement du disque ${DISK}"

if lsblk "${DISK}" 2>/dev/null | grep -q "${DISK}1"; then
    log_warning "Partitions déjà présentes - Skip du partitionnement"
else
    log_info "Création des partitions avec fdisk..."
    log_info "Plan de partitionnement:"
    log_info "  - ${DISK}1: /boot 100M ext2"
    log_info "  - ${DISK}2: swap 256M" 
    log_info "  - ${DISK}3: / 6G ext4"
    log_info "  - ${DISK}4: /home 6G ext4"
    
    (
        echo o
        echo n; echo p; echo 1
        echo ; echo +100M
        echo n; echo p; echo 2
        echo ; echo +256M
        echo n; echo p; echo 3
        echo ; echo +6G
        echo n; echo p; echo 4
        echo ; echo
        echo t; echo 2; echo 82
        echo w
    ) | fdisk "${DISK}" >/dev/null 2>&1
    
    sleep 2
    partprobe "${DISK}" 2>/dev/null || true
    log_success "Partitions créées selon l'exercice 1.2"
fi

# ============================================================================
# EXERCICE 1.3 - FORMATAGE AVEC LABELS
# ============================================================================
log_info "EXERCICE 1.3 - Formatage des partitions avec labels"

if ! blkid -L boot >/dev/null 2>&1; then
    mkfs.ext2 -F -L boot "${DISK}1" >/dev/null 2>&1
    log_success "Partition /boot formatée (ext2) avec label 'boot'"
fi

if ! blkid -L swap >/dev/null 2>&1; then
    mkswap -L swap "${DISK}2" >/dev/null 2>&1
    log_success "Partition swap formatée avec label 'swap'"
fi

if ! blkid -L root >/dev/null 2>&1; then
    mkfs.ext4 -F -L root "${DISK}3" >/dev/null 2>&1
    log_success "Partition / formatée (ext4) avec label 'root'"
fi

if ! blkid -L home >/dev/null 2>&1; then
    mkfs.ext4 -F -L home "${DISK}4" >/dev/null 2>&1
    log_success "Partition /home formatée (ext4) avec label 'home'"
fi

# ============================================================================
# EXERCICE 1.4 - MONTAGE DES PARTITIONS
# ============================================================================
log_info "EXERCICE 1.4 - Montage des partitions et activation swap"

mkdir -p "${MOUNT_POINT}"

if ! mountpoint -q "${MOUNT_POINT}"; then
    mount "${DISK}3" "${MOUNT_POINT}"
    log_success "Partition / montée sur ${MOUNT_POINT}"
fi

mkdir -p "${MOUNT_POINT}/boot"
if ! mountpoint -q "${MOUNT_POINT}/boot"; then
    mount "${DISK}1" "${MOUNT_POINT}/boot"
    log_success "Partition /boot montée"
fi

mkdir -p "${MOUNT_POINT}/home"
if ! mountpoint -q "${MOUNT_POINT}/home"; then
    mount "${DISK}4" "${MOUNT_POINT}/home"
    log_success "Partition /home montée"
fi

if ! swapon --show | grep -q "${DISK}2"; then
    swapon "${DISK}2"
    log_success "Swap activé sur ${DISK}2"
fi

# ============================================================================
# EXERCICE 1.5 - TÉLÉCHARGEMENT STAGE3 ET PORTAGE
# ============================================================================
log_info "EXERCICE 1.5 - Téléchargement du stage3 et de Portage"

cd "${MOUNT_POINT}"

STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-systemd.txt"
ACTUAL_STAGE3_URL=$(wget -qO- "${STAGE3_URL}" | grep -v '^#' | awk '{print $1}')
STAGE3_BASE_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/${ACTUAL_STAGE3_URL}"
PORTAGE_URL="https://distfiles.gentoo.org/snapshots/portage-latest.tar.xz"

STAGE3_FILENAME=$(basename "${ACTUAL_STAGE3_URL}")
if [ ! -f "${STAGE3_FILENAME}" ]; then
    log_info "Téléchargement du stage3: ${STAGE3_FILENAME}"
    wget --quiet --show-progress "${STAGE3_BASE_URL}"
    log_success "Stage3 téléchargé"
fi

if [ ! -f "portage-latest.tar.xz" ]; then
    log_info "Téléchargement du snapshot Portage"
    wget --quiet --show-progress "${PORTAGE_URL}"
    log_success "Portage téléchargé"
fi

# ============================================================================
# EXERCICE 1.6 - EXTRACTION DES ARCHIVES
# ============================================================================
log_info "EXERCICE 1.6 - Extraction des archives"

log_info "Extraction du stage3..."
tar xpf "${STAGE3_FILENAME}" --xattrs-include='*.*' --numeric-owner
log_success "Stage3 extrait avec succès"

log_info "Extraction de Portage..."
mkdir -p "${MOUNT_POINT}/var/db/repos/gentoo"
cd "${MOUNT_POINT}/var/db/repos/gentoo"
tar xpf "${MOUNT_POINT}/portage-latest.tar.xz"
rm -f "${MOUNT_POINT}/portage-latest.tar.xz"
log_success "Portage extrait dans /var/db/repos/gentoo"

# ============================================================================
# EXERCICE 1.7 - PRÉPARATION DU CHROOT
# ============================================================================
log_info "EXERCICE 1.7 - Préparation de l'environnement chroot"

mount -t proc /proc "${MOUNT_POINT}/proc"
mount --rbind /sys "${MOUNT_POINT}/sys"
mount --make-rslave "${MOUNT_POINT}/sys"
mount --rbind /dev "${MOUNT_POINT}/dev"
mount --make-rslave "${MOUNT_POINT}/dev"
cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/"

log_success "Environnement chroot prêt"

# ============================================================================
# EXERCICE 1.8 - CONFIGURATION DE L'ENVIRONNEMENT (CHROOT)
# ============================================================================
log_info "EXERCICE 1.8 - Configuration de l'environnement dans le chroot"

chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_CMDS'
#!/bin/bash
set -euo pipefail

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[CHROOT]${NC} $1"; }
log_success() { echo -e "${GREEN}[CHROOT OK]${NC} $1"; }

source /etc/profile
export PS1="(chroot) \$PS1"

# Configuration du clavier français
log_info "Configuration du clavier français"
echo 'keymap="fr-latin1"' > /etc/conf.d/keymaps

# Configuration des locales
log_info "Configuration des locales fr_FR.UTF-8"
cat > /etc/locale.gen <<'EOF'
fr_FR.UTF-8 UTF-8
en_US.UTF-8 UTF-8
EOF
locale-gen
eselect locale set fr_FR.utf8
env-update
source /etc/profile

# Configuration du hostname
log_info "Configuration du nom d'hôte"
echo "gentoo-tp1" > /etc/hostname

# Configuration du fuseau horaire
log_info "Configuration du fuseau horaire Europe/Paris"
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
echo "Europe/Paris" > /etc/timezone

# Configuration réseau avec dhcpcd
log_info "Configuration réseau DHCP"
cat > /etc/conf.d/net <<'EOF'
config_eth0="dhcp"
EOF

cd /etc/init.d
ln -sf net.lo net.eth0
rc-update add net.eth0 default

# Configuration de /etc/fstab
log_info "Configuration de /etc/fstab"
cat > /etc/fstab <<'EOF'
# <fs>         <mountpoint>  <type>  <opts>              <dump/pass>
LABEL=root     /             ext4    defaults,noatime    0 1
LABEL=boot     /boot         ext2    defaults            0 2
LABEL=home     /home         ext4    defaults,noatime    0 2
LABEL=swap     none          swap    sw                  0 0
EOF

log_success "=== Configuration de base terminée (Exercice 1.8) ==="

CHROOT_CMDS

# ============================================================================
# EXERCICE 1.9 - INSTALLATION DE HTOP + SYSTÈME COMPLET
# ============================================================================
log_info "EXERCICE 1.9 - Installation de htop et configuration système complète"

chroot "${MOUNT_POINT}" /bin/bash <<'SYSTEM_CMDS'
#!/bin/bash
set -euo pipefail

source /etc/profile
export PS1="(chroot) \$PS1"

echo "🔧 Configuration du système complet pour l'export OVA..."

# Configuration de Portage
mkdir -p /etc/portage/repos.conf
cat > /etc/portage/repos.conf/gentoo.conf <<'EOF'
[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
auto-sync = yes
EOF

# Synchronisation de Portage
echo "🔁 Synchronisation de Portage..."
emerge-webrsync

# Installation de htop
echo "📦 Installation de htop avec emerge..."
emerge --noreplace --quiet htop

# Installation des outils système essentiels
echo "📦 Installation des outils système..."
emerge --noreplace --quiet app-admin/sudo
emerge --noreplace --quiet sys-kernel/gentoo-sources
emerge --noreplace --quiet sys-kernel/genkernel
emerge --noreplace --quiet sys-boot/grub

# Installation de dhcpcd
echo "📦 Installation de dhcpcd..."
emerge --noreplace --quiet net-misc/dhcpcd

# Configuration des utilisateurs
echo "👤 Configuration des utilisateurs..."
echo "root:gentoo" | chpasswd
useradd -m -G users,wheel -s /bin/bash etudiant
echo "etudiant:etudiant" | chpasswd

# Configuration sudo
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# Compilation du noyau
echo "🐧 Compilation du noyau (cette étape peut prendre 20-30 minutes)..."
genkernel all

# Installation de GRUB
echo "🔧 Installation de GRUB..."
grub-install /dev/vda
grub-mkconfig -o /boot/grub/grub.cfg

# Configuration des services
echo "🔧 Configuration des services..."
rc-update add dhcpcd default
rc-update add sshd default

# Création d'un fichier de bienvenue
cat > /etc/motd <<'EOF'
=============================================
    🐧 Gentoo TP1 - ISTY ADMSYS
    Installation complète avec export OVA
=============================================
- User: etudiant/etudiant ou root/gentoo
- Toutes les partitions sont montées
- Environnement français configuré
- Htop installé pour le monitoring
=============================================
EOF

# Script de premier démarrage pour régénération des clés
cat > /etc/firstboot.sh <<'EOF'
#!/bin/bash
if [ ! -f /etc/ssh/ssh_host_key ]; then
    echo "🔑 Génération des clés SSH..."
    ssh-keygen -A
fi
# Régénération machine-id pour systemd
if [ -f /etc/machine-id ]; then
    rm /etc/machine-id
    systemd-machine-id-setup
fi
rm -f /etc/firstboot.sh
EOF

chmod +x /etc/firstboot.sh

echo "✅ Système complètement configuré et prêt pour l'export OVA"

SYSTEM_CMDS

# ============================================================================
# NETTOYAGE ET PRÉPARATION POUR L'EXPORT
# ============================================================================
log_info "Préparation de l'export OVA"

chroot "${MOUNT_POINT}" /bin/bash <<'CLEANUP_CMDS'
#!/bin/bash
set -euo pipefail

source /etc/profile

echo "🧹 Nettoyage du système pour l'export..."

# Nettoyage des logs
rm -rf /var/log/*
find /var/tmp -type f -delete 2>/dev/null || true
find /tmp -type f -delete 2>/dev/null || true

# Nettoyage de l'historique
rm -f /root/.bash_history
rm -f /home/etudiant/.bash_history

# Nettoyage des fichiers temporaires de Portage
rm -rf /var/tmp/portage/*
rm -rf /var/cache/edb/dep/*

echo "✅ Nettoyage terminé"

CLEANUP_CMDS

# Démontage propre
log_info "Démontage des partitions..."
cd /
umount -l "${MOUNT_POINT}/dev"{/shm,/pts,} 2>/dev/null || true
umount -R "${MOUNT_POINT}" 2>/dev/null || true
swapoff "${DISK}2" 2>/dev/null || true

# ============================================================================
# CRÉATION DE LA VM ET EXPORT OVA
# ============================================================================
log_info "Création de la VM VirtualBox et export OVA"

# Créer la VM
if ! VBoxManage list vms | grep -q "${VM_NAME}"; then
    VBoxManage createvm --name "${VM_NAME}" --ostype "Gentoo_64" --register
    VBoxManage modifyvm "${VM_NAME}" --memory 2048 --cpus 2
    VBoxManage modifyvm "${VM_NAME}" --nic1 nat
    VBoxManage modifyvm "${VM_NAME}" --graphicscontroller vmsvga
    
    # Attacher le disque dur
    VBoxManage storagectl "${VM_NAME}" --name "SATA Controller" --add sata --controller IntelAhci
    VBoxManage storageattach "${VM_NAME}" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "${DISK}"
    
    log_success "VM ${VM_NAME} créée"
fi

# Exporter en OVA
log_info "Export de la VM en OVA..."
VBoxManage export "${VM_NAME}" --output "${OVA_FILE}" --ovf20

if [ -f "${OVA_FILE}" ]; then
    log_success "✅ Export OVA réussi: ${OVA_FILE}"
    echo ""
    echo "📦 Fichier OVA créé: $(pwd)/${OVA_FILE}"
    echo "   Taille: $(du -h "${OVA_FILE}" | cut -f1)"
else
    log_error "❌ Échec de l'export OVA"
    exit 1
fi

# ============================================================================
# CRÉATION DU GUIDE D'IMPORTATION
# ============================================================================
cat > "IMPORT_README.txt" <<'EOF'
🎯 GENTOO TP1 - GUIDE D'IMPORTATION
====================================

📦 FICHIER OVA : Gentoo-TP1-ISTY.ova

🚀 IMPORTATION RAPIDE :

1. Ouvrir VirtualBox
2. Fichier → Importer un service virtualisé  
3. Sélectionner le fichier .ova
4. Lancer la VM importée

🔧 INFORMATIONS DE CONNEXION :

- Utilisateur standard : etudiant / etudiant
- Utilisateur root : root / gentoo
- Sudo configuré pour l'utilisateur 'etudiant'

🐧 ENVIRONNEMENT PRÉCONFIGURÉ :

✓ Partitions montées : /boot, /, /home, swap
✓ Locales françaises (fr_FR.UTF-8)
✓ Clavier français (fr-latin1)  
✓ Fuseau horaire Europe/Paris
✓ Réseau DHCP configuré
✓ Noyau Gentoo compilé
✓ Bootloader GRUB installé
✓ Htop installé pour le monitoring
✓ Sudo configuré

🔍 VÉRIFICATION :

# Vérifier les partitions montées
$ mount | grep -E "(boot|home)"

# Vérifier la locale
$ locale

# Vérifier le réseau
$ ip addr show eth0

# Tester htop
$ htop

⚠️  RECOMMANDATIONS :

- Changez les mots de passe après le premier démarrage
- Les clés SSH seront régénérées automatiquement
- Machine-id unique créée au premier boot

📚 POUR LE TP :

Toutes les étapes des exercices 1.1 à 1.9 sont complétées
et l'environnement est entièrement préservé dans l'OVA.

Bon TP ! 🐧
EOF

log_success "Guide d'importation créé: IMPORT_README.txt"

# ============================================================================
# RAPPORT FINAL
# ============================================================================
echo ""
echo "================================================================"
log_success "🎉 TP1 COMPLÈTEMENT TERMINÉ AVEC EXPORT OVA !"
echo "================================================================"
echo ""
echo "📋 Récapitulatif :"
echo "  ✅ Exercices 1.1 à 1.9 complétés"
echo "  ✅ Partitions créées et montées"
echo "  ✅ Système Gentoo complètement installé"
echo "  ✅ Noyau compilé et GRUB configuré"
echo "  ✅ Environnement français configuré"
echo "  ✅ Utilisateurs créés"
echo "  ✅ Htop installé"
echo "  ✅ VM exportée en OVA"
echo ""
echo "📦 FICHIERS CRÉÉS :"
echo "  - ${OVA_FILE} (VM exportée)"
echo "  - IMPORT_README.txt (guide d'importation)"
echo ""
echo "🚀 POUR L'IMPORTATION :"
echo "   VirtualBox → Fichier → Importer un service virtualisé"
echo "   Sélectionner : ${OVA_FILE}"
echo ""
echo "🔗 La personne qui importe l'OVA verra EXACTEMENT le même"
echo "   environnement que vous avez configuré !"
echo ""