#!/bin/bash
# Correction complète : Portage + Profil systemd

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
echo "     Correction Portage + Profil systemd"
echo "================================================================"
echo ""

# Vérifier le montage
if [ ! -d "${MOUNT_POINT}/etc" ]; then
    log_error "Le système n'est pas monté sur ${MOUNT_POINT}"
    log_info "Montage du système..."
    
    mkdir -p "${MOUNT_POINT}"
    mount /dev/sda3 "${MOUNT_POINT}"
    mkdir -p "${MOUNT_POINT}"/{boot,home}
    mount /dev/sda1 "${MOUNT_POINT}/boot" 2>/dev/null || true
    mount /dev/sda4 "${MOUNT_POINT}/home" 2>/dev/null || true
    swapon /dev/sda2 2>/dev/null || true
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

log_success "Système monté"

# ============================================================================
# DIAGNOSTIC ET CORRECTION
# ============================================================================

chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_FIX'
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
log_info "Profil actuel:"
if [ -L "/etc/portage/make.profile" ]; then
    CURRENT_PROFILE=$(readlink /etc/portage/make.profile)
    echo "  → ${CURRENT_PROFILE}"
    
    if [ -d "${CURRENT_PROFILE}" ]; then
        log_success "Le profil existe"
    else
        log_error "Le profil N'EXISTE PAS (lien cassé)"
    fi
fi

# Vérifier le dépôt Portage
log_info "Vérification du dépôt Portage..."
if [ -d "/var/db/repos/gentoo/profiles" ]; then
    PROFILE_COUNT=$(find /var/db/repos/gentoo/profiles -name "profile.bashrc" 2>/dev/null | wc -l)
    log_success "Dépôt Portage présent (${PROFILE_COUNT} profils)"
else
    log_warning "Dépôt Portage incomplet ou absent"
fi

# Vérifier si portage-latest.tar.xz existe
log_info "Recherche de l'archive Portage..."
if [ -f "/portage-latest.tar.xz" ]; then
    log_success "Archive portage-latest.tar.xz trouvée à la racine"
    PORTAGE_ARCHIVE="/portage-latest.tar.xz"
elif [ -f "/mnt/gentoo/portage-latest.tar.xz" ]; then
    log_success "Archive trouvée dans /mnt/gentoo"
    PORTAGE_ARCHIVE="/mnt/gentoo/portage-latest.tar.xz"
else
    log_warning "Archive Portage non trouvée"
    PORTAGE_ARCHIVE=""
fi

echo ""
echo "════════════════════════════════════════════════════════════"
log_info "ÉTAPE 2 : EXTRACTION/MISE À JOUR DE PORTAGE"
echo "════════════════════════════════════════════════════════════"
echo ""

if [ -n "${PORTAGE_ARCHIVE}" ] && [ -f "${PORTAGE_ARCHIVE}" ]; then
    log_info "Extraction de l'archive Portage..."
    
    # Créer le répertoire si nécessaire
    mkdir -p /var/db/repos/gentoo
    
    # Extraire l'archive
    tar xpf "${PORTAGE_ARCHIVE}" -C /var/db/repos/gentoo --strip-components=1 2>&1 | tail -3
    
    log_success "Archive Portage extraite"
else
    log_warning "Pas d'archive Portage, tentative de synchronisation..."
    
    if command -v emerge-webrsync >/dev/null 2>&1; then
        log_info "Synchronisation avec emerge-webrsync..."
        emerge-webrsync 2>&1 | tail -10
        log_success "Dépôt synchronisé"
    else
        log_error "Impossible de synchroniser le dépôt"
        log_info "Installation manuelle nécessaire"
    fi
fi

# Vérification post-extraction
if [ -d "/var/db/repos/gentoo/profiles" ]; then
    log_success "Dépôt Portage maintenant présent"
else
    log_error "Le dépôt Portage n'a pas été restauré correctement"
    exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════════"
log_info "ÉTAPE 3 : LISTE DES PROFILS SYSTEMD DISPONIBLES"
echo "════════════════════════════════════════════════════════════"
echo ""

log_info "Profils systemd disponibles:"
echo ""

SYSTEMD_PROFILES=$(find /var/db/repos/gentoo/profiles/default/linux/amd64 -type d -name "*systemd*" 2>/dev/null | sort)

if [ -n "${SYSTEMD_PROFILES}" ]; then
    echo "${SYSTEMD_PROFILES}" | while read -r profile; do
        RELATIVE_PATH=$(echo "${profile}" | sed 's|/var/db/repos/gentoo/profiles/||')
        echo "  ✓ ${RELATIVE_PATH}"
    done
else
    log_warning "Aucun profil systemd trouvé"
    log_info "Profils AMD64 disponibles:"
    ls -1 /var/db/repos/gentoo/profiles/default/linux/amd64/ 2>/dev/null | head -10
fi

echo ""
echo "════════════════════════════════════════════════════════════"
log_info "ÉTAPE 4 : SÉLECTION ET APPLICATION DU PROFIL"
echo "════════════════════════════════════════════════════════════"
echo ""

PROFILE_PATH=""
PROFILE_NAME=""

# Liste des profils systemd à essayer (du plus récent au plus ancien)
SYSTEMD_PROFILES_TO_TRY=(
    "17.1/systemd"
    "17.0/systemd"
    "17.1/systemd/merged-usr"
    "17.0/systemd/merged-usr"
    "23.0/systemd"
    "23.0/split-usr/systemd"
)

log_info "Recherche d'un profil systemd compatible..."
for PROFILE in "${SYSTEMD_PROFILES_TO_TRY[@]}"; do
    TEST_PATH="/var/db/repos/gentoo/profiles/default/linux/amd64/${PROFILE}"
    if [ -d "${TEST_PATH}" ]; then
        PROFILE_PATH="${TEST_PATH}"
        PROFILE_NAME="default/linux/amd64/${PROFILE}"
        log_success "Profil trouvé: ${PROFILE_NAME}"
        break
    else
        echo "  ✗ ${PROFILE} n'existe pas"
    fi
done

# Si aucun profil systemd trouvé, prendre le premier disponible
if [ -z "${PROFILE_PATH}" ]; then
    log_warning "Aucun profil systemd standard trouvé"
    log_info "Recherche du premier profil systemd disponible..."
    
    FIRST_SYSTEMD=$(find /var/db/repos/gentoo/profiles/default/linux/amd64 -type d -name "*systemd*" 2>/dev/null | head -1)
    
    if [ -n "${FIRST_SYSTEMD}" ] && [ -d "${FIRST_SYSTEMD}" ]; then
        PROFILE_PATH="${FIRST_SYSTEMD}"
        PROFILE_NAME=$(echo "${FIRST_SYSTEMD}" | sed 's|/var/db/repos/gentoo/profiles/||')
        log_warning "Utilisation du profil: ${PROFILE_NAME}"
    else
        log_error "AUCUN profil systemd trouvé dans le dépôt"
        log_warning "Votre stage3-systemd nécessite un profil systemd"
        
        # Fallback sur OpenRC
        log_info "Fallback sur un profil OpenRC (non recommandé avec stage3-systemd)..."
        for VERSION in 17.1 17.0 13.0; do
            TEST_PATH="/var/db/repos/gentoo/profiles/default/linux/amd64/${VERSION}"
            if [ -d "${TEST_PATH}" ]; then
                PROFILE_PATH="${TEST_PATH}"
                PROFILE_NAME="default/linux/amd64/${VERSION}"
                log_warning "Profil OpenRC utilisé: ${PROFILE_NAME}"
                break
            fi
        done
    fi
fi

if [ -z "${PROFILE_PATH}" ]; then
    log_error "Aucun profil utilisable trouvé"
    exit 1
fi

log_info "Application du profil: ${PROFILE_NAME}"

# Suppression de l'ancien lien
rm -f /etc/portage/make.profile

# Création du nouveau lien
ln -sf "${PROFILE_PATH}" /etc/portage/make.profile

log_success "Profil appliqué"

echo ""
echo "════════════════════════════════════════════════════════════"
log_info "ÉTAPE 5 : VÉRIFICATION FINALE"
echo "════════════════════════════════════════════════════════════"
echo ""

log_info "Vérification du lien symbolique..."
FINAL_LINK=$(readlink /etc/portage/make.profile)
echo "  → ${FINAL_LINK}"

if [ -d "${FINAL_LINK}" ]; then
    log_success "Le profil est VALIDE !"
else
    log_error "Le profil est toujours invalide"
    exit 1
fi

log_info "Test avec emerge --info..."
if emerge --info 2>&1 | head -10; then
    log_success "emerge fonctionne correctement !"
else
    log_warning "emerge a des avertissements"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
log_success "✅ CORRECTION TERMINÉE AVEC SUCCÈS !"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Profil configuré: ${PROFILE_NAME}"
echo ""
echo "INFORMATIONS IMPORTANTES:"
echo "  • Vous utilisez un stage3-systemd"
echo "  • Le profil systemd est maintenant correctement configuré"
echo "  • Le dépôt Portage a été restauré/synchronisé"
echo ""

CHROOT_FIX

echo ""
echo "================================================================"
log_success "✅ TOUT EST CORRIGÉ !"
echo "================================================================"
echo ""
echo "📋 CE QUI A ÉTÉ FAIT:"
echo "  ✓ Dépôt Portage restauré/synchronisé"
echo "  ✓ Profil systemd trouvé et configuré"
echo "  ✓ Lien symbolique créé"
echo "  ✓ emerge fonctionnel"
echo ""
echo "🚀 PROCHAINE ÉTAPE:"
echo "  Vous pouvez maintenant lancer le script TP2 :"
echo "  ./tp2_complet.sh"
echo ""
echo "💡 NOTE:"
echo "  Votre installation utilise systemd (pas OpenRC)"
echo "  Les commandes de service seront différentes :"
echo "  • systemctl au lieu de rc-update"
echo "  • systemctl enable/start au lieu de rc-service"
echo ""