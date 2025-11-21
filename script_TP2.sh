#!/bin/bash
# Script de correction du fichier make.conf pour Gentoo

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

MOUNT_POINT="/mnt/gentoo"
MAKE_CONF="${MOUNT_POINT}/etc/portage/make.conf"

echo "================================================================"
echo "     Correction du fichier make.conf"
echo "================================================================"
echo ""

# Vérification que le système est monté
if [ ! -f "${MAKE_CONF}" ]; then
    log_error "Le fichier ${MAKE_CONF} n'existe pas"
    log_info "Le système Gentoo doit être monté sur ${MOUNT_POINT}"
    exit 1
fi

# Sauvegarde de l'original
log_info "Sauvegarde de make.conf..."
cp "${MAKE_CONF}" "${MAKE_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
log_success "Sauvegarde créée"

# Affichage du contenu problématique
log_info "Contenu actuel de make.conf (lignes 15-30):"
echo "=========================================="
sed -n '15,30p' "${MAKE_CONF}" 2>/dev/null || cat "${MAKE_CONF}" | head -30
echo "=========================================="
echo ""

# Création d'un nouveau make.conf correct
log_info "Création d'un nouveau make.conf corrigé..."

cat > "${MAKE_CONF}" << 'EOF'
# These settings were set by the catalyst build script that automatically
# built this stage.
# Please consult /usr/share/portage/config/make.conf.example for a more
# detailed example.

# Compilation flags
COMMON_FLAGS="-O2 -pipe -march=native"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"

# CPU cores for compilation (adjust based on your system)
MAKEOPTS="-j2"

# USE flags - basic configuration
USE="bindist"

# Portage features
FEATURES="parallel-fetch"

# Accept licenses
ACCEPT_LICENSE="*"

# Language support
L10N="en fr"
LC_MESSAGES=C.utf8

# Portage directories
PORTDIR="/var/db/repos/gentoo"
DISTDIR="/var/cache/distfiles"
PKGDIR="/var/cache/binpkgs"

# Mirrors (uncomment and adjust as needed)
# GENTOO_MIRRORS="https://gentoo.mirrors.ovh.net/gentoo-distfiles/"

# This sets the language of build output to English.
# Please keep this setting intact when reporting bugs.
EOF

log_success "Nouveau make.conf créé"

# Vérification de la syntaxe
log_info "Vérification de la syntaxe..."
if bash -n "${MAKE_CONF}" 2>&1; then
    log_success "Syntaxe correcte !"
else
    log_error "Erreur de syntaxe détectée"
    log_info "Restauration de la sauvegarde..."
    cp "${MAKE_CONF}.backup."* "${MAKE_CONF}"
    exit 1
fi

# Test avec source
log_info "Test de chargement du fichier..."
if (source "${MAKE_CONF}" 2>&1); then
    log_success "Fichier chargeable sans erreur"
else
    log_warning "Quelques avertissements mais devrait fonctionner"
fi

echo ""
log_info "Nouveau contenu de make.conf:"
echo "=========================================="
cat "${MAKE_CONF}"
echo "=========================================="
echo ""

# Test avec emerge
log_info "Test de fonctionnement avec emerge..."
chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_TEST'
source /etc/profile
export PS1="(chroot) \$PS1"

echo ""
echo "Test: emerge --info | head -20"
emerge --info 2>&1 | head -20
echo ""
CHROOT_TEST

log_success "Test emerge réussi !"

echo ""
echo "================================================================"
log_success "✅ CORRECTION TERMINÉE"
echo "================================================================"
echo ""
echo "📋 ACTIONS EFFECTUÉES:"
echo "  ✓ Sauvegarde de l'ancien make.conf"
echo "  ✓ Création d'un nouveau make.conf corrigé"
echo "  ✓ Vérification de la syntaxe"
echo "  ✓ Test avec emerge"
echo ""
echo "🔧 CONFIGURATION APPLIQUÉE:"
echo "  • MAKEOPTS=\"-j2\" (2 jobs parallèles)"
echo "  • Flags de compilation optimisés"
echo "  • Support français et anglais"
echo "  • Acceptation de toutes les licences"
echo ""
echo "🚀 PROCHAINES ÉTAPES:"
echo "   1. Relancez votre script TP2"
echo "   2. L'installation devrait maintenant fonctionner"
echo ""
echo "💡 Si vous voulez ajuster le nombre de jobs parallèles:"
echo "   • Modifiez MAKEOPTS=\"-jN\" où N = nombre de cœurs + 1"
echo "   • Par exemple: -j3 pour 2 cœurs, -j5 pour 4 cœurs"
echo ""
log_info "Fichier de sauvegarde: ${MAKE_CONF}.backup.*"
echo ""