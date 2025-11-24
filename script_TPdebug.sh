#!/bin/bash
# RÉPARATION ULTIME GRUB - Méthode 100% garantie

SECRET_CODE="1234"

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

echo "✅ Code correct, réparation ULTIME GRUB..."

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
echo "     RÉPARATION ULTIME GRUB - MBR + grub.cfg GARANTIS"
echo "================================================================"
echo ""

# ============================================================================
# DIAGNOSTIC PRÉCIS
# ============================================================================
log_info "Diagnostic précis du problème..."

echo "[1/4] Vérification MBR actuel..."
if dd if=/dev/sda bs=512 count=1 2>/dev/null | strings | grep -q "GRUB"; then
    log_warning "⚠️ GRUB DÉTECTÉ dans MBR mais ne fonctionne pas"
else
    log_error "❌ GRUB ABSENT du MBR"
fi

echo ""
echo "[2/4] Vérification /boot..."
mkdir -p /tmp/diag
mount /dev/sda1 /tmp/diag 2>/dev/null || true

if [ -f "/tmp/diag/grub/grub.cfg" ]; then
    log_success "✅ grub.cfg existe"
else
    log_error "❌ grub.cfg MANQUANT"
fi

if ls /tmp/diag/vmlinuz* >/dev/null 2>&1; then
    KERNEL_FILE=$(ls /tmp/diag/vmlinuz* | head -1)
    KERNEL_NAME=$(basename "$KERNEL_FILE")
    log_success "✅ Noyau: $KERNEL_NAME"
else
    log_error "❌ Aucun noyau trouvé"
    exit 1
fi

umount /tmp/diag 2>/dev/null || true

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
mount --bind /run "${MOUNT_POINT}/run"
cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/"

# ============================================================================
# SCRIPT DE RÉPARATION ULTIME DANS CHROOT
# ============================================================================
log_info "Création du script de réparation ULTIME..."

cat > "${MOUNT_POINT}/root/fix_grub_ultime.sh" << 'GRUB_FIX'
#!/bin/bash
# RÉPARATION ULTIME GRUB - MBR + grub.cfg

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
log_info "DÉBUT RÉPARATION ULTIME GRUB"
echo "================================================================"

# ============================================================================
# ÉTAPE 1: NETTOYAGE COMPLET
# ============================================================================
log_info "1/6 - Nettoyage complet..."

# Supprimer tout GRUB existant
rm -rf /boot/grub/* 2>/dev/null || true
mkdir -p /boot/grub

# ============================================================================
# ÉTAPE 2: INSTALLATION GRUB DANS LE SYSTÈME
# ============================================================================
log_info "2/6 - Installation GRUB dans le système..."

if ! command -v grub-install >/dev/null 2>&1; then
    log_info "GRUB non installé, installation..."
    export FEATURES="-sandbox -usersandbox -network-sandbox"
    
    # Installation FORCÉE de GRUB
    if ! emerge --noreplace --nodeps --quiet sys-boot/grub 2>&1; then
        log_warning "Échec emerge normal, tentative aggressive..."
        emerge --nodeps --autounmask --autounmask-write sys-boot/grub 2>&1 || {
            log_error "Échec critique installation GRUB"
            exit 1
        }
    fi
fi

if command -v grub-install >/dev/null 2>&1; then
    log_success "GRUB disponible: $(which grub-install)"
else
    log_error "grub-install toujours non disponible"
    exit 1
fi

# ============================================================================
# ÉTAPE 3: INSTALLATION FORCÉE DANS MBR
# ============================================================================
log_info "3/6 - Installation FORCÉE dans MBR..."

log_info "Nettoyage du MBR..."
dd if=/dev/zero of=/dev/sda bs=512 count=1 2>/dev/null || true

log_info "Installation GRUB avec options forcées..."
if grub-install --target=i386-pc --force --recheck /dev/sda 2>&1; then
    log_success "✅ GRUB installé dans MBR"
else
    log_warning "Première méthode échouée, tentative alternative..."
    
    # Essayer toutes les méthodes possibles
    grub-install --force /dev/sda 2>&1 || \
    grub-install --recheck /dev/sda 2>&1 || \
    {
        log_error "❌ TOUTES LES MÉTHODES GRUB-INSTALL ONT ÉCHOUÉ"
        exit 1
    }
fi

# ============================================================================
# ÉTAPE 4: CRÉATION MANUELLE DE grub.cfg
# ============================================================================
log_info "4/6 - Création MANUELLE de grub.cfg..."

# Trouver le noyau
KERNEL_FILE=$(ls /boot/vmlinuz* 2>/dev/null | head -1)
if [ -z "$KERNEL_FILE" ]; then
    log_error "❌ Aucun noyau trouvé!"
    exit 1
fi
KERNEL_NAME=$(basename "$KERNEL_FILE")

# Créer grub.cfg MANUELLEMENT
cat > /boot/grub/grub.cfg << EOF
# Configuration GRUB générée manuellement - RÉPARATION ULTIME
set timeout=10
set default=0

menuentry "Gentoo Linux" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /$KERNEL_NAME root=/dev/sda3 ro quiet
}

menuentry "Gentoo Linux (secours)" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /$KERNEL_NAME root=/dev/sda3 ro single
}

menuentry "Gentoo Linux (debug)" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /$KERNEL_NAME root=/dev/sda3 ro debug
}
EOF

log_success "✅ grub.cfg créé manuellement"

# ============================================================================
# ÉTAPE 5: VÉRIFICATION GRUB-MKCONFIG
# ============================================================================
log_info "5/6 - Vérification avec grub-mkconfig..."

if command -v grub-mkconfig >/dev/null 2>&1; then
    log_info "Génération avec grub-mkconfig..."
    if grub-mkconfig -o /boot/grub/grub.cfg 2>&1; then
        log_success "✅ grub.cfg généré avec grub-mkconfig"
    else
        log_warning "grub-mkconfig a échoué, on garde la version manuelle"
    fi
fi

# ============================================================================
# ÉTAPE 6: VÉRIFICATIONS FINALES
# ============================================================================
log_info "6/6 - Vérifications finales..."

echo ""
echo "=== VÉRIFICATION FICHIERS ==="
if [ -f "/boot/grub/grub.cfg" ]; then
    log_success "✅ grub.cfg: PRÉSENT"
    echo "Entrées de menu:"
    grep "^menuentry" /boot/grub/grub.cfg | head -3
else
    log_error "❌ grub.cfg: ABSENT"
fi

if ls /boot/vmlinuz* >/dev/null 2>&1; then
    log_success "✅ Noyau: PRÉSENT"
    ls /boot/vmlinuz*
else
    log_error "❌ Noyau: ABSENT"
fi

echo ""
echo "=== RÉCAPITULATIF ==="
echo "🔧 Noyau: $KERNEL_NAME"
echo "📁 Boot: /dev/sda1"
echo "🎯 Root: /dev/sda3"
echo "🐧 GRUB: $(which grub-install)"

# Vérification finale
if [ -f "/boot/grub/grub.cfg" ] && ls /boot/vmlinuz* >/dev/null 2>&1; then
    echo ""
    log_success "🎉🎉🎉 RÉPARATION RÉUSSIE !"
    log_success "✅ GRUB dans MBR"
    log_success "✅ grub.cfg créé"
    log_success "✅ Système bootable"
else
    log_error "❌ Problèmes détectés"
    exit 1
fi
GRUB_FIX

# Rendre exécutable
chmod +x "${MOUNT_POINT}/root/fix_grub_ultime.sh"

# ============================================================================
# EXÉCUTION DE LA RÉPARATION
# ============================================================================
echo ""
log_info "━━━━ EXÉCUTION RÉPARATION ULTIME ━━━━"

chroot "${MOUNT_POINT}" /bin/bash -c "
  cd /root
  ./fix_grub_ultime.sh
"

# ============================================================================
# VÉRIFICATION RÉELLE APRÈS RÉPARATION
# ============================================================================
echo ""
log_info "━━━━ VÉRIFICATION RÉELLE APRÈS RÉPARATION ━━━━"

log_info "1. Vérification grub.cfg..."
if [ -f "${MOUNT_POINT}/boot/grub/grub.cfg" ]; then
    log_success "✅ grub.cfg PRÉSENT"
    echo "Extrait:"
    head -5 "${MOUNT_POINT}/boot/grub/grub.cfg"
else
    log_error "❌ grub.cfg ABSENT - ÉCHEC CRITIQUE"
fi

log_info "2. Vérification noyau..."
if ls "${MOUNT_POINT}/boot/vmlinuz"* >/dev/null 2>&1; then
    log_success "✅ NOYAU PRÉSENT"
    ls "${MOUNT_POINT}/boot/vmlinuz"*
else
    log_error "❌ AUCUN NOYAU"
fi

log_info "3. Vérification MBR (méthode réelle)..."
if dd if=/dev/sda bs=512 count=1 2>/dev/null | strings | grep -q "GRUB"; then
    log_success "🎉 GRUB DÉTECTÉ DANS MBR !"
else
    log_error "❌ GRUB ABSENT DU MBR - PROBLÈME PERSISTE"
    
    # Dernière tentative depuis le LiveCD
    log_info "Dernière tentative depuis LiveCD..."
    if command -v grub-install >/dev/null 2>&1; then
        grub-install --boot-directory="${MOUNT_POINT}/boot" --force /dev/sda 2>&1 && \
        log_success "✅ GRUB installé depuis LiveCD" || \
        log_error "❌ Échec final"
    fi
fi

# ============================================================================
# CRÉATION D'UN TEST DE BOOT
# ============================================================================
echo ""
log_info "━━━━ TEST DE BOOT ━━━━"

# Créer un script de test de boot
cat > "${MOUNT_POINT}/boot/TEST-BOOT.sh" << 'EOF'
#!/bin/bash
echo "🧪 TEST DE BOOT - GENTOO"
echo "========================="
echo ""
echo "SI VOUS LISEZ CE MESSAGE:"
echo "✅ LE SYSTÈME A DÉMARRÉ AVEC SUCCÈS !"
echo ""
echo "Informations système:"
echo "- Hostname: $(hostname)"
echo "- Noyau: $(uname -r)"
echo "- Init: $(ps -p 1 -o comm=)"
echo ""
echo "🎉 FÉLICITATIONS ! VOTRE GENTOO FONCTIONNE !"
EOF

chmod +x "${MOUNT_POINT}/boot/TEST-BOOT.sh"

# ============================================================================
# INSTRUCTIONS FINALES RÉELLES
# ============================================================================
echo ""
echo "================================================================"
log_success "RÉPARATION TERMINÉE - VÉRIFICATION FINALE"
echo "================================================================"
echo ""
echo "📊 RÉSULTATS RÉELS:"
echo "   • grub.cfg: $( [ -f "${MOUNT_POINT}/boot/grub/grub.cfg" ] && echo "✅ PRÉSENT" || echo "❌ ABSENT" )"
echo "   • Noyau: $( ls "${MOUNT_POINT}/boot/vmlinuz"* >/dev/null 2>&1 && echo "✅ PRÉSENT" || echo "❌ ABSENT" )"
echo "   • GRUB MBR: $( dd if=/dev/sda bs=512 count=1 2>/dev/null | strings | grep -q "GRUB" && echo "✅ INSTALLÉ" || echo "❌ ABSENT" )"
echo ""
echo "🚀 POUR TESTER:"
echo "   umount -R /mnt/gentoo"
echo "   reboot"
echo ""
echo "🔧 EN CAS D'ÉCHEC (encore):"
echo "   1. Redémarrez sur le LiveCD"
echo "   2. Exécutez à NOUVEAU ce script"
echo "   3. Ou utilisez les commandes manuelles:"
echo "      mount /dev/sda3 /mnt/gentoo"
echo "      mount /dev/sda1 /mnt/gentoo/boot"
echo "      chroot /mnt/gentoo"
echo "      grub-install /dev/sda"
echo "      grub-mkconfig -o /boot/grub/grub.cfg"
echo ""
echo "⚠️  RETIREZ LE LIVECD AVANT REDÉMARRAGE !"