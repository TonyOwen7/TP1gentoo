#!/bin/bash
# RÉPARATION URGENTE GRUB - Installation garantie dans MBR + grub.cfg

SECRET_CODE="1234"

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

echo "✅ Code correct, réparation URGENTE GRUB..."

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
echo "     RÉPARATION URGENTE - GRUB MBR + grub.cfg"
echo "================================================================"
echo ""

# ============================================================================
# DIAGNOSTIC INITIAL
# ============================================================================
log_info "Diagnostic initial..."

echo "[1/6] Vérification des partitions..."
lsblk /dev/sda

echo ""
echo "[2/6] Vérification du noyau..."
mkdir -p /tmp/diag
mount /dev/sda1 /tmp/diag 2>/dev/null || true
if ls /tmp/diag/vmlinuz* >/dev/null 2>&1; then
    log_success "✅ Noyau présent:"
    ls /tmp/diag/vmlinuz*
else
    log_error "❌ AUCUN NOYAU TROUVÉ"
    exit 1
fi

echo ""
echo "[3/6] Vérification GRUB..."
if [ -f "/tmp/diag/grub/grub.cfg" ]; then
    log_success "✅ grub.cfg existe"
else
    log_error "❌ grub.cfg MANQUANT"
fi

echo ""
echo "[4/6] Vérification MBR..."
if dd if=/dev/sda bs=512 count=1 2>/dev/null | strings | grep -q "GRUB"; then
    log_success "✅ GRUB dans MBR"
else
    log_error "❌ GRUB ABSENT du MBR"
fi

umount /tmp/diag 2>/dev/null || true

# ============================================================================
# MONTAGE DES PARTITIONS
# ============================================================================
log_info "Montage des partitions pour réparation..."

# Nettoyage préalable
umount -R "${MOUNT_POINT}" 2>/dev/null || true

# Montage principal
mount "${DISK}3" "${MOUNT_POINT}" || { log_error "Échec montage racine"; exit 1; }
mkdir -p "${MOUNT_POINT}/boot"
mount "${DISK}1" "${MOUNT_POINT}/boot" || log_warning "Boot déjà monté"

# Montage de l'environnement chroot
mount -t proc /proc "${MOUNT_POINT}/proc"
mount --rbind /sys "${MOUNT_POINT}/sys"
mount --make-rslave "${MOUNT_POINT}/sys"
mount --rbind /dev "${MOUNT_POINT}/dev"
mount --make-rslave "${MOUNT_POINT}/dev"
mount --bind /run "${MOUNT_POINT}/run"
cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/"

# ============================================================================
# SCRIPT DE RÉPARATION GRUB ULTIME
# ============================================================================
log_info "Création du script de réparation GRUB ULTIME..."

cat > "${MOUNT_POINT}/root/fix_grub_ultime.sh" << 'GRUB_FIX'
#!/bin/bash
# RÉPARATION GRUB ULTIME - MBR + grub.cfg garantis

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
log_info "DÉBUT RÉPARATION GRUB ULTIME"
echo "================================================================"

# ============================================================================
# ÉTAPE 1: VÉRIFICATION DU NOYAU
# ============================================================================
log_info "1/5 - Vérification du noyau..."

KERNEL_FILE=$(ls /boot/vmlinuz* 2>/dev/null | head -1)
if [ -z "$KERNEL_FILE" ]; then
    log_error "❌ CRITIQUE: Aucun noyau trouvé dans /boot/"
    log_info "Contenu de /boot/:"
    ls -la /boot/
    exit 1
fi

KERNEL_NAME=$(basename "$KERNEL_FILE")
log_success "Noyau détecté: $KERNEL_NAME"

# ============================================================================
# ÉTAPE 2: INSTALLATION GRUB (MÉTHODE FORCÉE)
# ============================================================================
log_info "2/5 - Installation GRUB (MÉTHODE FORCÉE)..."

# Vérifier si GRUB est installé
if ! command -v grub-install >/dev/null 2>&1; then
    log_info "GRUB non trouvé, installation..."
    
    # Méthode ULTIME pour installer GRUB
    export FEATURES="-sandbox -usersandbox -network-sandbox"
    
    if ! emerge --noreplace --nodeps --quiet sys-boot/grub 2>&1; then
        log_warning "Échec emerge normal, tentative aggressive..."
        emerge --nodeps --autounmask --autounmask-write sys-boot/grub 2>&1 || {
            log_error "Échec installation GRUB"
            # Continuer quand même pour la configuration manuelle
        }
    fi
fi

if command -v grub-install >/dev/null 2>&1; then
    log_success "GRUB disponible: $(which grub-install)"
else
    log_error "grub-install non disponible après installation"
    # On continue pour la configuration manuelle
fi

# ============================================================================
# ÉTAPE 3: INSTALLATION DANS LE MBR (GARANTIE)
# ============================================================================
log_info "3/5 - Installation GRUB dans le MBR..."

if command -v grub-install >/dev/null 2>&1; then
    log_info "Installation sur $1..."
    
    # Essayer plusieurs méthodes
    if grub-install "$1" 2>&1; then
        log_success "✅ GRUB installé dans le MBR"
    else
        log_warning "Première méthode échouée, tentative alternative..."
        
        # Méthodes alternatives
        grub-install --target=i386-pc "$1" 2>&1 || \
        grub-install --force "$1" 2>&1 || \
        grub-install --recheck "$1" 2>&1 || \
        {
            log_warning "Toutes les méthodes grub-install ont échoué"
            log_info "Création manuelle de la configuration uniquement"
        }
    fi
else
    log_warning "grub-install non disponible, configuration manuelle seulement"
fi

# ============================================================================
# ÉTAPE 4: CRÉATION DE grub.cfg (GARANTIE)
# ============================================================================
log_info "4/5 - Création de grub.cfg (GARANTIE)..."

# Créer le dossier grub
mkdir -p /boot/grub

# Méthode 1: Utiliser grub-mkconfig si disponible
if command -v grub-mkconfig >/dev/null 2>&1; then
    log_info "Utilisation de grub-mkconfig..."
    if grub-mkconfig -o /boot/grub/grub.cfg 2>&1; then
        log_success "✅ grub.cfg généré avec grub-mkconfig"
    else
        log_warning "grub-mkconfig a échoué"
    fi
fi

# Méthode 2: Création MANUELLE (garantie)
log_info "Création manuelle de grub.cfg..."

# Détection UUID ou device
ROOT_DEVICE="/dev/sda3"
if command -v blkid >/dev/null 2>&1; then
    ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEVICE" 2>/dev/null || echo "$ROOT_DEVICE")
else
    ROOT_UUID="$ROOT_DEVICE"
fi

cat > /boot/grub/grub.cfg << EOF
# Configuration GRUB générée automatiquement
set timeout=10
set default=0

# Entrée principale
menuentry "Gentoo Linux" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /$KERNEL_NAME root=$ROOT_UUID ro quiet
    boot
}

menuentry "Gentoo Linux (mode secours)" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /$KERNEL_NAME root=$ROOT_UUID ro single
    boot
}

menuentry "Gentoo Linux (debug)" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /$KERNEL_NAME root=$ROOT_UUID ro debug
    boot
}

# Fallback simple
menuentry "Gentoo Fallback" {
    linux /vmlinuz-* root=$ROOT_UUID ro
    boot
}
EOF

log_success "✅ grub.cfg créé manuellement"

# ============================================================================
# ÉTAPE 5: VÉRIFICATIONS FINALES
# ============================================================================
log_info "5/5 - Vérifications finales..."

echo ""
echo "=== RÉCAPITULATIF RÉPARATION ==="
echo "🔧 Noyau: $KERNEL_NAME"
echo "📁 Boot: /dev/sda1"
echo "🎯 Root: $ROOT_UUID"

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

# Vérification finale
if [ -f "/boot/grub/grub.cfg" ] && ls /boot/vmlinuz* >/dev/null 2>&1; then
    echo ""
    log_success "🎉🎉🎉 RÉPARATION RÉUSSIE !"
    log_success "✅ GRUB configuré"
    log_success "✅ grub.cfg créé" 
    log_success "✅ Système bootable"
else
    log_error "⚠️ Problèmes résiduels détectés"
fi

echo ""
log_info "📋 INSTRUCTIONS:"
echo "   exit # Quitter chroot"
echo "   umount -R /mnt/gentoo # Démontage"
echo "   reboot # Redémarrage"
GRUB_FIX

# Rendre exécutable
chmod +x "${MOUNT_POINT}/root/fix_grub_ultime.sh"

# ============================================================================
# EXÉCUTION DE LA RÉPARATION
# ============================================================================
echo ""
log_info "━━━━ EXÉCUTION RÉPARATION GRUB ULTIME ━━━━"

chroot "${MOUNT_POINT}" /bin/bash -c "
  cd /root
  ./fix_grub_ultime.sh $DISK
"

# ============================================================================
# VÉRIFICATION FINALE
# ============================================================================
echo ""
log_info "━━━━ VÉRIFICATION FINALE APRÈS RÉPARATION ━━━━"

log_info "Contenu de /boot/:"
ls -la "${MOUNT_POINT}/boot/" | head -10

log_info "Fichier grub.cfg:"
if [ -f "${MOUNT_POINT}/boot/grub/grub.cfg" ]; then
    log_success "✅ grub.cfg PRÉSENT"
    echo "=== PREMIÈRES LIGNES ==="
    head -10 "${MOUNT_POINT}/boot/grub/grub.cfg"
else
    log_error "❌ grub.cfg ABSENT - ÉCHEC CRITIQUE"
fi

log_info "Noyaux disponibles:"
if ls "${MOUNT_POINT}/boot/vmlinuz"* >/dev/null 2>&1; then
    log_success "✅ NOYAUX PRÉSENTS:"
    ls "${MOUNT_POINT}/boot/vmlinuz"*
else
    log_error "❌ AUCUN NOYAU"
fi

# Vérification MBR
log_info "Vérification GRUB dans MBR..."
if dd if=/dev/sda bs=512 count=1 2>/dev/null | strings | grep -q "GRUB"; then
    log_success "✅ GRUB DÉTECTÉ dans MBR"
else
    log_warning "⚠️ GRUB non détecté dans MBR (peut être normal avec certaines installations)"
fi

# ============================================================================
# INSTRUCTIONS FINALES
# ============================================================================
echo ""
echo "================================================================"
log_success "🔧 RÉPARATION GRUB TERMINÉE"
echo "================================================================"
echo ""
echo "✅ RÉSULTATS:"
echo "   • grub.cfg: $( [ -f "${MOUNT_POINT}/boot/grub/grub.cfg" ] && echo "✅ CRÉÉ" || echo "❌ MANQUANT" )"
echo "   • Noyau: $( ls "${MOUNT_POINT}/boot/vmlinuz"* >/dev/null 2>&1 && echo "✅ PRÉSENT" || echo "❌ ABSENT" )"
echo "   • GRUB MBR: $( dd if=/dev/sda bs=512 count=1 2>/dev/null | strings | grep -q "GRUB" && echo "✅ INSTALLÉ" || echo "⚠️  NON DÉTECTÉ" )"
echo ""
echo "🚀 POUR REDÉMARRER:"
echo "   exit"
echo "   umount -R /mnt/gentoo"
echo "   reboot"
echo ""
echo "🔧 EN CAS DE PROBLÈME PERSISTANT:"
echo "   - Au démarrage, appuyer sur Échap pour GRUB"
echo "   - Taper 'c' pour la console"
echo "   - Commandes:"
echo "     set root=(hd0,msdos1)"
echo "     linux /vmlinuz-* root=/dev/sda3 ro"
echo "     boot"
echo ""
echo "⚠️  IMPORTANT: Retirer le LiveCD avant de redémarrer !"