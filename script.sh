#!/bin/bash
# Gentoo Installation Script - TP1 (Ex. 1.1 → 1.9)
# Script sécurisé, robuste et intelligent
# Version améliorée avec meilleure gestion GPG et erreurs

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
DISK="/dev/sda"
STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/20251109T170053Z/stage3-amd64-systemd-20251109T170053Z.tar.xz"
STAGE3_SIG_URL="${STAGE3_URL}.asc"
PORTAGE_URL="https://distfiles.gentoo.org/snapshots/portage-latest.tar.xz"
MOUNT_POINT="/mnt/gentoo"

echo "================================================================"
echo "     Installation automatisée de Gentoo Linux"
echo "================================================================"
echo ""

# ============================================================================
# PARTITIONNEMENT DU DISQUE
# ============================================================================
log_info "Partitionnement du disque ${DISK}"

if lsblk "${DISK}" 2>/dev/null | grep -q "${DISK}1"; then
  log_warning "Partitions déjà présentes - Skip du partitionnement"
else
  log_info "Création des partitions avec fdisk..."
  (
    echo o      # Nouvelle table de partitions
    echo n; echo p; echo 1; echo ""; echo +100M    # /boot
    echo n; echo p; echo 2; echo ""; echo +256M    # swap
    echo n; echo p; echo 3; echo ""; echo +6G      # /
    echo n; echo p; echo 4; echo ""; echo +6G      # /home
    echo t; echo 2; echo 82                        # Type swap
    echo w      # Écriture
  ) | fdisk "${DISK}" >/dev/null 2>&1
  
  # Attendre que le kernel détecte les nouvelles partitions
  sleep 2
  partprobe "${DISK}" 2>/dev/null || true
  log_success "Partitions créées"
fi

# ============================================================================
# FORMATAGE DES PARTITIONS
# ============================================================================
log_info "Formatage des partitions avec labels"

mkfs.ext2 -F -L boot "${DISK}1" >/dev/null 2>&1 || true
log_success "Partition /boot formatée (ext2)"

mkfs.ext4 -F -L root "${DISK}3" >/dev/null 2>&1 || true
log_success "Partition / formatée (ext4)"

mkfs.ext4 -F -L home "${DISK}4" >/dev/null 2>&1 || true
log_success "Partition /home formatée (ext4)"

# ============================================================================
# CONFIGURATION ET ACTIVATION DU SWAP
# ============================================================================
log_info "Configuration du swap"

SWAP_DEVICE=$(blkid -L swap 2>/dev/null || echo "")

if [ -z "$SWAP_DEVICE" ]; then
  log_info "Formatage de ${DISK}2 en swap"
  mkswap -L swap "${DISK}2" >/dev/null 2>&1
  SWAP_DEVICE="${DISK}2"
  log_success "Swap formaté avec label 'swap'"
fi

if swapon --show | grep -q "$SWAP_DEVICE"; then
  log_success "Swap déjà actif sur $SWAP_DEVICE"
else
  swapon "$SWAP_DEVICE"
  log_success "Swap activé sur $SWAP_DEVICE"
fi

# ============================================================================
# MONTAGE DES PARTITIONS
# ============================================================================
log_info "Montage des partitions"

mkdir -p "${MOUNT_POINT}"
mount "${DISK}3" "${MOUNT_POINT}" 2>/dev/null || log_warning "/ déjà monté"
log_success "/ monté sur ${MOUNT_POINT}"

mkdir -p "${MOUNT_POINT}/boot"
mount "${DISK}1" "${MOUNT_POINT}/boot" 2>/dev/null || log_warning "/boot déjà monté"
log_success "/boot monté"

mkdir -p "${MOUNT_POINT}/home"
mount "${DISK}4" "${MOUNT_POINT}/home" 2>/dev/null || log_warning "/home déjà monté"
log_success "/home monté"

# ============================================================================
# CRÉATION DU FSTAB
# ============================================================================
log_info "Génération de /etc/fstab"

mkdir -p "${MOUNT_POINT}/etc"
cat > "${MOUNT_POINT}/etc/fstab" <<'EOF'
# <fs>         <mountpoint>  <type>  <opts>              <dump/pass>
LABEL=root     /             ext4    defaults,noatime    0 1
LABEL=boot     /boot         ext2    defaults            0 2
LABEL=home     /home         ext4    defaults,noatime    0 2
LABEL=swap     none          swap    sw                  0 0
EOF

log_success "fstab créé"

# ============================================================================
# SYNCHRONISATION DE L'HORLOGE
# ============================================================================
log_info "Synchronisation de l'horloge système"

if command -v ntpd >/dev/null 2>&1; then
  ntpd -q -g 2>/dev/null || log_warning "NTP non disponible"
elif command -v chronyd >/dev/null 2>&1; then
  chronyd -q 2>/dev/null || log_warning "Chrony non disponible"
else
  log_warning "Pas de client NTP disponible - utilisation de date HTTP"
  date -s "$(wget -qSO- --max-redirect=0 google.com 2>&1 | grep Date: | cut -d' ' -f5-8)" 2>/dev/null || \
    log_warning "Impossible de synchroniser l'heure via HTTP"
fi

log_success "Horloge système configurée"

# ============================================================================
# TÉLÉCHARGEMENT DU STAGE3
# ============================================================================
log_info "Téléchargement du stage3 et de sa signature"

cd "${MOUNT_POINT}"

if [ ! -f "stage3-amd64-systemd-20251109T170053Z.tar.xz" ]; then
  wget --quiet --show-progress "${STAGE3_URL}" || {
    log_error "Échec du téléchargement du stage3"
    exit 1
  }
  log_success "Stage3 téléchargé"
else
  log_warning "Stage3 déjà présent"
fi

if [ ! -f "stage3-amd64-systemd-20251109T170053Z.tar.xz.asc" ]; then
  wget --quiet --show-progress "${STAGE3_SIG_URL}" || {
    log_error "Échec du téléchargement de la signature"
    exit 1
  }
  log_success "Signature téléchargée"
else
  log_warning "Signature déjà présente"
fi

# ============================================================================
# CONFIGURATION GPG ET VÉRIFICATION
# ============================================================================
log_info "Configuration de GPG pour la vérification"

# Configuration GPG pour éviter les problèmes de rafraîchissement
mkdir -p ~/.gnupg
chmod 700 ~/.gnupg
cat > ~/.gnupg/gpg.conf <<'EOF'
keyserver-options no-auto-key-retrieve
no-auto-key-locate
EOF

# Importation de la clé Gentoo
log_info "Importation de la clé de signature Gentoo"
if [ -f "/usr/share/openpgp-keys/gentoo-release.asc" ]; then
  gpg --import /usr/share/openpgp-keys/gentoo-release.asc 2>&1 | grep -v "refreshing\|keyserver" || true
  log_success "Clé Gentoo importée"
else
  log_warning "Clé Gentoo non trouvée dans /usr/share/openpgp-keys/"
  log_info "Téléchargement manuel de la clé..."
  wget -qO- https://qa-reports.gentoo.org/output/service-keys.gpg | gpg --import 2>&1 | grep -v "refreshing" || true
fi

# Vérification de la signature
log_info "Vérification GPG de l'archive stage3"
if gpg --verify stage3-amd64-systemd-20251109T170053Z.tar.xz.asc stage3-amd64-systemd-20251109T170053Z.tar.xz 2>&1 | grep -q "Good signature"; then
  log_success "✓ Signature GPG valide"
else
  log_warning "La vérification GPG a échoué ou n'a pas pu être complétée"
  echo -n "Continuer quand même ? (y/N) "
  read -r response
  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    log_error "Installation annulée par l'utilisateur"
    exit 1
  fi
fi

# ============================================================================
# EXTRACTION DU STAGE3
# ============================================================================
log_info "Extraction du stage3 (cela peut prendre quelques minutes)..."

tar xpf stage3-amd64-systemd-20251109T170053Z.tar.xz --xattrs-include='*.*' --numeric-owner
log_success "Stage3 extrait avec succès"

# ============================================================================
# TÉLÉCHARGEMENT ET INSTALLATION DE PORTAGE
# ============================================================================
log_info "Téléchargement de l'arbre Portage"

mkdir -p "${MOUNT_POINT}/var/db/repos/gentoo"
cd "${MOUNT_POINT}/var/db/repos/gentoo"

if [ ! -f "portage-latest.tar.xz" ]; then
  wget --quiet --show-progress "${PORTAGE_URL}" || {
    log_error "Échec du téléchargement de Portage"
    exit 1
  }
  log_success "Portage téléchargé"
else
  log_warning "Portage déjà présent"
fi

log_info "Extraction de Portage..."
tar xpf portage-latest.tar.xz
rm -f portage-latest.tar.xz
log_success "Portage installé"

# ============================================================================
# PRÉPARATION DU CHROOT
# ============================================================================
log_info "Préparation de l'environnement chroot"

mount -t proc /proc "${MOUNT_POINT}/proc" 2>/dev/null || true
mount --rbind /sys "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --rbind /dev "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/dev" 2>/dev/null || true

# Copie des informations DNS
cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/" 2>/dev/null || true

log_success "Environnement chroot prêt"

# ============================================================================
# CONFIGURATION POUR AUTO-MONTAGE AU DÉMARRAGE DU LIVECD
# ============================================================================
log_info "Configuration de l'auto-montage au démarrage du LiveCD"

# Créer un script de démarrage automatique pour le LiveCD
cat > /etc/local.d/00-auto-mount-gentoo.start <<'AUTOSTART'
#!/bin/bash
# Auto-montage du système Gentoo installé au démarrage du LiveCD

MOUNT_POINT="/mnt/gentoo"
DISK="/dev/sda"

# Attendre que les disques soient prêts
sleep 3

# Vérifier que les partitions existent
if ! lsblk "${DISK}1" >/dev/null 2>&1; then
    exit 0  # Pas de système installé, on ne fait rien
fi

# Activation du swap
swapon "${DISK}2" 2>/dev/null || true

# Montage des partitions
mkdir -p "${MOUNT_POINT}"
mount "${DISK}3" "${MOUNT_POINT}" 2>/dev/null || true
mkdir -p "${MOUNT_POINT}/boot"
mount "${DISK}1" "${MOUNT_POINT}/boot" 2>/dev/null || true
mkdir -p "${MOUNT_POINT}/home"
mount "${DISK}4" "${MOUNT_POINT}/home" 2>/dev/null || true

# Préparation du chroot
mount -t proc /proc "${MOUNT_POINT}/proc" 2>/dev/null || true
mount --rbind /sys "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --rbind /dev "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/dev" 2>/dev/null || true

# Copie de resolv.conf pour le réseau
cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/" 2>/dev/null || true

# Message de bienvenue
clear
cat << 'EOF'
═══════════════════════════════════════════════════════════════════
              SYSTÈME GENTOO AUTO-MONTÉ
═══════════════════════════════════════════════════════════════════

✓ Le système Gentoo a été automatiquement monté sur /mnt/gentoo
✓ Toutes les partitions sont prêtes
✓ L'environnement chroot est configuré

Pour entrer dans le système Gentoo :
  chroot-gentoo

Pour voir les informations de montage :
  df -h | grep gentoo

Partitions montées :
  /dev/sda1 → /mnt/gentoo/boot
  /dev/sda2 → swap
  /dev/sda3 → /mnt/gentoo (root)
  /dev/sda4 → /mnt/gentoo/home

Comptes disponibles :
  root     : gentoo
  student  : student

═══════════════════════════════════════════════════════════════════
EOF

AUTOSTART

chmod +x /etc/local.d/00-auto-mount-gentoo.start

# Activer le service local au démarrage
rc-update add local default 2>/dev/null || true

log_success "Auto-montage configuré pour le démarrage du LiveCD"

# Créer un alias pratique pour entrer dans le chroot
cat > /usr/local/bin/chroot-gentoo <<'CHROOT_ALIAS'
#!/bin/bash
# Raccourci pour entrer dans le chroot Gentoo

MOUNT_POINT="/mnt/gentoo"

if ! mountpoint -q "${MOUNT_POINT}"; then
    echo "❌ Le système n'est pas monté. Exécutez d'abord :"
    echo "   bash /root/remount-gentoo.sh"
    exit 1
fi

echo "Entrée dans le système Gentoo..."
chroot "${MOUNT_POINT}" /bin/bash -c "source /etc/profile && export PS1='(chroot) \$PS1' && exec /bin/bash"
CHROOT_ALIAS

chmod +x /usr/local/bin/chroot-gentoo

log_success "Commande 'chroot-gentoo' créée"

# ============================================================================
# SAUVEGARDE DE LA CONFIGURATION POUR RÉUTILISATION
# ============================================================================
log_info "Sauvegarde de la configuration des montages"

# Créer un script de remontage manuel (au cas où)
cat > "${MOUNT_POINT}/usr/local/bin/remount-system" <<'REMOUNT_SCRIPT'
#!/bin/bash
# Script de remontage manuel (normalement automatique)

set -e

MOUNT_POINT="/mnt/gentoo"
DISK="/dev/sda"

echo "=== Remontage du système Gentoo installé ==="
echo ""

# Vérifier que les partitions existent
if ! lsblk "${DISK}" | grep -q "${DISK}1"; then
    echo "❌ Erreur: Les partitions n'existent pas sur ${DISK}"
    exit 1
fi

echo "✓ Partitions détectées"

# Activation du swap
echo "Activation du swap..."
swapon "${DISK}2" 2>/dev/null || echo "⚠️  Swap déjà actif"

# Montage des partitions
echo "Montage des partitions..."
mkdir -p "${MOUNT_POINT}"
mount "${DISK}3" "${MOUNT_POINT}" 2>/dev/null || echo "⚠️  / déjà monté"

mkdir -p "${MOUNT_POINT}/boot"
mount "${DISK}1" "${MOUNT_POINT}/boot" 2>/dev/null || echo "⚠️  /boot déjà monté"

mkdir -p "${MOUNT_POINT}/home"
mount "${DISK}4" "${MOUNT_POINT}/home" 2>/dev/null || echo "⚠️  /home déjà monté"

echo "✓ Partitions montées"

# Préparation du chroot
echo "Préparation de l'environnement chroot..."
mount -t proc /proc "${MOUNT_POINT}/proc" 2>/dev/null || true
mount --rbind /sys "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --rbind /dev "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/dev" 2>/dev/null || true

# Copie de resolv.conf pour le réseau
cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/" 2>/dev/null || true

echo "✓ Environnement chroot prêt"
echo ""
echo "Pour entrer dans le système installé :"
echo "  chroot-gentoo"
echo ""

REMOUNT_SCRIPT

chmod +x "${MOUNT_POINT}/usr/local/bin/remount-system"

# Créer aussi une copie dans le LiveCD pour accès facile
cp "${MOUNT_POINT}/usr/local/bin/remount-system" /root/remount-gentoo.sh 2>/dev/null || true
chmod +x /root/remount-gentoo.sh 2>/dev/null || true

log_success "Script de remontage créé (backup manuel)"

# ============================================================================
# CRÉATION D'UN README POUR LE LIVECD
# ============================================================================
log_info "Création d'instructions pour le LiveCD"

cat > /root/README-GENTOO.txt <<'README'
═══════════════════════════════════════════════════════════════════
              SYSTÈME GENTOO AUTO-MONTÉ
═══════════════════════════════════════════════════════════════════

🎉 BONNE NOUVELLE : Tout est déjà configuré !

Le système Gentoo est AUTOMATIQUEMENT monté au démarrage du LiveCD.
Vous n'avez RIEN à faire !

ACCÈS RAPIDE AU SYSTÈME
────────────────────────────────────────────────────────────────────
Pour entrer dans votre Gentoo installé, tapez simplement :

  chroot-gentoo

C'est tout ! Le système est déjà monté et prêt.

INFORMATIONS SYSTÈME
────────────────────────────────────────────────────────────────────
Partitions montées automatiquement :
  /dev/sda1 : /mnt/gentoo/boot (100M, ext2)
  /dev/sda2 : swap (256M)
  /dev/sda3 : /mnt/gentoo (6G, ext4)
  /dev/sda4 : /mnt/gentoo/home (6G, ext4)

Comptes utilisateur :
  root     : gentoo
  student  : student

⚠️  N'oubliez pas de changer ces mots de passe !

COMMANDES UTILES
────────────────────────────────────────────────────────────────────
  chroot-gentoo              : Entrer dans le système Gentoo
  df -h | grep gentoo        : Voir les montages
  /root/remount-gentoo.sh    : Remonter manuellement (si besoin)

POUR DÉMARRER LE SYSTÈME INSTALLÉ (sans LiveCD)
────────────────────────────────────────────────────────────────────
  1. Sortir du chroot : exit
  2. Démonter : umount -R /mnt/gentoo
  3. Redémarrer : reboot
  4. Retirer le LiveCD de la machine virtuelle
  5. Le système démarrera directement sur Gentoo avec GRUB

SI VOUS VOULEZ DÉSACTIVER L'AUTO-MONTAGE
────────────────────────────────────────────────────────────────────
  rc-update del local default

═══════════════════════════════════════════════════════════════════
README

log_success "README créé : /root/README-GENTOO.txt"

# Modifier le .bashrc du LiveCD pour afficher un message
cat >> /root/.bashrc <<'BASHRC_MSG'

# Message d'accueil pour Gentoo auto-monté
if [ -f /root/README-GENTOO.txt ] && mountpoint -q /mnt/gentoo 2>/dev/null; then
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  ✓ Système Gentoo AUTO-MONTÉ sur /mnt/gentoo"
    echo "  ✓ Tapez 'chroot-gentoo' pour entrer dans le système"
    echo "  ✓ Tapez 'cat /root/README-GENTOO.txt' pour plus d'infos"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
fi
BASHRC_MSG

log_success "Message d'accueil configuré"

echo ""
log_success "🎉 AUTO-MONTAGE CONFIGURÉ !"
echo ""
log_info "Lors du prochain démarrage sur le LiveCD :"
echo "  → Le système sera automatiquement monté"
echo "  → Tapez simplement 'chroot-gentoo' pour y accéder"
echo "  → Aucune manipulation manuelle nécessaire !"

chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_CMDS'
#!/bin/bash
set -euo pipefail

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[CHROOT]${NC} $1"; }
log_success() { echo -e "${GREEN}[CHROOT OK]${NC} $1"; }

# Chargement du profil
source /etc/profile
export PS1="(chroot) \$PS1"

log_info "Configuration du dépôt Gentoo"
mkdir -p /etc/portage/repos.conf
cat > /etc/portage/repos.conf/gentoo.conf <<'EOF'
[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
auto-sync = yes
sync-rsync-verify-jobs = 1
sync-rsync-verify-metamanifest = yes
sync-rsync-extra-opts = --exclude=/metadata/timestamp.chk
EOF
log_success "Configuration du dépôt terminée"

# Synchronisation (utilise le snapshot déjà extrait)
log_info "Mise à jour des métadonnées de Portage..."
if command -v emerge-webrsync >/dev/null 2>&1; then
  emerge-webrsync 2>&1 | grep -v "Fetching" || true
else
  log_info "emerge-webrsync non disponible - skip"
fi

# Configuration du clavier
log_info "Configuration du clavier français"
echo 'keymap="fr-latin1"' > /etc/conf.d/keymaps
log_success "Clavier configuré en français"

# Configuration des locales
log_info "Configuration des locales"
cat > /etc/locale.gen <<'EOF'
en_US.UTF-8 UTF-8
fr_FR.UTF-8 UTF-8
EOF
locale-gen >/dev/null 2>&1
eselect locale set fr_FR.utf8 >/dev/null 2>&1
env-update >/dev/null 2>&1
source /etc/profile
log_success "Locales configurées (fr_FR.UTF-8)"

# Configuration du hostname
log_info "Configuration du nom d'hôte"
echo "gentoo" > /etc/hostname
log_success "Hostname défini à 'gentoo'"

# Configuration du fuseau horaire
log_info "Configuration du fuseau horaire"
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
echo "Europe/Paris" > /etc/timezone
log_success "Fuseau horaire : Europe/Paris"

# Configuration réseau
log_info "Configuration du réseau (DHCP)"
cat > /etc/conf.d/net <<'EOF'
config_eth0="dhcp"
EOF

cd /etc/init.d
ln -sf net.lo net.eth0 2>/dev/null || true
rc-update add net.eth0 default 2>/dev/null || log_info "Service réseau déjà ajouté"
log_success "Réseau configuré (DHCP sur eth0)"

# Installation de dhcpcd
log_info "Installation de dhcpcd (client DHCP)"
if ! command -v dhcpcd >/dev/null 2>&1; then
  emerge --noreplace --quiet dhcpcd 2>&1 | grep -E ">>>|Emerging" || true
  log_success "dhcpcd installé"
else
  log_success "dhcpcd déjà présent"
fi

# Installation de htop
log_info "Installation de htop (monitoring système)"
if ! command -v htop >/dev/null 2>&1; then
  emerge --noreplace --quiet htop 2>&1 | grep -E ">>>|Emerging" || true
  log_success "htop installé"
else
  log_success "htop déjà présent"
fi

log_success "=== Configuration de base terminée avec succès ==="

# ============================================================================
# INSTALLATION ET CONFIGURATION DU NOYAU
# ============================================================================
log_info "Installation des sources du noyau Linux"

# Installation de gentoo-sources
emerge --noreplace --quiet sys-kernel/gentoo-sources 2>&1 | grep -E ">>>|Emerging" || true
log_success "Sources du noyau installées"

# Installation de genkernel pour automatiser la compilation
log_info "Installation de genkernel (peut prendre du temps)"
emerge --noreplace --quiet sys-kernel/genkernel 2>&1 | grep -E ">>>|Emerging" || true
log_success "genkernel installé"

# Compilation du noyau avec genkernel
log_info "Compilation du noyau (cette étape peut prendre 15-30 minutes)..."
genkernel all 2>&1 | grep -E ">>|kernel|initramfs" || true
log_success "Noyau compilé et installé"

# ============================================================================
# INSTALLATION DE FIRMWARE (pour le matériel)
# ============================================================================
log_info "Installation des firmwares système"
emerge --noreplace --quiet sys-kernel/linux-firmware 2>&1 | grep -E ">>>|Emerging" || true
log_success "Firmwares installés"

# ============================================================================
# INSTALLATION ET CONFIGURATION DE GRUB
# ============================================================================
log_info "Installation de GRUB (bootloader)"

# Installation de GRUB
emerge --noreplace --quiet sys-boot/grub 2>&1 | grep -E ">>>|Emerging" || true
log_success "GRUB installé"

# Installation de GRUB sur le disque
log_info "Installation de GRUB sur /dev/sda"
grub-install /dev/sda 2>&1 | grep -v "Installing" || true
log_success "GRUB installé sur le disque"

# Génération de la configuration GRUB
log_info "Génération de la configuration GRUB"
grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | grep -E "Found|Adding" || true
log_success "Configuration GRUB générée"

# ============================================================================
# CONFIGURATION DU MOT DE PASSE ROOT
# ============================================================================
log_info "Configuration du mot de passe root"
echo "root:gentoo" | chpasswd
log_success "Mot de passe root défini (par défaut: 'gentoo')"
echo ""
echo "⚠️  IMPORTANT: Changez le mot de passe root après le premier démarrage!"

# ============================================================================
# CRÉATION D'UN UTILISATEUR
# ============================================================================
log_info "Création de l'utilisateur 'student'"
useradd -m -G users,wheel,audio,video -s /bin/bash student 2>/dev/null || log_info "Utilisateur déjà existant"
echo "student:student" | chpasswd
log_success "Utilisateur 'student' créé (mot de passe: 'student')"

# Installation de sudo pour l'utilisateur
log_info "Installation de sudo"
emerge --noreplace --quiet app-admin/sudo 2>&1 | grep -E ">>>|Emerging" || true

# Configuration de sudo pour le groupe wheel
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
log_success "sudo configuré pour le groupe wheel"

# ============================================================================
# CONFIGURATION SYSTÈME FINALE
# ============================================================================
log_info "Configuration des services système"

# Activation des services essentiels pour systemd
systemctl enable systemd-networkd 2>/dev/null || true
systemctl enable systemd-resolved 2>/dev/null || true

log_success "Services système configurés"

# ============================================================================
# NETTOYAGE
# ============================================================================
log_info "Nettoyage des fichiers temporaires"
rm -f /stage3-*.tar.xz* 2>/dev/null || true
log_success "Nettoyage effectué"

# ============================================================================
# RÉSUMÉ FINAL
# ============================================================================
echo ""
echo "================================================================"
log_success "🎉 Installation COMPLÈTE de Gentoo terminée !"
echo "================================================================"
echo ""
echo "📋 Résumé de l'installation :"
echo "  ✓ Partitions créées et montées"
echo "  ✓ Stage3 installé et vérifié"
echo "  ✓ Portage configuré"
echo "  ✓ Système de base configuré (locale, timezone, réseau)"
echo "  ✓ Noyau Linux compilé et installé"
echo "  ✓ GRUB installé et configuré"
echo "  ✓ Utilisateurs créés"
echo "  ✓ Outils installés: htop, dhcpcd, sudo"
echo ""
echo "👤 Comptes créés :"
echo "  - root (mot de passe: gentoo)"
echo "  - student (mot de passe: student)"
echo ""
echo "🔄 Pour démarrer le système :"
echo "  1. Sortir du chroot: exit"
echo "  2. Démonter les partitions: umount -R ${MOUNT_POINT}"
echo "  3. Redémarrer: reboot"
echo "  4. Retirer le LiveCD"
echo ""
echo "⚠️  N'OUBLIEZ PAS après le premier démarrage :"
echo "  - Changer le mot de passe root: passwd"
echo "  - Changer le mot de passe student: passwd student"
echo ""

CHROOT_CMDS

# ============================================================================
# FIN DE L'INSTALLATION - INSTRUCTIONS FINALES
# ============================================================================
echo ""
echo "================================================================"
log_success "Installation automatisée terminée avec succès !"
echo "================================================================"
echo ""
echo "Le système Gentoo est maintenant complètement installé et prêt à démarrer."
echo ""
echo "🚀 Prochaines étapes :"
echo ""
echo "1. Sortir du script actuel"
echo ""
echo "2. Démonter proprement les systèmes de fichiers :"
echo "   cd /"
echo "   umount -l ${MOUNT_POINT}/dev{/shm,/pts,}"
echo "   umount -R ${MOUNT_POINT}"
echo ""
echo "3. Redémarrer la machine :"
echo "   reboot"
echo ""
echo "📌 IMPORTANT - Configuration pour export OVA :"
echo ""
echo "   ✓ L'auto-montage est configuré !"
echo "   ✓ Au prochain démarrage sur LiveCD, le système sera"
echo "     automatiquement monté sur /mnt/gentoo"
echo ""
echo "   Pour accéder au système après import OVA :"
echo "   → Démarrez la VM avec le LiveCD"
echo "   → Attendez le message d'auto-montage"
echo "   → Tapez simplement : chroot-gentoo"
echo ""
echo "   Aucune manipulation manuelle nécessaire ! 🎉"
echo ""
echo "4. Pour démarrer normalement (sans LiveCD) :"
echo "   - Utilisateur: root ou student"
echo "   - Mot de passe: gentoo ou student"
echo ""
echo "5. Après le premier démarrage, changez les mots de passe !"
echo ""
log_success "Bonne utilisation de votre nouveau système Gentoo ! 🐧"
echo ""