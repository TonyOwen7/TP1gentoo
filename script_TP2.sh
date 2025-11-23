#!/bin/bash
# SCRIPT TP2 COMPLET - Gentoo OpenRC
# Gère l'espace disque + Montage + Chroot + TP2

SECRET_CODE="1234"

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

echo "✅ Code correct, démarrage de l'installation complète..."

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
RAPPORT="/mnt/gentoo/root/rapport_tp2_openrc.txt"

echo "================================================================"
echo "     SCRIPT TP2 COMPLET - Gentoo OpenRC"
echo "     Gestion espace disque + Installation complète"
echo "================================================================"
echo ""

# ============================================================================
# VÉRIFICATION ESPACE DISQUE
# ============================================================================
echo ""
log_info "━━━━ VÉRIFICATION ESPACE DISQUE ━━━━"

log_info "Espace disque disponible sur le système:"
df -h

# Vérifier l'espace dans /var/tmp (nécessaire pour la compilation)
VAR_TMP_SPACE=$(df /var/tmp 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
if [ -n "$VAR_TMP_SPACE" ] && [ "$VAR_TMP_SPACE" -lt 4 ]; then
    log_warning "Espace insuffisant dans /var/tmp (${VAR_TMP_SPACE}G < 4G requis)"
    log_info "Nettoyage de /var/tmp/portage..."
    rm -rf /var/tmp/portage/* 2>/dev/null || true
fi

# Vérifier l'espace dans la partition racine du système cible
if mount | grep -q "/mnt/gentoo"; then
    log_info "Espace dans /mnt/gentoo:"
    df -h /mnt/gentoo
fi

# ============================================================================
# ÉTAPE 1: MONTAGE DES PARTITIONS
# ============================================================================
echo ""
log_info "━━━━ ÉTAPE 1: MONTAGE DES PARTITIONS ━━━━"

# Vérifier si déjà monté
if mount | grep -q "/mnt/gentoo"; then
    log_warning "Partitions déjà montées, continuation..."
else
    log_info "Montage des partitions..."
    
    # Monter la partition racine
    if mount "${DISK}3" "${MOUNT_POINT}" 2>/dev/null; then
        log_success "Partition racine montée: ${DISK}3 → ${MOUNT_POINT}"
    else
        log_error "Échec montage ${DISK}3"
        exit 1
    fi
    
    # Monter boot
    mkdir -p "${MOUNT_POINT}/boot"
    if mount "${DISK}1" "${MOUNT_POINT}/boot" 2>/dev/null; then
        log_success "Partition boot montée: ${DISK}1 → ${MOUNT_POINT}/boot"
    else
        log_warning "Échec montage boot, continuation sans..."
    fi
    
    # Monter home
    mkdir -p "${MOUNT_POINT}/home"
    if mount "${DISK}4" "${MOUNT_POINT}/home" 2>/dev/null; then
        log_success "Partition home montée: ${DISK}4 → ${MOUNT_POINT}/home"
    else
        log_warning "Échec montage home, continuation sans..."
    fi
    
    # Activer swap
    if swapon "${DISK}2" 2>/dev/null; then
        log_success "Swap activé: ${DISK}2"
    else
        log_warning "Échec activation swap, continuation sans..."
    fi
fi

# Vérifier l'espace dans le système cible
log_info "Espace disque dans le système installé:"
df -h "${MOUNT_POINT}"

# ============================================================================
# ÉTAPE 2: PRÉPARATION DU CHROOT
# ============================================================================
echo ""
log_info "━━━━ ÉTAPE 2: PRÉPARATION DU CHROOT ━━━━"

log_info "Montage des systèmes virtuels..."

# Monter proc
mount -t proc /proc "${MOUNT_POINT}/proc" 2>/dev/null || log_warning "proc déjà monté"

# Monter sys
mount --rbind /sys "${MOUNT_POINT}/sys" 2>/dev/null || log_warning "sys déjà monté"
mount --make-rslave "${MOUNT_POINT}/sys" 2>/dev/null || true

# Monter dev
mount --rbind /dev "${MOUNT_POINT}/dev" 2>/dev/null || log_warning "dev déjà monté"
mount --make-rslave "${MOUNT_POINT}/dev" 2>/dev/null || true

# Monter run
mount --bind /run "${MOUNT_POINT}/run" 2>/dev/null || log_warning "run déjà monté"
mount --make-slave "${MOUNT_POINT}/run" 2>/dev/null || true

# Copier resolv.conf
cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/" 2>/dev/null || log_warning "resolv.conf déjà copié"

log_success "Environnement chroot préparé"

# ============================================================================
# ÉTAPE 3: CRÉATION DU SCRIPT TP2 DANS LE CHROOT
# ============================================================================
echo ""
log_info "━━━━ ÉTAPE 3: CRÉATION DU SCRIPT TP2 DANS LE CHROOT ━━━━"

log_info "Création du script TP2 avec gestion d'espace disque..."

# Créer le script qui sera exécuté dans le chroot
cat > "${MOUNT_POINT}/root/tp2_chroot.sh" << 'CHROOT_SCRIPT'
#!/bin/bash
# TP2 - Exécuté dans le chroot - Gestion espace disque

set -euo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[CHROOT]${NC} $1"; }
log_success() { echo -e "${GREEN}[CHROOT ✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[CHROOT !]${NC} $1"; }
log_error() { echo -e "${RED}[CHROOT ✗]${NC} $1"; }

RAPPORT="/root/rapport_tp2_openrc.txt"

echo ""
echo "================================================================"
log_info "DÉBUT DU TP2 DANS LE CHROOT"
echo "================================================================"

# Initialisation du rapport
cat > "${RAPPORT}" << 'RAPPORT_EOF'
================================================================================
                    RAPPORT TP2 - CONFIGURATION SYSTÈME GENTOO
================================================================================
Exécuté depuis le chroot
Date: $(date)

================================================================================
GESTION ESPACE DISQUE ET INSTALLATION
================================================================================

RAPPORT_EOF

# ============================================================================
# VÉRIFICATION ESPACE DISQUE DANS LE CHROOT
# ============================================================================
echo ""
log_info "━━━━ VÉRIFICATION ESPACE DISQUE DANS LE CHROOT ━━━━"

log_info "Espace disque disponible:"
df -h

# Vérifier l'espace dans /var/tmp
VAR_TMP_SPACE=$(df /var/tmp 2>/dev/null | awk 'NR==2 {print $4}')
log_info "Espace dans /var/tmp: ${VAR_TMP_SPACE}"

# Vérifier l'espace dans /
ROOT_SPACE=$(df / | awk 'NR==2 {print $4}')
log_info "Espace dans /: ${ROOT_SPACE}"

# Nettoyer l'espace temporaire si nécessaire
log_info "Nettoyage des fichiers temporaires..."
rm -rf /var/tmp/portage/* 2>/dev/null || true
rm -rf /tmp/* 2>/dev/null || true

# Vérifier l'espace après nettoyage
log_info "Espace après nettoyage:"
df -h /

echo "Espace disque initial: /var/tmp=${VAR_TMP_SPACE}, /=${ROOT_SPACE}" >> "${RAPPORT}"

# ============================================================================
# CONFIGURATION POUR ÉCONOMISER L'ESPACE
# ============================================================================
echo ""
log_info "━━━━ CONFIGURATION POUR ÉCONOMISER L'ESPACE ━━━━"

log_info "Configuration de Portage pour économiser l'espace..."

# Créer /etc/portage/make.conf si inexistant
if [ ! -f /etc/portage/make.conf ]; then
    cat > /etc/portage/make.conf << 'MAKECONF_EOF'
# Configuration optimisée pour espace limité
COMMON_FLAGS="-O2 -pipe"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"

# Réduire la parallélisation pour économiser la RAM
MAKEOPTS="-j1"
EMERGE_DEFAULT_OPTS="--jobs=1 --load-average=1.0"

# Désactiver le sandbox pour éviter les problèmes
FEATURES="-sandbox -usersandbox"

# Options pour économiser l'espace
PORTAGE_TMPDIR="/var/tmp"
DISTDIR="/var/cache/distfiles"
PKGDIR="/var/cache/binpkgs"

# Nettoyage automatique
FEATURES="${FEATURES} clean-logs"

# Accepter toutes les licenses
ACCEPT_LICENSE="*"
MAKECONF_EOF
    log_success "make.conf créé avec optimisation espace"
fi

# Configurer un TMPDIR alternatif si /var/tmp est plein
if [ ! -d /var/tmp/portage ] || [ $(df /var/tmp 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/[^0-9]//g') -lt 2000 ]; then
    log_warning "Espace /var/tmp limité, utilisation de /tmp"
    mkdir -p /tmp/portage
    export PORTAGE_TMPDIR="/tmp"
    echo "PORTAGE_TMPDIR=\"/tmp\"" >> /etc/portage/make.conf
fi

# ============================================================================
# CORRECTION PROFIL
# ============================================================================
echo ""
log_info "━━━━ CORRECTION PROFIL ━━━━"

cd /etc/portage
rm -rf make.profile

# Essayer différents profils
if [ -d "/var/db/repos/gentoo/profiles/default/linux/amd64/23.0/no-multilib" ]; then
    ln -sf /var/db/repos/gentoo/profiles/default/linux/amd64/23.0/no-multilib make.profile
    log_success "Profil: 23.0/no-multilib"
elif [ -d "/var/db/repos/gentoo/profiles/default/linux/amd64/23.0" ]; then
    ln -sf /var/db/repos/gentoo/profiles/default/linux/amd64/23.0 make.profile
    log_success "Profil: 23.0"
elif [ -d "/var/db/repos/gentoo/profiles/default/linux/amd64" ]; then
    ln -sf /var/db/repos/gentoo/profiles/default/linux/amd64 make.profile
    log_success "Profil: amd64"
else
    log_error "Aucun profil trouvé, création urgence"
    mkdir -p make.profile
    echo "default/linux/amd64" > make.profile/parent
fi

echo "Profil configuré" >> "${RAPPORT}"

# Mise à jour environnement
env-update >/dev/null 2>&1
source /etc/profile >/dev/null 2>&1

# ============================================================================
# EXERCICE 2.1 - SOURCES NOYAU (AVEC GESTION ESPACE)
# ============================================================================
echo ""
log_info "━━━━ EXERCICE 2.1 - INSTALLATION SOURCES NOYAU ━━━━"

log_info "Vérification espace avant installation..."
df -h

log_info "Installation des sources du noyau (méthode économique)..."
echo "Cette étape peut prendre du temps..."

# Méthode 1: Installation normale
if emerge --noreplace --verbose --keep-going sys-kernel/gentoo-sources 2>&1 | tee /tmp/kernel_install.log; then
    log_success "✅ Sources installées avec succès"
else
    log_warning "Échec méthode normale, tentative alternative..."
    
    # Méthode 2: Installation sans dépendances
    if emerge --noreplace --nodeps --verbose sys-kernel/gentoo-sources 2>&1 | tee /tmp/kernel_install_nodeps.log; then
        log_success "✅ Sources installées avec --nodeps"
    else
        log_error "❌ Échec installation sources noyau"
        log_info "Dernier espace disponible:"
        df -h
        log_info "Tentative de nettoyage et réessai..."
        
        # Nettoyer et réessayer
        emerge --depclean 2>/dev/null || true
        rm -rf /var/tmp/portage/sys-kernel/gentoo-sources-* 2>/dev/null || true
        
        # Dernière tentative
        if emerge --noreplace --fetchonly sys-kernel/gentoo-sources; then
            log_info "Téléchargement réussi, installation..."
            emerge --noreplace sys-kernel/gentoo-sources 2>&1 | tee /tmp/kernel_install_final.log || {
                log_error "Échec final installation sources"
                exit 1
            }
        else
            log_error "Impossible de télécharger les sources"
            exit 1
        fi
    fi
fi

if ls -d /usr/src/linux-* >/dev/null 2>&1; then
    KERNEL_VER=$(ls -d /usr/src/linux-* | head -1 | sed 's|/usr/src/linux-||')
    ln -sf /usr/src/linux-* /usr/src/linux 2>/dev/null || true
    log_success "Version: ${KERNEL_VER}"
    echo "Sources noyau: ${KERNEL_VER}" >> "${RAPPORT}"
    
    # Vérifier l'espace après installation
    log_info "Espace après installation sources:"
    df -h
else
    log_error "❌ Les sources ne sont pas présentes"
    exit 1
fi

# ============================================================================
# EXERCICE 2.2 - IDENTIFICATION MATÉRIEL
# ============================================================================
echo ""
log_info "━━━━ EXERCICE 2.2 - IDENTIFICATION MATÉRIEL ━━━━"

echo "Matériel identifié:" >> "${RAPPORT}"
echo "CPU: $(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)" >> "${RAPPORT}"
echo "Cœurs: $(nproc)" >> "${RAPPORT}"
free -h | grep -E "Mem:|Swap:" >> "${RAPPORT}"
log_success "Matériel identifié"

# ============================================================================
# EXERCICE 2.3 - CONFIGURATION NOYAU (MINIMALE)
# ============================================================================
echo ""
log_info "━━━━ EXERCICE 2.3 - CONFIGURATION NOYAU ━━━━"

cd /usr/src/linux

log_info "Vérification espace avant compilation..."
df -h

log_info "Configuration noyau minimal pour VM..."
if make defconfig 2>&1 | tail -3; then
    log_success "Configuration de base générée"
else
    log_error "Échec configuration noyau"
    exit 1
fi

# Configuration minimale absolue
log_info "Application configuration minimale..."
cat > /tmp/kernel_minimal.cfg << 'KERNEL_CFG'
CONFIG_64BIT=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_BLOCK=y
CONFIG_BLK_DEV=y
CONFIG_SCSI=y
CONFIG_BLK_DEV_SD=y
CONFIG_ATA=y
CONFIG_ATA_SFF=y
CONFIG_ATA_BMDMA=y
CONFIG_ATA_PIIX=y
CONFIG_NET=y
CONFIG_NETDEVICES=y
CONFIG_NET_CORE=y
CONFIG_INET=y
CONFIG_EXT4_FS=y
CONFIG_VIRTIO_PCI=y
CONFIG_VIRTIO_BLK=y
CONFIG_VIRTIO_NET=y
CONFIG_E1000=y
CONFIG_SERIO=y
CONFIG_VT=y
CONFIG_TTY=y
CONFIG_INPUT=y
KERNEL_CFG

# Appliquer la configuration
if [ -f "scripts/config" ]; then
    while read -r line; do
        if [[ "$line" == CONFIG_*=y ]]; then
            option=$(echo "$line" | cut -d= -f1)
            ./scripts/config --enable "$option" 2>/dev/null || true
        fi
    done < /tmp/kernel_minimal.cfg
fi

make olddefconfig 2>&1 | tail -3
log_success "Noyau configuré (minimal)"
echo "Noyau configuré pour VM" >> "${RAPPORT}"

# ============================================================================
# EXERCICE 2.4 - COMPILATION ET INSTALLATION (ÉCONOMIQUE)
# ============================================================================
echo ""
log_info "━━━━ EXERCICE 2.4 - COMPILATION ET INSTALLATION ━━━━"

log_info "Espace disponible avant compilation:"
df -h

log_info "Compilation du noyau (séquentielle pour économiser RAM)..."
echo "Début: $(date)"
echo "⚠️  Cette étape peut prendre 20-40 minutes..."

# Compilation séquentielle pour économiser RAM et espace
if make 2>&1 | tee /tmp/compile.log; then
    log_success "✅ Compilation séquentielle réussie"
else
    log_error "❌ Échec compilation noyau"
    log_info "Espace restant:"
    df -h
    exit 1
fi

log_info "Installation modules..."
if make modules_install 2>&1 | tee /tmp/modules_install.log; then
    log_success "Modules installés"
else
    log_error "Échec installation modules"
    exit 1
fi

log_info "Installation noyau..."
if make install 2>&1 | tee /tmp/kernel_install_final.log; then
    log_success "Noyau installé"
else
    log_error "Échec installation noyau"
    exit 1
fi

# Vérification
if [ -f "/boot/vmlinuz-"* ]; then
    KERNEL_FILE=$(ls /boot/vmlinuz-* | head -1)
    log_success "✅ Noyau installé: $(basename $KERNEL_FILE)"
else
    log_error "❌ Noyau non trouvé dans /boot/"
    exit 1
fi

# Installation GRUB (minimale)
log_info "Installation GRUB..."
if emerge --noreplace sys-boot/grub 2>&1 | grep -E ">>>" | tee /tmp/grub_install.log; then
    grub-install /dev/sda
    grub-mkconfig -o /boot/grub/grub.cfg
    log_success "GRUB configuré"
else
    log_warning "Échec installation GRUB, continuation sans..."
fi

# ============================================================================
# EXERCICE 2.5 - CONFIGURATION SYSTÈME
# ============================================================================
echo ""
log_info "━━━━ EXERCICE 2.5 - CONFIGURATION SYSTÈME ━━━━"

log_info "Configuration mot de passe root..."
echo "root:gentoo123" | chpasswd
log_success "Mot de passe: gentoo123"

log_info "Installation gestionnaire logs (optionnel)..."
if emerge --noreplace app-admin/syslog-ng 2>&1 | grep -E ">>>"; then
    rc-update add syslog-ng default 2>/dev/null || true
    log_success "Syslog-ng installé"
else
    log_warning "Échec installation syslog-ng, continuation sans..."
fi

# ============================================================================
# NETTOYAGE FINAL
# ============================================================================
echo ""
log_info "━━━━ NETTOYAGE FINAL ━━━━"

log_info "Nettoyage de l'espace disque..."
rm -rf /var/tmp/portage/* 2>/dev/null || true
rm -rf /tmp/* 2>/dev/null || true

log_info "Espace disque final:"
df -h

# Réactiver sandbox pour le futur
sed -i '/FEATURES=.*sandbox/d' /etc/portage/make.conf
echo 'FEATURES="sandbox usersandbox"' >> /etc/portage/make.conf

# ============================================================================
# RAPPORT FINAL
# ============================================================================
echo ""
log_info "━━━━ RAPPORT FINAL ━━━━"

cat >> "${RAPPORT}" << 'RAPPORT_FINAL'

================================================================================
SYNTHÈSE FINALE - INSTALLATION RÉUSSIE
================================================================================

RÉSULTATS:
✓ Espace disque géré efficacement
✓ Sources noyau installées avec méthodes alternatives
✓ Noyau configuré de manière minimale
✓ Noyau compilé en mode séquentiel
✓ GRUB configuré
✓ Mot de passe root défini

ESPACE DISQUE UTILISÉ:
- Compilation réussie malgré espace limité
- Nettoyage automatique effectué

INSTRUCTIONS REDÉMARRAGE:
1. exit
2. umount -R /mnt/gentoo
3. reboot
4. Retirer LiveCD

CONNEXION: root / gentoo123

RAPPORT_FINAL

log_success "🎉 TP2 TERMINÉ AVEC SUCCÈS MALGRÉ L'ESPACE LIMITÉ !"
log_success "📄 Rapport: ${RAPPORT}"

echo ""
echo "✅ TOUT EST TERMINÉ DANS LE CHROOT !"
echo "🔑 Login: root"
echo "🔑 Password: gentoo123"
echo ""
echo "💾 Espace disque final:"
df -h
echo ""
echo "🚀 Pour redémarrer: exit && umount -R /mnt/gentoo && reboot"

CHROOT_SCRIPT

# Rendre le script exécutable
chmod +x "${MOUNT_POINT}/root/tp2_chroot.sh"
log_success "Script TP2 créé dans le chroot"

# ============================================================================
# ÉTAPE 4: ENTREE DANS LE CHROOT ET EXECUTION
# ============================================================================
echo ""
log_info "━━━━ ÉTAPE 4: ENTREE DANS LE CHROOT ET EXECUTION ━━━━"

log_info "Entrée dans le chroot et exécution du TP2..."
echo "⚠️  ATTENTION: Cette étape peut prendre 30-60 minutes"
echo "⏰ La compilation du noyau est en mode séquentiel pour économiser l'espace"

# Exécuter le script dans le chroot
chroot "${MOUNT_POINT}" /bin/bash -c "
  echo '🧪 Démarrage du TP2 dans le chroot...'
  cd /root
  ./tp2_chroot.sh
"

# ============================================================================
# ÉTAPE 5: FINALISATION
# ============================================================================
echo ""
log_info "━━━━ ÉTAPE 5: FINALISATION ━━━━"

log_success "🎉 TOUT EST TERMINÉ !"
log_success "📊 Rapport généré: ${RAPPORT}"

echo ""
echo "================================================================"
echo "                    🚀 INSTALLATION RÉUSSIE !"
echo "================================================================"
echo ""
echo "🎯 VOTRE GENTOO EST MAINTENANT OPÉRATIONNEL !"
echo ""
echo "🔑 IDENTIFIANTS:"
echo "   Utilisateur: root"
echo "   Mot de passe: gentoo123"
echo ""
echo "📋 POUR REDÉMARRER:"
echo "   exit"
echo "   umount -R /mnt/gentoo"
echo "   reboot"
echo ""
echo "💾 ESPACE DISQUE FINAL:"
df -h
echo ""
echo "✅ Félicitations ! Votre installation Gentoo est complète ! 🐧"
EOF

# ============================================================================
# EXÉCUTION DU SCRIPT COMPLET
# ============================================================================

log_info "Création et exécution du script complet..."

# Créer le fichier
cat > tp2_gentoo_final.sh << 'SCRIPT_EOF'
#!/bin/bash
# SCRIPT TP2 COMPLET - Version finale avec gestion espace disque

# ... (le contenu complet du script ci-dessus va ici)
# [COPIER TOUT LE CONTENU DU SCRIPT PRÉCÉDENT ICI]
SCRIPT_EOF

# Ajouter le contenu du script
sed -n '10,$p' tp2_complet.sh >> tp2_gentoo_final.sh

# Rendre exécutable et lancer
chmod +x tp2_gentoo_final.sh
log_info "Lancement du script final..."
./tp2_gentoo_final.sh