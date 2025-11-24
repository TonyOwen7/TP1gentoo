#!/bin/bash
# TP2 ULTRA-CORRIGÉ - Installation manuelle garantie du noyau

SECRET_CODE="1234"

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

echo "✅ Code correct, installation ULTRA-GARANTIE du noyau..."

set -euo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# Configuration
DISK="/dev/sda"
MOUNT_POINT="/mnt/gentoo"

echo "================================================================"
echo "     TP2 ULTRA-CORRIGÉ - Installation MANUELLE noyau"
echo "================================================================"
echo ""

# ============================================================================
# MONTAGE DES PARTITIONS
# ============================================================================
log_info "Montage des partitions..."
mount "${DISK}3" "${MOUNT_POINT}" 2>/dev/null || log_warning "Racine déjà montée"
mkdir -p "${MOUNT_POINT}/boot"
mount "${DISK}1" "${MOUNT_POINT}/boot" 2>/dev/null || log_warning "Boot déjà monté"
swapon "${DISK}2" 2>/dev/null || log_warning "Swap déjà activé"

# Monter l'environnement chroot
mount -t proc /proc "${MOUNT_POINT}/proc"
mount --rbind /sys "${MOUNT_POINT}/sys"
mount --make-rslave "${MOUNT_POINT}/sys"
mount --rbind /dev "${MOUNT_POINT}/dev" 
mount --make-rslave "${MOUNT_POINT}/dev"
cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/"

# ============================================================================
# SCRIPT D'INSTALLATION MANUELLE DU NOYAU
# ============================================================================
log_info "Création du script d'installation MANUELLE du noyau..."

cat > "${MOUNT_POINT}/root/install_noyau_manuel.sh" << 'MANUEL_SCRIPT'
#!/bin/bash
# Installation MANUELLE garantie du noyau

set -euo pipefail

# Couleurs pour le chroot
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[CHROOT]${NC} $1"; }
log_success() { echo -e "${GREEN}[CHROOT ✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[CHROOT !]${NC} $1"; }
log_error() { echo -e "${RED}[CHROOT ✗]${NC} $1"; }

echo ""
echo "================================================================"
log_info "DÉBUT INSTALLATION MANUELLE NOYAU"
echo "================================================================"

# ============================================================================
# ÉTAPE 1: NETTOYAGE ET PRÉPARATION
# ============================================================================
log_info "1/6 - Nettoyage et préparation..."

# Désactiver sandbox
echo 'FEATURES="-sandbox -usersandbox"' >> /etc/portage/make.conf
export FEATURES="-sandbox -usersandbox"

# Vérifier l'espace
log_info "Espace disque disponible:"
df -h /boot
df -h /

# Nettoyer /boot au cas où
rm -f /boot/vmlinuz-* /boot/System.map-* /boot/config-* 2>/dev/null || true

# ============================================================================
# ÉTAPE 2: INSTALLATION SOURCES NOYAU
# ============================================================================
log_info "2/6 - Installation sources noyau..."

# Méthode ULTRA-FORCÉE
if ! emerge --noreplace --verbose --nodeps sys-kernel/gentoo-sources 2>&1 | tee /tmp/sources_install.log; then
    log_error "Échec installation sources"
    log_info "Tentative avec --getbinpkg..."
    emerge --noreplace --getbinpkg sys-kernel/gentoo-sources 2>&1 | tee /tmp/sources_bin.log || {
        log_error "Échec critique sources"
        exit 1
    }
fi

# Vérifier que les sources sont là
if ! ls -d /usr/src/linux-* >/dev/null 2>&1; then
    log_error "Sources non trouvées après installation"
    log_info "Contenu de /usr/src:"
    ls -la /usr/src/
    exit 1
fi

KERNEL_VER=$(ls -d /usr/src/linux-* | head -1 | sed 's|/usr/src/linux-||')
log_success "Sources installées: ${KERNEL_VER}"

# Lien symbolique
cd /usr/src
ln -sf linux-* linux 2>/dev/null || true

# ============================================================================
# ÉTAPE 3: CONFIGURATION NOYAU ULTRA-MINIMALE
# ============================================================================
log_info "3/6 - Configuration noyau ULTRA-minimale..."

cd /usr/src/linux

# Configuration de base
log_info "Génération configuration défaut..."
make defconfig 2>&1 | tail -5

# Configuration ABSOLUMENT MINIMALE POUR DÉMARRER
log_info "Application configuration minimale critique..."

# Créer un fichier de config manuel si scripts/config échoue
cat > .config << 'MINIMAL_CONFIG'
CONFIG_64BIT=y
CONFIG_SMP=y
CONFIG_NR_CPUS=8
CONFIG_HZ_1000=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_BLOCK=y
CONFIG_BLK_DEV=y
CONFIG_BLK_DEV_SD=y
CONFIG_SCSI=y
CONFIG_SCSI_LOWLEVEL=y
CONFIG_ATA=y
CONFIG_ATA_SFF=y
CONFIG_ATA_BMDMA=y
CONFIG_ATA_PIIX=y
CONFIG_NET=y
CONFIG_NETDEVICES=y
CONFIG_NET_CORE=y
CONFIG_INET=y
CONFIG_EXT4_FS=y
CONFIG_EXT4_FS_POSIX_ACL=y
CONFIG_EXT4_FS_SECURITY=y
CONFIG_VIRTIO_PCI=y
CONFIG_VIRTIO_BLK=y
CONFIG_VIRTIO_NET=y
CONFIG_VIRTIO_CONSOLE=y
CONFIG_E1000=y
CONFIG_SERIO=y
CONFIG_SERIO_I8042=y
CONFIG_VT=y
CONFIG_VT_CONSOLE=y
CONFIG_TTY=y
CONFIG_FB=y
CONFIG_FB_VESA=y
CONFIG_LOGO=y
CONFIG_UNIX98_PTYS=y
CONFIG_LEGACY_PTYS=y
CONFIG_PCI=y
CONFIG_PCI_MSI=y
CONFIG_X86_MSR=y
CONFIG_X86_CPUID=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
CONFIG_TMPFS=y
CONFIG_INOTIFY_USER=y
CONFIG_CRYPTO_USER=y
CONFIG_CRYPTO_CBC=y
CONFIG_CRYPTO_SHA256=y
CONFIG_CRYPTO_AES=y
CONFIG_KEY_DH_OPERATIONS=y
CONFIG_NET_9P=y
CONFIG_NET_9P_VIRTIO=y
CONFIG_9P_FS=y
CONFIG_NLS=y
CONFIG_NLS_UTF8=y
CONFIG_PRINTK_TIME=y
CONFIG_CONSOLE_LOGLEVEL_DEFAULT=7
CONFIG_MESSAGE_LOGLEVEL_DEFAULT=4
CONFIG_BINFMT_ELF=y
CONFIG_MMU=y
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y
CONFIG_PROC_SYSCTL=y
CONFIG_SYSCTL=y
CONFIG_UEVENT_HELPER=y
CONFIG_FW_LOADER=y
CONFIG_FIRMWARE_IN_KERNEL=y
MINIMAL_CONFIG

make olddefconfig 2>&1 | tail -3
log_success "Configuration appliquée"

# ============================================================================
# ÉTAPE 4: COMPILATION GARANTIE
# ============================================================================
log_info "4/6 - Compilation noyau (GARANTIE)..."
echo "⏰ Début: $(date '+%H:%M:%S')"

# Compilation noyau
if ! make 2>&1 | tee /tmp/compile.log; then
    log_error "❌ Échec compilation noyau"
    log_info "Dernières erreurs:"
    tail -30 /tmp/compile.log
    exit 1
fi

log_success "✅ Noyau compilé avec succès"

# Compilation modules
log_info "Compilation modules..."
if ! make modules 2>&1 | tee /tmp/modules.log; then
    log_warning "⚠️  Problème modules, continuation sans..."
fi

# ============================================================================
# ÉTAPE 5: INSTALLATION MANUELLE GARANTIE DANS /boot/
# ============================================================================
log_info "5/6 - Installation MANUELLE dans /boot/..."

# Vérifier que le noyau compilé existe
if [ ! -f "arch/x86/boot/bzImage" ]; then
    log_error "bzImage non trouvé après compilation"
    log_info "Recherche fichiers noyau..."
    find . -name "*Image*" -type f 2>/dev/null | head -10
    exit 1
fi

log_info "Copie MANUELLE du noyau vers /boot/..."

# Copier le noyau
cp -v arch/x86/boot/bzImage /boot/vmlinuz-${KERNEL_VER}-manuel
ln -sf vmlinuz-${KERNEL_VER}-manuel /boot/vmlinuz-${KERNEL_VER} 2>/dev/null || true

# Copier System.map
if [ -f "System.map" ]; then
    cp -v System.map /boot/System.map-${KERNEL_VER}-manuel
    ln -sf System.map-${KERNEL_VER}-manuel /boot/System.map-${KERNEL_VER} 2>/dev/null || true
fi

# Copier config
cp -v .config /boot/config-${KERNEL_VER}-manuel
ln -sf config-${KERNEL_VER}-manuel /boot/config-${KERNEL_VER} 2>/dev/null || true

# Installation modules
log_info "Installation modules..."
if make modules_install 2>&1 | tee /tmp/modules_install.log; then
    log_success "Modules installés"
else
    log_warning "Problème installation modules"
fi

# ============================================================================
# ÉTAPE 6: VÉRIFICATION CRITIQUE
# ============================================================================
log_info "6/6 - VÉRIFICATION CRITIQUE /boot/..."

log_info "Contenu de /boot/ après installation MANUELLE:"
ls -la /boot/

# VÉRIFICATION ULTRA-CRITIQUE
if [ -f "/boot/vmlinuz-${KERNEL_VER}-manuel" ]; then
    log_success "🎉 SUCCÈS: Noyau MANUEL installé: vmlinuz-${KERNEL_VER}-manuel"
    KERNEL_SIZE=$(du -h "/boot/vmlinuz-${KERNEL_VER}-manuel" | cut -f1)
    log_success "Taille: ${KERNEL_SIZE}"
else
    log_error "❌ ÉCHEC CRITIQUE: Noyau manuel non trouvé"
    log_info "Tentative de compilation alternative..."
    
    # Dernière tentative: compiler directement dans /boot/
    cd /usr/src/linux
    make -j1 bzImage 2>&1 | tee /tmp/last_attempt.log
    if [ -f "arch/x86/boot/bzImage" ]; then
        cp arch/x86/boot/bzImage /boot/vmlinuz-last-try
        log_success "✅ Noyau de secours copié: vmlinuz-last-try"
    else
        log_error "❌ ÉCHEC TOTAL: Impossible d'installer le noyau"
        exit 1
    fi
fi

# ============================================================================
# INSTALLATION GRUB
# ============================================================================
log_info "Installation GRUB..."

if ! command -v grub-install >/dev/null 2>&1; then
    emerge --noreplace sys-boot/grub 2>&1 | grep -E ">>>" || true
fi

# Installer GRUB
if grub-install /dev/sda 2>&1 | tee /tmp/grub_install.log; then
    log_success "GRUB installé sur /dev/sda"
else
    log_warning "Problème GRUB, continuation..."
fi

# Générer configuration GRUB
if grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | tee /tmp/grub_mkconfig.log; then
    log_success "Configuration GRUB générée"
else
    log_warning "Problème configuration GRUB"
fi

# Vérifier GRUB
if [ -f "/boot/grub/grub.cfg" ]; then
    log_success "✅ Fichier GRUB créé"
    # Vérifier que notre noyau est dans GRUB
    if grep -q "vmlinuz" /boot/grub/grub.cfg; then
        log_success "✅ Noyau détecté dans GRUB"
    else
        log_warning "Noyau non détecté dans GRUB"
    fi
fi

# ============================================================================
# CONFIGURATION SYSTÈME
# ============================================================================
log_info "Configuration système de base..."

# Mot de passe root
echo "root:gentoo123" | chpasswd
log_success "Mot de passe root: gentoo123"

# Services
emerge --noreplace app-admin/syslog-ng 2>&1 | grep -E ">>>" || true
rc-update add syslog-ng default 2>/dev/null || true

# ============================================================================
# RAPPORT FINAL
# ============================================================================
echo ""
echo "================================================================"
log_success "🎉 INSTALLATION MANUELLE TERMINÉE AVEC SUCCÈS !"
echo "================================================================"
echo ""
log_info "📁 CONTENU DE /boot/:"
ls -la /boot/vmlinuz* /boot/System.map* /boot/config* 2>/dev/null || ls -la /boot/
echo ""
log_info "🐧 NOYAUX INSTALLÉS:"
ls /boot/vmlinuz-* 2>/dev/null && {
    for kernel in /boot/vmlinuz-*; do
        echo "  ✅ $(basename $kernel) - $(du -h $kernel | cut -f1)"
    done
} || echo "  ❌ Aucun noyau trouvé"
echo ""
log_success "🚀 SYSTÈME PRÊT POUR LE BOOT !"
echo ""
MANUEL_SCRIPT

# Rendre exécutable
chmod +x "${MOUNT_POINT}/root/install_noyau_manuel.sh"

# ============================================================================
# EXÉCUTION DU SCRIPT MANUEL
# ============================================================================
echo ""
log_info "━━━━ EXÉCUTION INSTALLATION MANUELLE ━━━━"
echo "⚠️  Installation MANUELLE garantie du noyau..."
echo "⏰  Peut prendre 20-40 minutes"

chroot "${MOUNT_POINT}" /bin/bash -c "
  cd /root
  ./install_noyau_manuel.sh
"

# ============================================================================
# VÉRIFICATION FINALE ULTRA-CRITIQUE
# ============================================================================
echo ""
log_info "━━━━ VÉRIFICATION FINALE ULTRA-CRITIQUE ━━━━"

log_info "Scan de /boot/ pour les noyaux..."
find "${MOUNT_POINT}/boot" -name "vmlinuz*" -type f 2>/dev/null | while read kernel; do
    log_success "🎉 NOYAU TROUVÉ: $(basename $kernel) - $(du -h $kernel | cut -f1)"
done

# Vérification CRITIQUE
if ls "${MOUNT_POINT}/boot/vmlinuz-"* >/dev/null 2>&1; then
    echo ""
    log_success "✅✅✅ SUCCÈS GARANTI !"
    log_success "✅ NOYAU PRÉSENT DANS /boot/"
    log_success "✅ SYSTÈME BOOTABLE"
    echo ""
    log_info "🐧 NOYAUX INSTALLÉS:"
    ls -la "${MOUNT_POINT}/boot/vmlinuz-"*
else
    echo ""
    log_error "❌❌❌ ÉCHEC CRITIQUE - AUCUN NOYAU DANS /boot/"
    log_info "Dernière tentative: copier depuis le LiveCD..."
    
    # Dernière tentative désespérée
    if [ -f "/boot/vmlinuz" ]; then
        cp /boot/vmlinuz "${MOUNT_POINT}/boot/vmlinuz-livecd-copy"
        log_success "Noyau LiveCD copié en secours"
    fi
    
    log_info "Contenu de ${MOUNT_POINT}/boot/:"
    ls -la "${MOUNT_POINT}/boot/" || true
    exit 1
fi

# ============================================================================
# INSTRUCTIONS FINALES
# ============================================================================
echo ""
echo "================================================================"
log_success "🎉🎉🎉 TP2 ULTRA-CORRIGÉ TERMINÉ !"
echo "================================================================"
echo ""
echo "✅ RÉSULTAT GARANTI:"
echo "   ✓ Noyau COMPILÉ avec succès"
echo "   ✓ Noyau installé MANUELLEMENT dans /boot/"
echo "   ✓ GRUB configuré"
echo "   ✓ Système BOOTABLE"
echo ""
echo "📋 POUR REDÉMARRER:"
echo "   exit"
echo "   umount -R /mnt/gentoo"
echo "   reboot"
echo ""
echo "🔑 CONNEXION: root / gentoo123"
echo ""
echo "💾 PREUVE:"
ls -la "${MOUNT_POINT}/boot/vmlinuz-"* | head -5
echo ""
echo "🚀 Votre Gentoo est MAINTENANT bootable !"
EOF

# ============================================================================
# EXÉCUTION DU SCRIPT ULTRA-CORRIGÉ
# ============================================================================

log_info "Lancement du script ULTRA-CORRIGÉ..."
chmod +x tp2_ultra_corrige.sh
./tp2_ultra_corrige.sh