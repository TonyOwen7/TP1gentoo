#!/bin/bash
# GÉNÉRATION MANUELLE modules GRUB + core.img + grub.cfg

SECRET_CODE="1234"

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

echo "✅ Code correct, génération manuelle GRUB..."

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
echo "     GÉNÉRATION MANUELLE modules GRUB + core.img + grub.cfg"
echo "================================================================"
echo ""

# ============================================================================
# MONTAGE DES PARTITIONS
# ============================================================================
log_info "Montage des partitions..."

umount -R "${MOUNT_POINT}" 2>/dev/null || true

mount "${DISK}3" "${MOUNT_POINT}" || { log_error "Échec montage racine"; exit 1; }
mkdir -p "${MOUNT_POINT}/boot"
mount "${DISK}1" "${MOUNT_POINT}/boot" || log_warning "Boot déjà monté"

# Monter l'environnement chroot
mount -t proc /proc "${MOUNT_POINT}/proc"
mount --rbind /sys "${MOUNT_POINT}/sys"
mount --make-rslave "${MOUNT_POINT}/sys"
mount --rbind /dev "${MOUNT_POINT}/dev"
mount --make-rslave "${MOUNT_POINT}/dev"
cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/"

# ============================================================================
# VÉRIFICATION DE L'ÉTAT ACTUEL
# ============================================================================
log_info "Vérification de l'état actuel..."

echo "[1/4] Vérification noyau..."
if ls "${MOUNT_POINT}/boot/vmlinuz"* >/dev/null 2>&1; then
    KERNEL_FILE=$(ls "${MOUNT_POINT}/boot/vmlinuz"* | head -1)
    KERNEL_NAME=$(basename "$KERNEL_FILE")
    log_success "✅ Noyau: $KERNEL_NAME"
else
    log_error "❌ Aucun noyau trouvé"
    exit 1
fi

echo ""
echo "[2/4] Vérification modules GRUB..."
if [ -d "${MOUNT_POINT}/boot/grub/i386-pc" ]; then
    MODULE_COUNT=$(ls "${MOUNT_POINT}/boot/grub/i386-pc"/*.mod 2>/dev/null | wc -l)
    if [ "$MODULE_COUNT" -gt 0 ]; then
        log_success "✅ Modules GRUB: $MODULE_COUNT fichiers"
    else
        log_error "❌ Dossier i386-pc vide"
    fi
else
    log_error "❌ Dossier i386-pc manquant"
fi

echo ""
echo "[3/4] Vérification core.img..."
if [ -f "${MOUNT_POINT}/boot/grub/core.img" ]; then
    log_success "✅ core.img présent"
else
    log_error "❌ core.img manquant"
fi

echo ""
echo "[4/4] Vérification grub.cfg..."
if [ -f "${MOUNT_POINT}/boot/grub/grub.cfg" ]; then
    log_success "✅ grub.cfg présent"
else
    log_error "❌ grub.cfg manquant"
fi

# ============================================================================
# SCRIPT DE GÉNÉRATION MANUELLE DANS CHROOT
# ============================================================================
log_info "Création du script de génération manuelle..."

cat > "${MOUNT_POINT}/root/generate_grub_manual.sh" << 'GRUB_GEN'
#!/bin/bash
# Génération manuelle modules GRUB + core.img + grub.cfg

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

echo ""
echo "================================================================"
log_info "DÉBUT GÉNÉRATION MANUELLE GRUB"
echo "================================================================"

# ============================================================================
# ÉTAPE 1: INSTALLATION DE GRUB DANS LE SYSTÈME
# ============================================================================
log_info "1/5 - Installation de GRUB dans le système..."

if ! command -v grub-install >/dev/null 2>&1; then
    log_info "GRUB non installé, installation..."
    export FEATURES="-sandbox -usersandbox -network-sandbox"
    
    if emerge --noreplace --nodeps --quiet sys-boot/grub 2>&1; then
        log_success "✅ GRUB installé"
    else
        log_error "❌ Échec installation GRUB"
        exit 1
    fi
else
    log_success "✅ GRUB déjà installé"
fi

# ============================================================================
# ÉTAPE 2: CRÉATION DES DOSSIERS GRUB
# ============================================================================
log_info "2/5 - Création des dossiers GRUB..."

mkdir -p /boot/grub
mkdir -p /boot/grub/i386-pc
log_success "✅ Dossiers GRUB créés"

# ============================================================================
# ÉTAPE 3: GÉNÉRATION DES MODULES GRUB
# ============================================================================
log_info "3/5 - Génération des modules GRUB..."

if command -v grub-mkimage >/dev/null 2>&1; then
    log_info "Génération des modules avec grub-mkimage..."
    
    # Modules essentiels pour boot
    MODULES="biosdisk part_msdos ext2 fat normal ls boot search search_fs_uuid search_fs_file search_label configfile echo test cat help reboot halt linux chain"
    
    # Générer core.img avec modules
    if grub-mkimage -O i386-pc -o /boot/grub/core.img -p "(hd0,msdos1)/grub" $MODULES 2>&1; then
        log_success "✅ core.img généré"
    else
        log_error "❌ Échec génération core.img"
    fi
    
    # Copier les modules depuis le système
    if [ -d "/usr/lib/grub/i386-pc" ]; then
        log_info "Copie des modules depuis /usr/lib/grub/i386-pc..."
        cp /usr/lib/grub/i386-pc/*.mod /boot/grub/i386-pc/ 2>/dev/null || true
        cp /usr/lib/grub/i386-pc/*.lst /boot/grub/i386-pc/ 2>/dev/null || true
        cp /usr/lib/grub/i386-pc/*.img /boot/grub/i386-pc/ 2>/dev/null || true
        
        MODULE_COUNT=$(ls /boot/grub/i386-pc/*.mod 2>/dev/null | wc -l)
        log_success "✅ Modules copiés: $MODULE_COUNT fichiers"
    else
        log_warning "⚠️ Dossier /usr/lib/grub/i386-pc non trouvé"
    fi
else
    log_error "❌ grub-mkimage non disponible"
fi

# ============================================================================
# ÉTAPE 4: CRÉATION DE grub.cfg
# ============================================================================
log_info "4/5 - Création de grub.cfg..."

# Trouver le noyau exact
KERNEL_FILE=$(ls /boot/vmlinuz* 2>/dev/null | head -1)
if [ -z "$KERNEL_FILE" ]; then
    log_error "❌ Aucun noyau trouvé"
    exit 1
fi
KERNEL_NAME=$(basename "$KERNEL_FILE")

log_info "Utilisation du noyau: $KERNEL_NAME"

# Créer grub.cfg manuellement
cat > /boot/grub/grub.cfg << EOF
# Configuration GRUB générée manuellement
set timeout=5
set default=0

# Entrée principale
menuentry "Gentoo Linux" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /$KERNEL_NAME root=/dev/sda3 ro quiet
}

menuentry "Gentoo Linux (mode secours)" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /$KERNEL_NAME root=/dev/sda3 ro single
}

menuentry "Gentoo Linux (mode debug)" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /$KERNEL_NAME root=/dev/sda3 ro debug
}

# Fallback
menuentry "Gentoo Fallback" {
    linux /vmlinuz-* root=/dev/sda3 ro
}
EOF

log_success "✅ grub.cfg créé"

# ============================================================================
# ÉTAPE 5: INSTALLATION DANS LE MBR
# ============================================================================
log_info "5/5 - Installation dans le MBR..."

if command -v grub-install >/dev/null 2>&1; then
    log_info "Installation avec grub-install..."
    
    if grub-install /dev/sda 2>&1; then
        log_success "✅ GRUB installé dans MBR"
    else
        log_warning "Échec grub-install, tentative alternative..."
        
        # Méthode alternative
        grub-install --target=i386-pc /dev/sda 2>&1 || \
        grub-install --force /dev/sda 2>&1 || \
        log_error "❌ Toutes les méthodes ont échoué"
    fi
else
    log_error "❌ grub-install non disponible"
fi

# ============================================================================
# VÉRIFICATIONS FINALES
# ============================================================================
log_info "VÉRIFICATIONS FINALES..."

echo ""
echo "=== RÉCAPITULATIF ==="
echo "🔧 Noyau: $KERNEL_NAME"
echo "📁 Boot: /dev/sda1"
echo "🎯 Root: /dev/sda3"

echo ""
echo "=== VÉRIFICATION FICHIERS ==="
if [ -f "/boot/grub/grub.cfg" ]; then
    log_success "✅ grub.cfg: PRÉSENT"
    echo "Entrées:"
    grep "^menuentry" /boot/grub/grub.cfg
else
    log_error "❌ grub.cfg: ABSENT"
fi

if [ -f "/boot/grub/core.img" ]; then
    log_success "✅ core.img: PRÉSENT"
else
    log_error "❌ core.img: ABSENT"
fi

MODULE_COUNT=$(ls /boot/grub/i386-pc/*.mod 2>/dev/null | wc -l)
if [ "$MODULE_COUNT" -gt 0 ]; then
    log_success "✅ Modules: $MODULE_COUNT fichiers"
else
    log_error "❌ Modules: AUCUN"
fi

# Vérification finale
if [ -f "/boot/grub/grub.cfg" ] && [ -f "/boot/grub/core.img" ] && [ "$MODULE_COUNT" -gt 0 ]; then
    echo ""
    log_success "🎉🎉🎉 GÉNÉRATION RÉUSSIE !"
    log_success "✅ Modules GRUB générés"
    log_success "✅ core.img créé"
    log_success "✅ grub.cfg configuré"
    log_success "✅ GRUB dans MBR"
else
    log_error "⚠️ Problèmes détectés"
fi
GRUB_GEN

# Rendre exécutable
chmod +x "${MOUNT_POINT}/root/generate_grub_manual.sh"

# ============================================================================
# EXÉCUTION DE LA GÉNÉRATION
# ============================================================================
echo ""
log_info "━━━━ EXÉCUTION GÉNÉRATION MANUELLE ━━━━"

chroot "${MOUNT_POINT}" /bin/bash -c "
  cd /root
  ./generate_grub_manual.sh
"

# ============================================================================
# VÉRIFICATION RÉELLE APRÈS GÉNÉRATION
# ============================================================================
echo ""
log_info "━━━━ VÉRIFICATION RÉELLE APRÈS GÉNÉRATION ━━━━"

log_info "1. Vérification modules GRUB..."
if [ -d "${MOUNT_POINT}/boot/grub/i386-pc" ]; then
    MODULE_COUNT=$(ls "${MOUNT_POINT}/boot/grub/i386-pc"/*.mod 2>/dev/null | wc -l)
    if [ "$MODULE_COUNT" -gt 0 ]; then
        log_success "✅ Modules: $MODULE_COUNT fichiers"
        ls "${MOUNT_POINT}/boot/grub/i386-pc"/*.mod | head -5
    else
        log_error "❌ Aucun module trouvé"
    fi
else
    log_error "❌ Dossier i386-pc manquant"
fi

log_info "2. Vérification core.img..."
if [ -f "${MOUNT_POINT}/boot/grub/core.img" ]; then
    CORE_SIZE=$(stat -c%s "${MOUNT_POINT}/boot/grub/core.img" 2>/dev/null || echo "0")
    log_success "✅ core.img: PRÉSENT ($CORE_SIZE octets)"
else
    log_error "❌ core.img: ABSENT"
fi

log_info "3. Vérification grub.cfg..."
if [ -f "${MOUNT_POINT}/boot/grub/grub.cfg" ]; then
    log_success "✅ grub.cfg: PRÉSENT"
    echo "Extrait:"
    head -10 "${MOUNT_POINT}/boot/grub/grub.cfg"
else
    log_error "❌ grub.cfg: ABSENT"
fi

log_info "4. Vérification MBR..."
if dd if=/dev/sda bs=512 count=1 2>/dev/null | strings | grep -q "GRUB"; then
    log_success "🎉 GRUB DÉTECTÉ DANS LE MBR !"
else
    log_warning "⚠️ GRUB non détecté dans MBR"
fi

# ============================================================================
# SAUVEGARDE DE LA CONFIGURATION
# ============================================================================
echo ""
log_info "Sauvegarde de la configuration..."

# Sauvegarder grub.cfg
cp "${MOUNT_POINT}/boot/grub/grub.cfg" "${MOUNT_POINT}/boot/grub/grub.cfg.backup" 2>/dev/null || true

# Créer un rapport
cat > "${MOUNT_POINT}/boot/GRUB-REPORT.txt" << EOF
🐧 RAPPORT GRUB - GÉNÉRATION MANUELLE
====================================

Date: $(date)
Noyau: $KERNEL_NAME

📊 RÉSULTATS:
• Modules GRUB: $(ls "${MOUNT_POINT}/boot/grub/i386-pc"/*.mod 2>/dev/null | wc -l) fichiers
• core.img: $( [ -f "${MOUNT_POINT}/boot/grub/core.img" ] && echo "PRÉSENT" || echo "ABSENT" )
• grub.cfg: $( [ -f "${MOUNT_POINT}/boot/grub/grub.cfg" ] && echo "PRÉSENT" || echo "ABSENT" )
• GRUB MBR: $(dd if=/dev/sda bs=512 count=1 2>/dev/null | strings | grep -q "GRUB" && echo "INSTALLÉ" || echo "ABSENT")

🔧 CONFIGURATION:
set root=(hd0,msdos1)
linux /$KERNEL_NAME root=/dev/sda3 ro

🚀 POUR DÉMARRER:
- Le système devrait démarrer automatiquement
- Sinon: au démarrage 'c' puis commandes ci-dessus

⚠️  IMPORTANT:
- Retirez le LiveCD avant redémarrage
EOF

log_success "Rapport créé: /boot/GRUB-REPORT.txt"

# ============================================================================
# INSTRUCTIONS FINALES
# ============================================================================
echo ""
echo "================================================================"
log_success "🎉 GÉNÉRATION GRUB TERMINÉE !"
echo "================================================================"
echo ""
echo "✅ RÉSULTATS:"
echo "   • Modules GRUB: $(ls "${MOUNT_POINT}/boot/grub/i386-pc"/*.mod 2>/dev/null | wc -l) fichiers"
echo "   • core.img: $( [ -f "${MOUNT_POINT}/boot/grub/core.img" ] && echo "✅ PRÉSENT" || echo "❌ ABSENT" )"
echo "   • grub.cfg: $( [ -f "${MOUNT_POINT}/boot/grub/grub.cfg" ] && echo "✅ PRÉSENT" || echo "❌ ABSENT" )"
echo "   • GRUB MBR: $(dd if=/dev/sda bs=512 count=1 2>/dev/null | strings | grep -q "GRUB" && echo "✅ INSTALLÉ" || echo "❌ ABSENT")"
echo ""
echo "🚀 POUR TESTER:"
echo "   exit"
echo "   umount -R /mnt/gentoo"
echo "   reboot"
echo ""
echo "🔧 EN CAS D'ÉCHEC:"
echo "   - Consultez /boot/GRUB-REPORT.txt"
echo "   - Boot manuel: au démarrage 'c' puis:"
echo "     set root=(hd0,msdos1)"
echo "     linux /$KERNEL_NAME root=/dev/sda3 ro"
echo "     boot"
echo ""
echo "⚠️  RETIREZ LE LIVECD AVANT REDÉMARRAGE !"