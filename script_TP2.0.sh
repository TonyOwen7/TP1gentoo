#!/bin/bash
# Correction du profil systemd inexistant vers OpenRC

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

MOUNT_POINT="/mnt/gentoo"

echo "================================================================"
echo "     Correction du profil systemd inexistant"
echo "================================================================"
echo ""

# Fonction de correction
fix_profile_in_chroot() {
    chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_FIX'
#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

source /etc/profile 2>/dev/null || true
export PS1="(chroot) \$PS1"

echo ""
log_info "Diagnostic du problème..."

# Afficher le profil actuel (cassé)
if [ -L "/etc/portage/make.profile" ]; then
    CURRENT=$(readlink /etc/portage/make.profile)
    echo "  Profil actuel (CASSÉ): ${CURRENT}"
    
    if [ ! -d "${CURRENT}" ]; then
        log_error "Ce répertoire n'existe pas !"
    fi
fi

echo ""
log_info "Recherche des profils disponibles..."

# Lister les profils disponibles
echo "  Profils dans /var/db/repos/gentoo/profiles/default/linux/amd64/:"
if [ -d "/var/db/repos/gentoo/profiles/default/linux/amd64" ]; then
    ls -1 /var/db/repos/gentoo/profiles/default/linux/amd64/ 2>/dev/null | grep -E "^[0-9]" | sort -V
else
    log_error "Le dépôt Gentoo n'est pas présent !"
    exit 1
fi

echo ""
log_info "Sélection d'un profil OpenRC approprié..."

# Recherche du meilleur profil OpenRC disponible
PROFILE_PATH=""

# Ordre de priorité des profils
for VERSION in 23.0 17.1 17.0 13.0; do
    if [ -d "/var/db/repos/gentoo/profiles/default/linux/amd64/${VERSION}" ]; then
        PROFILE_PATH="/var/db/repos/gentoo/profiles/default/linux/amd64/${VERSION}"
        PROFILE_NAME="default/linux/amd64/${VERSION}"
        break
    fi
done

if [ -z "${PROFILE_PATH}" ]; then
    log_error "Aucun profil OpenRC trouvé !"
    echo ""
    echo "Profils disponibles:"
    find /var/db/repos/gentoo/profiles/default/linux/amd64/ -maxdepth 1 -type d
    exit 1
fi

echo "  ✓ Profil trouvé: ${PROFILE_NAME}"

# Suppression de l'ancien lien cassé
log_info "Suppression de l'ancien lien cassé..."
rm -f /etc/portage/make.profile

# Création du nouveau lien vers OpenRC
log_info "Création du lien vers le profil OpenRC..."
ln -sf "${PROFILE_PATH}" /etc/portage/make.profile

log_success "Nouveau profil configuré: ${PROFILE_NAME}"

# Vérification
echo ""
log_info "Vérification du nouveau profil..."
if [ -d "/etc/portage/make.profile" ]; then
    ACTUAL_PATH=$(readlink /etc/portage/make.profile)
    echo "  Lien: ${ACTUAL_PATH}"
    
    if [ -d "${ACTUAL_PATH}" ]; then
        log_success "Le profil est VALIDE !"
    else
        log_error "Le profil est toujours invalide"
        exit 1
    fi
else
    log_error "Le lien n'a pas été créé correctement"
    exit 1
fi

# Test avec eselect
echo ""
log_info "Affichage du profil sélectionné..."
if command -v eselect >/dev/null 2>&1; then
    eselect profile show
else
    echo "  $(readlink /etc/portage/make.profile)"
fi

# Test avec emerge
echo ""
log_info "Test avec emerge --info..."
if emerge --info 2>&1 | head -10; then
    log_success "emerge fonctionne correctement !"
else
    log_error "emerge a encore des problèmes"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
log_success "PROFIL CORRIGÉ DE SYSTEMD VERS OPENRC !"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "AVANT: default/linux/amd64/23.0/systemd (INEXISTANT)"
echo "APRÈS: ${PROFILE_NAME} (OpenRC - VALIDE)"
echo ""

CHROOT_FIX
}

# Vérifier que le système est monté
if [ ! -d "${MOUNT_POINT}/etc/portage" ]; then
    log_error "Le système Gentoo n'est pas monté sur ${MOUNT_POINT}"
    log_info "Montage du système..."
    
    mkdir -p "${MOUNT_POINT}"
    mount /dev/sda3 "${MOUNT_POINT}" || {
        log_error "Impossible de monter le système"
        exit 1
    }
fi

# Montage des systèmes virtuels
log_info "Montage des systèmes virtuels..."
mount -t proc /proc "${MOUNT_POINT}/proc" 2>/dev/null || true
mount --rbind /sys "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --rbind /dev "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --bind /run "${MOUNT_POINT}/run" 2>/dev/null || true

cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/" 2>/dev/null || true

# Exécuter la correction
fix_profile_in_chroot

echo ""
echo "================================================================"
log_success "✅ CORRECTION TERMINÉE !"
echo "================================================================"
echo ""
echo "📋 CE QUI A ÉTÉ FAIT:"
echo "  ✓ Ancien profil systemd supprimé"
echo "  ✓ Nouveau profil OpenRC configuré"
echo "  ✓ Profil validé et fonctionnel"
echo ""
echo "🚀 PROCHAINE ÉTAPE:"
echo "  Vous pouvez maintenant relancer le script TP2 complet"
echo ""
log_info "Le système utilise maintenant OpenRC au lieu de systemd"
echo ""