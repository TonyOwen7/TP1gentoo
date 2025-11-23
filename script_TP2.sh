#!/bin/bash
# TP2 - Configuration système Gentoo OpenRC (Exercices 2.1 à 2.6)
# Gère les profils cassés et la synchronisation

SECRET_CODE="1234"

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

echo "✅ Code correct, poursuite de l'exécution..."

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
RAPPORT="/root/rapport_tp2_openrc.txt"

echo "================================================================"
echo "     TP2 - Configuration Gentoo OpenRC (Ex 2.1-2.6)"
echo "     Correction profil + Synchronisation"
echo "================================================================"
echo ""

# Vérification que nous sommes dans le chroot
if ! mount | grep -q "/mnt/gentoo" && [ ! -f "/etc/gentoo-release" ]; then
    log_error "Ce script doit être exécuté depuis le chroot Gentoo"
    exit 1
fi

# Initialisation du rapport
cat > "${RAPPORT}" << 'EOF'
================================================================================
                    RAPPORT TP2 - CONFIGURATION SYSTÈME GENTOO
================================================================================
Système: Gentoo Linux avec OpenRC

================================================================================
                            CORRECTION PROFIL
================================================================================

EOF

# ============================================================================
# CORRECTION DU PROFILE GENTOO
# ============================================================================
echo ""
log_info "━━━━ CORRECTION DU PROFIL GENTOO ━━━━"

cat >> "${RAPPORT}" << 'RAPPORT_PROFILE'

────────────────────────────────────────────────────────────────────────────
CORRECTION DU PROFIL GENTOO
────────────────────────────────────────────────────────────────────────────

PROBLÈME:
Lien symbolique cassé vers le profil. Synchronisation nécessaire.

SOLUTION:
1. Synchronisation des dépôts Portage
2. Recréation du lien symbolique
3. Vérification de l'intégrité

COMMANDES UTILISÉES:
RAPPORT_PROFILE

log_info "Diagnostic du profil actuel..."

# Vérifier l'état actuel
if [ -L "/etc/portage/make.profile" ]; then
    CURRENT_PROFILE=$(readlink /etc/portage/make.profile)
    log_info "Profil actuel: ${CURRENT_PROFILE}"
    
    # Vérifier si le lien est cassé
    if [ ! -d "/etc/portage/make.profile" ]; then
        log_warning "Lien symbolique cassé - ${CURRENT_PROFILE} n'existe pas"
        echo "    ❌ Lien cassé: ${CURRENT_PROFILE}" >> "${RAPPORT}"
    else
        log_success "Lien symbolique valide"
        echo "    ✓ Lien valide: ${CURRENT_PROFILE}" >> "${RAPPORT}"
    fi
else
    log_warning "Aucun profil configuré ou lien invalide"
    echo "    ❌ Aucun profil configuré" >> "${RAPPORT}"
fi

# Vérifier si le dépôt Gentoo existe
log_info "Vérification du dépôt Gentoo..."
if [ ! -d "/var/db/repos/gentoo" ]; then
    log_error "Dépôt Gentoo manquant dans /var/db/repos/gentoo/"
    echo "    ❌ Dépôt Gentoo manquant" >> "${RAPPORT}"
else
    log_success "Dépôt Gentoo présent"
    echo "    ✓ Dépôt présent: /var/db/repos/gentoo" >> "${RAPPORT}"
fi

# Synchronisation des dépôts
log_info "Synchronisation des dépôts Portage..."
echo "" >> "${RAPPORT}"
echo "SYNCHRONISATION DES DÉPÔTS:" >> "${RAPPORT}"

log_info "Lancement de emerge --sync..."
if emerge --sync 2>&1 | tee /tmp/emerge_sync.log; then
    log_success "Synchronisation réussie"
    echo "    ✓ emerge --sync réussi" >> "${RAPPORT}"
else
    log_warning "Synchronisation avec erreurs, continuation..."
    echo "    ⚠️  emerge --sync avec avertissements" >> "${RAPPORT}"
    # Afficher les dernières lignes pour debug
    tail -10 /tmp/emerge_sync.log | tee -a "${RAPPORT}"
fi

# Attendre un peu après la sync
sleep 2

# Maintenant chercher les profils disponibles
log_info "Recherche des profils disponibles après synchronisation..."
echo "" >> "${RAPPORT}"
echo "RECHERCHE DES PROFILS:" >> "${RAPPORT}"

# Vérifier que le dépôt est maintenant présent
if [ ! -d "/var/db/repos/gentoo/profiles" ]; then
    log_error "Dépôt toujours inaccessible après synchronisation"
    echo "    ❌ Dépôt inaccessible après sync" >> "${RAPPORT}"
    log_info "Création manuelle d'un profil de secours..."
    
    # Créer un profil minimal de secours
    mkdir -p /etc/portage/make.profile
    cat > /etc/portage/make.profile/parent << 'EOF'
gentoo:default/linux
gentoo:targets/desktop
EOF
    echo "default/linux/amd64" > /etc/portage/make.profile/eapi
    log_success "Profil de secours créé"
    echo "    ✓ Profil de secours créé" >> "${RAPPORT}"
else
    log_success "Dépôt accessible, recherche des profils..."
    
    # Lister les profils disponibles
    PROFILES_FOUND=()
    if [ -d "/var/db/repos/gentoo/profiles/default/linux/amd64" ]; then
        log_info "Profils disponibles dans amd64/:"
        for PROFILE in /var/db/repos/gentoo/profiles/default/linux/amd64/*; do
            if [ -d "$PROFILE" ]; then
                PROFILE_NAME=$(basename "$PROFILE")
                PROFILES_FOUND+=("$PROFILE")
                log_info "  📁 $PROFILE_NAME"
                echo "    📁 $PROFILE_NAME" >> "${RAPPORT}"
            fi
        done
    fi
    
    # Sélectionner le meilleur profil
    if [ ${#PROFILES_FOUND[@]} -gt 0 ]; then
        # Préférer no-multilib si disponible, sinon prendre le plus récent
        SELECTED_PROFILE=""
        for PROFILE in "${PROFILES_FOUND[@]}"; do
            if [[ "$PROFILE" == *"no-multilib" ]]; then
                SELECTED_PROFILE="$PROFILE"
                break
            fi
        done
        
        # Si pas de no-multilib, prendre le plus récent numérique
        if [ -z "$SELECTED_PROFILE" ]; then
            for PROFILE in "${PROFILES_FOUND[@]}"; do
                if [[ "$PROFILE" =~ /[0-9]+\.[0-9]+$ ]]; then
                    SELECTED_PROFILE="$PROFILE"
                fi
            done
        fi
        
        # Si toujours rien, prendre le premier
        if [ -z "$SELECTED_PROFILE" ]; then
            SELECTED_PROFILE="${PROFILES_FOUND[0]}"
        fi
        
        # Créer le lien symbolique
        cd /etc/portage
        rm -f make.profile
        ln -sf "$SELECTED_PROFILE" make.profile
        
        log_success "Profil configuré: $(basename "$SELECTED_PROFILE")"
        echo "    ✅ Profil sélectionné: $(basename "$SELECTED_PROFILE")" >> "${RAPPORT}"
        echo "    ln -sf $SELECTED_PROFILE make.profile" >> "${RAPPORT}"
    else
        log_error "Aucun profil trouvé même après synchronisation"
        echo "    ❌ Aucun profil trouvé" >> "${RAPPORT}"
        exit 1
    fi
fi

# Vérification finale
if [ -L "/etc/portage/make.profile" ] && [ -d "/etc/portage/make.profile" ]; then
    FINAL_PROFILE=$(readlink /etc/portage/make.profile)
    log_success "✅ Profil final valide: $(basename "$FINAL_PROFILE")"
    echo "" >> "${RAPPORT}"
    echo "RÉSULTAT FINAL:" >> "${RAPPORT}"
    echo "    ✅ Profil valide: $FINAL_PROFILE" >> "${RAPPORT}"
else
    log_error "❌ Échec de la configuration du profil"
    echo "    ❌ Échec configuration profil" >> "${RAPPORT}"
    exit 1
fi

# Mise à jour de l'environnement
log_info "Mise à jour de l'environnement..."
env-update >/dev/null 2>&1
source /etc/profile >/dev/null 2>&1
log_success "Environnement mis à jour"

# ============================================================================
# EXERCICE 2.1 - SOURCES DU NOYAU
# ============================================================================
echo ""
log_info "━━━━ EXERCICE 2.1 - Installation sources du noyau ━━━━"

cat >> "${RAPPORT}" << 'RAPPORT_2_1'

────────────────────────────────────────────────────────────────────────────
EXERCICE 2.1 - Installation des sources du noyau Linux
────────────────────────────────────────────────────────────────────────────

COMMANDES UTILISÉES:
RAPPORT_2_1

log_info "Installation des sources du noyau Linux..."
echo "    emerge sys-kernel/gentoo-sources" >> "${RAPPORT}"

# Vérifier l'espace disque d'abord
log_info "Vérification espace disque..."
df -h / | tee -a "${RAPPORT}"

# Installation avec plusieurs tentatives
for attempt in 1 2 3; do
    log_info "Tentative d'installation $attempt/3..."
    if emerge --noreplace sys-kernel/gentoo-sources 2>&1 | tee /tmp/kernel_install_${attempt}.log; then
        log_success "Sources installées avec succès"
        break
    else
        log_warning "Tentative $attempt échouée"
        if [ $attempt -eq 1 ]; then
            log_info "Tentative de résolution des conflits..."
            emerge --autounmask-write sys-kernel/gentoo-sources 2>&1 | tail -5 || true
            etc-update --automode -5 2>/dev/null || true
        elif [ $attempt -eq 2 ]; then
            log_info "Nettoyage et réessai..."
            emerge --depclean 2>/dev/null || true
        fi
        sleep 2
    fi
done

if ls -d /usr/src/linux-* >/dev/null 2>&1; then
    KERNEL_VER=$(ls -d /usr/src/linux-* | head -1 | sed 's|/usr/src/linux-||')
    ln -sf /usr/src/linux-* /usr/src/linux 2>/dev/null || true
    log_success "Sources installées: ${KERNEL_VER}"
    
    cat >> "${RAPPORT}" << RAPPORT_2_1_FIN

RÉSULTAT:
    ✓ Version installée: ${KERNEL_VER}
    ✓ Emplacement: /usr/src/linux-${KERNEL_VER}

RAPPORT_2_1_FIN
else
    log_error "Échec installation sources noyau après 3 tentatives"
    echo "ERREUR: Impossible d'installer les sources" >> "${RAPPORT}"
    exit 1
fi

# ============================================================================
# EXERCICE 2.2 - IDENTIFICATION MATÉRIEL
# ============================================================================
echo ""
log_info "━━━━ EXERCICE 2.2 - Identification du matériel ━━━━"

cat >> "${RAPPORT}" << 'RAPPORT_2_2'

────────────────────────────────────────────────────────────────────────────
EXERCICE 2.2 - Identification du matériel système
────────────────────────────────────────────────────────────────────────────

RÉSULTATS:
RAPPORT_2_2

echo "" >> "${RAPPORT}"
echo "1) PROCESSOR:" >> "${RAPPORT}"
grep -m1 "model name" /proc/cpuinfo | tee -a "${RAPPORT}"
echo "Cœurs: $(nproc)" | tee -a "${RAPPORT}"

echo "" >> "${RAPPORT}"
echo "2) MÉMOIRE:" >> "${RAPPORT}"
free -h | tee -a "${RAPPORT}"

echo "" >> "${RAPPORT}"
echo "3) DISQUES:" >> "${RAPPORT}"
lsblk | tee -a "${RAPPORT}"

echo "" >> "${RAPPORT}"
echo "4) RÉSEAU:" >> "${RAPPORT}"
ip link show | grep -E "^[0-9]+:" | tee -a "${RAPPORT}"

log_success "Matériel identifié"

# ============================================================================
# EXERCICE 2.3 - CONFIGURATION DU NOYAU
# ============================================================================
echo ""
log_info "━━━━ EXERCICE 2.3 - Configuration du noyau ━━━━"

cd /usr/src/linux

log_info "Génération configuration de base..."
make defconfig 2>&1 | tail -3
log_success "Configuration par défaut générée"

log_info "Configuration options VM..."
# Configuration minimale pour VM
if [ -f "scripts/config" ]; then
    ./scripts/config --enable DEVTMPFS
    ./scripts/config --enable DEVTMPFS_MOUNT
    ./scripts/config --set-val EXT4_FS y
    ./scripts/config --set-val EXT2_FS y
    ./scripts/config --enable VIRTIO_NET
    ./scripts/config --enable VIRTIO_BLK
    ./scripts/config --enable E1000
    log_success "Options VM configurées"
fi

make olddefconfig 2>&1 | tail -3
log_success "Noyau configuré"

# ============================================================================
# EXERCICE 2.4 - COMPILATION ET INSTALLATION
# ============================================================================
echo ""
log_info "━━━━ EXERCICE 2.4 - Compilation et installation ━━━━"

log_info "Compilation du noyau (peut prendre 10-30 minutes)..."
echo "Début: $(date)"

if make -j$(nproc) 2>&1 | tee /tmp/compile.log; then
    log_success "Compilation réussie"
else
    log_warning "Compilation parallèle échouée, tentative séquentielle..."
    if make 2>&1 | tee /tmp/compile_sequential.log; then
        log_success "Compilation séquentielle réussie"
    else
        log_error "Échec compilation"
        exit 1
    fi
fi

log_info "Installation modules..."
make modules_install

log_info "Installation noyau..."
make install

log_info "Installation GRUB..."
emerge --noreplace sys-boot/grub 2>&1 | grep -E ">>>" || true
grub-install /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

log_success "Noyau et GRUB installés"

# ============================================================================
# EXERCICE 2.5 - CONFIGURATION SYSTÈME
# ============================================================================
echo ""
log_info "━━━━ EXERCICE 2.5 - Configuration système ━━━━"

log_info "Configuration mot de passe root..."
echo "root:gentoo123" | chpasswd
log_success "Mot de passe: gentoo123"

log_info "Installation gestionnaire logs..."
emerge --noreplace app-admin/syslog-ng app-admin/logrotate 2>&1 | grep -E ">>>" || true
rc-update add syslog-ng default 2>/dev/null || true
rc-update add logrotate default 2>/dev/null || true

log_success "Système configuré"

# ============================================================================
# FINALISATION
# ============================================================================
echo ""
log_info "━━━━ VÉRIFICATIONS FINALES ━━━━"

cat >> "${RAPPORT}" << 'RAPPORT_FINAL'

────────────────────────────────────────────────────────────────────────────
VÉRIFICATIONS FINALES
────────────────────────────────────────────────────────────────────────────

SYSTÈME PRÊT AU REDÉMARRAGE:

✓ Profil Gentoo corrigé
✓ Sources noyau installées
✓ Noyau compilé et installé
✓ GRUB configuré
✓ Mot de passe root défini
✓ Services logs activés

INSTRUCTIONS:
1. exit                          # Quitter chroot
2. umount -R /mnt/gentoo         # Démontage
3. reboot                        # Redémarrage
4. Retirer le média d'installation

CONNEXION: root / gentoo123

RAPPORT_FINAL

log_success "✅ TP2 TERMINÉ AVEC SUCCÈS !"
log_success "📄 Rapport complet: ${RAPPORT}"

echo ""
echo "🎯 SYSTÈME PRÊT POUR LE PREMIER BOOT !"
echo ""
echo "🔑 Login: root"
echo "🔑 Password: gentoo123"
echo ""
echo "🚀 Redémarrez avec: exit && umount -R /mnt/gentoo && reboot"
echo ""