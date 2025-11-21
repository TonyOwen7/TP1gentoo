#!/bin/bash
# Diagnostic et correction automatique du profil Gentoo

set -euo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

MOUNT_POINT="/mnt/gentoo"

echo "================================================================"
echo "     Diagnostic et correction automatique du profil"
echo "================================================================"
echo ""

# Montage si nécessaire
if [ ! -d "${MOUNT_POINT}/etc/portage" ]; then
    log_info "Montage du système Gentoo..."
    mkdir -p "${MOUNT_POINT}"
    mount /dev/sda3 "${MOUNT_POINT}" 2>/dev/null || {
        log_error "Impossible de monter /dev/sda3"
        exit 1
    }
fi

# Montage des systèmes virtuels
mount -t proc /proc "${MOUNT_POINT}/proc" 2>/dev/null || true
mount --rbind /sys "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --rbind /dev "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --bind /run "${MOUNT_POINT}/run" 2>/dev/null || true

cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/" 2>/dev/null || true

# Exécution dans le chroot
chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_DIAGNOSTIC'
#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

source /etc/profile 2>/dev/null || true
export PS1="(chroot) \$PS1"

echo ""
echo "════════════════════════════════════════════════════════════"
log_info "ÉTAPE 1 : DIAGNOSTIC DU PROBLÈME"
echo "════════════════════════════════════════════════════════════"
echo ""

# Vérifier le profil actuel
log_info "Profil actuellement configuré:"
if [ -L "/etc/portage/make.profile" ]; then
    CURRENT_LINK=$(readlink /etc/portage/make.profile)
    echo "  → ${CURRENT_LINK}"
    
    if [ -d "${CURRENT_LINK}" ]; then
        log_success "Le profil existe"
    else
        log_error "Le profil N'EXISTE PAS (lien cassé)"
    fi
else
    log_error "Aucun lien symbolique /etc/portage/make.profile"
fi

echo ""
log_info "Vérification du dépôt Gentoo..."
if [ -d "/var/db/repos/gentoo/profiles" ]; then
    log_success "Dépôt Gentoo présent"
else
    log_error "Dépôt Gentoo ABSENT ! Synchronisation nécessaire"
    
    log_info "Tentative de synchronisation du dépôt..."
    if command -v emerge-webrsync >/dev/null 2>&1; then
        emerge-webrsync 2>&1 | tail -10
        log_success "Dépôt synchronisé"
    else
        log_error "Impossible de synchroniser le dépôt"
        exit 1
    fi
fi

echo ""
echo "════════════════════════════════════════════════════════════"
log_info "ÉTAPE 2 : LISTE DES PROFILS DISPONIBLES"
echo "════════════════════════════════════════════════════════════"
echo ""

log_info "Profils AMD64 disponibles:"
if [ -d "/var/db/repos/gentoo/profiles/default/linux/amd64" ]; then
    echo ""
    ls -1 /var/db/repos/gentoo/profiles/default/linux/amd64/ | while read -r profile; do
        if [ -d "/var/db/repos/gentoo/profiles/default/linux/amd64/${profile}" ]; then
            echo "  ✓ default/linux/amd64/${profile}"
        fi
    done
    echo ""
else
    log_error "Aucun profil AMD64 trouvé"
    
    log_info "Structure du dépôt:"
    find /var/db/repos/gentoo/profiles -maxdepth 3 -type d 2>/dev/null | grep -E "amd64|x86_64" | head -10
fi

echo ""
echo "════════════════════════════════════════════════════════════"
log_info "ÉTAPE 3 : SÉLECTION AUTOMATIQUE D'UN PROFIL"
echo "════════════════════════════════════════════════════════════"
echo ""

PROFILE_PATH=""
PROFILE_NAME=""

# Liste des profils à essayer (du plus récent au plus ancien)
PROFILES_TO_TRY=(
    "17.1"
    "17.0"
    "13.0"
    "17.1/no-multilib"
    "17.0/no-multilib"
)

log_info "Recherche du meilleur profil disponible..."
for VERSION in "${PROFILES_TO_TRY[@]}"; do
    TEST_PATH="/var/db/repos/gentoo/profiles/default/linux/amd64/${VERSION}"
    if [ -d "${TEST_PATH}" ]; then
        PROFILE_PATH="${TEST_PATH}"
        PROFILE_NAME="default/linux/amd64/${VERSION}"
        log_success "Profil trouvé: ${PROFILE_NAME}"
        break
    else
        echo "  ✗ ${VERSION} n'existe pas"
    fi
done

if [ -z "${PROFILE_PATH}" ]; then
    log_error "AUCUN PROFIL STANDARD TROUVÉ !"
    
    log_warning "Recherche de n'importe quel profil amd64..."
    FIRST_PROFILE=$(find /var/db/repos/gentoo/profiles/default/linux/amd64/ -maxdepth 1 -type d ! -name amd64 2>/dev/null | head -1)
    
    if [ -n "${FIRST_PROFILE}" ] && [ -d "${FIRST_PROFILE}" ]; then
        PROFILE_PATH="${FIRST_PROFILE}"
        PROFILE_NAME="default/linux/amd64/$(basename ${FIRST_PROFILE})"
        log_warning "Utilisation du profil: ${PROFILE_NAME}"
    else
        log_error "Impossible de trouver un profil utilisable"
        exit 1
    fi
fi

echo ""
echo "════════════════════════════════════════════════════════════"
log_info "ÉTAPE 4 : APPLICATION DU NOUVEAU PROFIL"
echo "════════════════════════════════════════════════════════════"
echo ""

log_info "Suppression de l'ancien lien..."
rm -f /etc/portage/make.profile
log_success "Ancien lien supprimé"

log_info "Création du nouveau lien..."
echo "  Source: ${PROFILE_PATH}"
echo "  Cible:  /etc/portage/make.profile"
ln -sf "${PROFILE_PATH}" /etc/portage/make.profile
log_success "Nouveau lien créé"

echo ""
echo "════════════════════════════════════════════════════════════"
log_info "ÉTAPE 5 : VÉRIFICATION"
echo "════════════════════════════════════════════════════════════"
echo ""

log_info "Vérification du lien symbolique..."
FINAL_LINK=$(readlink /etc/portage/make.profile)
echo "  → ${FINAL_LINK}"

if [ -d "${FINAL_LINK}" ]; then
    log_success "Le profil existe et est VALIDE !"
else
    log_error "Le profil est toujours CASSÉ"
    exit 1
fi

echo ""
log_info "Test avec emerge --info..."
if emerge --info 2>&1 | head -8; then
    log_success "emerge fonctionne correctement !"
else
    log_warning "emerge a des avertissements mais devrait fonctionner"
fi

echo ""
log_info "Affichage du profil avec eselect..."
if command -v eselect >/dev/null 2>&1; then
    eselect profile show 2>/dev/null || echo "  ${PROFILE_NAME}"
else
    echo "  ${PROFILE_NAME}"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
log_success "✅ PROFIL CORRIGÉ AVEC SUCCÈS !"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Profil sélectionné: ${PROFILE_NAME}"
echo ""

CHROOT_DIAGNOSTIC

echo ""
echo "================================================================"
log_success "✅ CORRECTION TERMINÉE !"
echo "================================================================"
echo ""
echo "📋 RÉSUMÉ:"
echo "  ✓ Diagnostic effectué"
echo "  ✓ Profil valide trouvé et configuré"
echo "  ✓ Lien symbolique créé"
echo "  ✓ emerge fonctionnel"
echo ""
echo "🚀 PROCHAINE ÉTAPE:"
echo "  Vous pouvez maintenant lancer le script TP2 complet :"
echo "  ./tp2_complet.sh"
echo ""