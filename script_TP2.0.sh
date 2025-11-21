#!/bin/bash
# Script de correction du profil Gentoo

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
echo "     Correction du profil Gentoo"
echo "================================================================"
echo ""

# Vérifier qu'on est dans le chroot ou qu'on peut y accéder
if [ ! -d "${MOUNT_POINT}/etc/portage" ] && [ ! -d "/etc/portage" ]; then
    log_error "Impossible de trouver le système Gentoo"
    exit 1
fi

# Fonction pour corriger le profil
fix_profile() {
    log_info "Diagnostic du profil actuel..."
    
    # Afficher le profil actuel
    if [ -L "/etc/portage/make.profile" ]; then
        CURRENT_PROFILE=$(readlink /etc/portage/make.profile)
        echo "  Profil actuel: ${CURRENT_PROFILE}"
        
        if [ ! -d "/etc/portage/make.profile" ]; then
            log_error "Le profil pointe vers un répertoire inexistant"
        fi
    else
        log_error "Aucun profil configuré"
    fi
    
    echo ""
    log_info "Profils disponibles:"
    eselect profile list 2>/dev/null || {
        log_warning "eselect non disponible, listing manuel..."
        ls -la /var/db/repos/gentoo/profiles/
    }
    
    echo ""
    log_info "Sélection automatique d'un profil approprié..."
    
    # Chercher un profil stable approprié
    if [ -d "/var/db/repos/gentoo/profiles/default/linux/amd64/23.0" ]; then
        PROFILE_PATH="/var/db/repos/gentoo/profiles/default/linux/amd64/23.0"
        PROFILE_NAME="default/linux/amd64/23.0"
    elif [ -d "/var/db/repos/gentoo/profiles/default/linux/amd64/17.1" ]; then
        PROFILE_PATH="/var/db/repos/gentoo/profiles/default/linux/amd64/17.1"
        PROFILE_NAME="default/linux/amd64/17.1"
    elif [ -d "/var/db/repos/gentoo/profiles/default/linux/amd64/17.0" ]; then
        PROFILE_PATH="/var/db/repos/gentoo/profiles/default/linux/amd64/17.0"
        PROFILE_NAME="default/linux/amd64/17.0"
    else
        log_error "Aucun profil standard trouvé"
        log_info "Profils disponibles dans /var/db/repos/gentoo/profiles/:"
        find /var/db/repos/gentoo/profiles/default/linux/amd64/ -maxdepth 1 -type d 2>/dev/null
        exit 1
    fi
    
    log_info "Sélection du profil: ${PROFILE_NAME}"
    
    # Supprimer l'ancien lien symbolique
    rm -f /etc/portage/make.profile
    
    # Créer le nouveau lien symbolique
    ln -sf "${PROFILE_PATH}" /etc/portage/make.profile
    
    log_success "Profil configuré: ${PROFILE_NAME}"
    
    # Vérification
    echo ""
    log_info "Vérification du nouveau profil..."
    if [ -d "/etc/portage/make.profile" ]; then
        log_success "Le profil est valide !"
        echo "  Lien: $(readlink /etc/portage/make.profile)"
    else
        log_error "Le profil est toujours invalide"
        exit 1
    fi
    
    # Test avec emerge
    echo ""
    log_info "Test avec emerge --info..."
    if emerge --info 2>&1 | head -5; then
        log_success "emerge fonctionne correctement"
    else
        log_warning "Des avertissements persistent mais devrait fonctionner"
    fi
}

# Exécution selon le contexte
if [ -d "/etc/portage" ] && [ ! -d "${MOUNT_POINT}/etc" ]; then
    # On est déjà dans le chroot
    log_info "Exécution dans le chroot..."
    fix_profile
else
    # On est en dehors, il faut chrooter
    log_info "Exécution via chroot..."
    
    # Montage si nécessaire
    if [ ! -d "${MOUNT_POINT}/etc/portage" ]; then
        log_error "Le système Gentoo n'est pas monté sur ${MOUNT_POINT}"
        exit 1
    fi
    
    # Montage des systèmes virtuels
    mount -t proc /proc "${MOUNT_POINT}/proc" 2>/dev/null || true
    mount --rbind /sys "${MOUNT_POINT}/sys" 2>/dev/null || true
    mount --make-rslave "${MOUNT_POINT}/sys" 2>/dev/null || true
    mount --rbind /dev "${MOUNT_POINT}/dev" 2>/dev/null || true
    mount --make-rslave "${MOUNT_POINT}/dev" 2>/dev/null || true
    
    cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/" 2>/dev/null || true
    
    # Exécution dans le chroot
    chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_FIX'
#!/bin/bash
set -euo pipefail

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

source /etc/profile
export PS1="(chroot) \$PS1"

echo ""
log_info "Diagnostic du profil dans le chroot..."

# Afficher le profil actuel
if [ -L "/etc/portage/make.profile" ]; then
    CURRENT_PROFILE=$(readlink /etc/portage/make.profile)
    echo "  Profil actuel: ${CURRENT_PROFILE}"
    
    if [ ! -d "/etc/portage/make.profile" ]; then
        log_error "Le profil pointe vers un répertoire inexistant"
    fi
else
    log_error "Aucun profil configuré"
fi

echo ""
log_info "Profils disponibles:"
eselect profile list 2>&1 | head -20

echo ""
log_info "Sélection automatique du profil..."

# Utiliser eselect pour choisir le premier profil stable
PROFILE_NUM=$(eselect profile list | grep -E "default/linux/amd64/[0-9]+\.[0-9]+.*\(stable\)" | head -1 | awk '{print $1}' | tr -d '[]')

if [ -z "$PROFILE_NUM" ]; then
    # Fallback: prendre le premier profil amd64 disponible
    PROFILE_NUM=$(eselect profile list | grep "default/linux/amd64" | head -1 | awk '{print $1}' | tr -d '[]')
fi

if [ -n "$PROFILE_NUM" ]; then
    log_info "Sélection du profil numéro: ${PROFILE_NUM}"
    eselect profile set "${PROFILE_NUM}"
    log_success "Profil configuré avec eselect"
else
    log_warning "Impossible de trouver un profil avec eselect"
    log_info "Configuration manuelle..."
    
    # Configuration manuelle
    if [ -d "/var/db/repos/gentoo/profiles/default/linux/amd64/23.0" ]; then
        PROFILE_PATH="/var/db/repos/gentoo/profiles/default/linux/amd64/23.0"
    elif [ -d "/var/db/repos/gentoo/profiles/default/linux/amd64/17.1" ]; then
        PROFILE_PATH="/var/db/repos/gentoo/profiles/default/linux/amd64/17.1"
    elif [ -d "/var/db/repos/gentoo/profiles/default/linux/amd64/17.0" ]; then
        PROFILE_PATH="/var/db/repos/gentoo/profiles/default/linux/amd64/17.0"
    else
        log_error "Aucun profil trouvé"
        exit 1
    fi
    
    rm -f /etc/portage/make.profile
    ln -sf "${PROFILE_PATH}" /etc/portage/make.profile
    log_success "Profil configuré manuellement: ${PROFILE_PATH}"
fi

# Vérification finale
echo ""
log_info "Vérification du profil..."
SELECTED_PROFILE=$(eselect profile show 2>/dev/null || readlink /etc/portage/make.profile)
echo "  Profil sélectionné: ${SELECTED_PROFILE}"

if [ -d "/etc/portage/make.profile" ]; then
    log_success "Le profil est VALIDE !"
else
    log_error "Le profil est INVALIDE"
    exit 1
fi

# Test avec emerge
echo ""
log_info "Test final avec emerge..."
if emerge --info 2>&1 | grep -E "^Portage|^Profile" | head -3; then
    log_success "emerge fonctionne parfaitement !"
else
    log_warning "emerge a des avertissements"
fi

CHROOT_FIX
fi

echo ""
echo "================================================================"
log_success "✅ PROFIL CORRIGÉ !"
echo "================================================================"
echo ""
log_info "Vous pouvez maintenant relancer votre script TP2"
echo ""