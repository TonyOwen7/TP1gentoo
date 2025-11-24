#!/bin/bash
# INSTALLATION FORCÉE GRUB DANS MBR - Méthode directe

SECRET_CODE="1234"

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

echo "✅ Code correct, installation FORCÉE GRUB dans MBR..."

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
echo "     INSTALLATION FORCÉE GRUB DANS MBR - MÉTHODE DIRECTE"
echo "================================================================"
echo ""

# ============================================================================
# VÉRIFICATION INITIALE
# ============================================================================
log_info "Vérification initiale..."

# Vérifier qu'on est sur le LiveCD
if [ ! -f "/etc/gentoo-release" ]; then
    log_info "✅ Nous sommes sur le LiveCD - parfait pour l'installation"
else
    log_warning "⚠️  Nous ne sommes pas sur le LiveCD, mais continuons..."
fi

# ============================================================================
# MONTAGE DES PARTITIONS
# ============================================================================
log_info "Montage des partitions..."

# Nettoyage
umount -R "${MOUNT_POINT}" 2>/dev/null || true

# Montage
mount "${DISK}3" "${MOUNT_POINT}" || { log_error "Échec montage racine"; exit 1; }
mkdir -p "${MOUNT_POINT}/boot"
mount "${DISK}1" "${MOUNT_POINT}/boot" || log_warning "Boot déjà monté"

# Montage chroot
mount -t proc /proc "${MOUNT_POINT}/proc"
mount --rbind /sys "${MOUNT_POINT}/sys"
mount --make-rslave "${MOUNT_POINT}/sys"
mount --rbind /dev "${MOUNT_POINT}/dev"
mount --make-rslave "${MOUNT_POINT}/dev"
cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/"

# ============================================================================
# MÉTHODE 1: INSTALLATION GRUB DEPUIS LE LIVECD (DIRECTE)
# ============================================================================
echo ""
log_info "━━━━ MÉTHODE 1: GRUB DU LIVECD → MBR ━━━━"

log_info "Vérification GRUB dans LiveCD..."
if command -v grub-install >/dev/null 2>&1; then
    log_success "✅ GRUB trouvé dans LiveCD: $(which grub-install)"
    
    log_info "Installation DIRECTE dans MBR depuis LiveCD..."
    if grub-install --boot-directory="${MOUNT_POINT}/boot" --target=i386-pc --force "${DISK}" 2>&1; then
        log_success "🎉 GRUB INSTALLÉ DANS MBR avec succès!"
    else
        log_warning "Première méthode échouée, tentative alternative..."
        
        # Essayer différentes options
        grub-install --boot-directory="${MOUNT_POINT}/boot" --force "${DISK}" 2>&1 || \
        grub-install --boot-directory="${MOUNT_POINT}/boot" --recheck "${DISK}" 2>&1 || \
        log_error "Échec installation GRUB depuis LiveCD"
    fi
else
    log_error "❌ GRUB non trouvé dans le LiveCD"
fi

# ============================================================================
# MÉTHODE 2: UTILISATION DE GRUB DEPUIS LE SYSTÈME INSTALLÉ
# ============================================================================
echo ""
log_info "━━━━ MÉTHODE 2: GRUB DU SYSTÈME → MBR ━━━━"

log_info "Vérification GRUB dans le système installé..."
chroot "${MOUNT_POINT}" /bin/bash -c "
  if command -v grub-install >/dev/null 2>&1; then
    echo '[CHROOT] ✅ GRUB trouvé dans le système'
    echo '[CHROOT] Installation dans MBR...'
    
    if grub-install --target=i386-pc --force '${DISK}' 2>&1; then
      echo '[CHROOT] 🎉 GRUB INSTALLÉ DANS MBR avec succès!'
    else
      echo '[CHROOT] ❌ Échec installation GRUB depuis le système'
    fi
  else
    echo '[CHROOT] ❌ GRUB non trouvé dans le système'
  fi
"

# ============================================================================
# MÉTHODE 3: INSTALLATION MANUELLE ULTIME
# ============================================================================
echo ""
log_info "━━━━ MÉTHODE 3: INSTALLATION MANUELLE ULTIME ━━━━"

log_info "Création manuelle des fichiers GRUB..."

# Créer la structure GRUB
mkdir -p "${MOUNT_POINT}/boot/grub"
mkdir -p "${MOUNT_POINT}/boot/grub/i386-pc" 2>/dev/null || true

# Trouver le noyau
KERNEL_FILE=$(ls "${MOUNT_POINT}/boot"/vmlinuz* 2>/dev/null | head -1)
if [ -n "$KERNEL_FILE" ]; then
    KERNEL_NAME=$(basename "$KERNEL_FILE")
    log_success "Noyau détecté: $KERNEL_NAME"
else
    log_error "❌ Aucun noyau trouvé!"
    exit 1
fi

# Créer grub.cfg MANUEL
log_info "Création de grub.cfg..."
cat > "${MOUNT_POINT}/boot/grub/grub.cfg" << EOF
set timeout=5
set default=0

menuentry "Gentoo Linux" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /${KERNEL_NAME} root=/dev/sda3 ro quiet
}

menuentry "Gentoo Linux (secours)" {
    insmod ext2
    insmod part_msdos
    set root=(hd0,msdos1)
    linux /${KERNEL_NAME} root=/dev/sda3 ro single
}
EOF

log_success "grub.cfg créé"

# ============================================================================
# MÉTHODE 4: ÉCRITURE DIRECTE DU MBR
# ============================================================================
echo ""
log_info "━━━━ MÉTHODE 4: ÉCRITURE DIRECTE DU MBR ━━━━"

log_info "Tentative d'écriture directe du bootloader..."

# Méthode manuelle pour écrire le MBR
if command -v grub-install >/dev/null 2>&1; then
    log_info "Utilisation de grub-install pour écriture directe..."
    
    # Essayer avec différentes options
    if grub-install --force --target=i386-pc --boot-directory="${MOUNT_POINT}/boot" "${DISK}" 2>&1; then
        log_success "✅ Bootloader écrit dans MBR"
    else
        log_warning "Échec, tentative avec options réduites..."
        grub-install --boot-directory="${MOUNT_POINT}/boot" "${DISK}" 2>&1 || true
    fi
fi

# ============================================================================
# VÉRIFICATION DU MBR
# ============================================================================
echo ""
log_info "━━━━ VÉRIFICATION DU MBR ━━━━"

log_info "Vérification de la présence de GRUB dans le MBR..."

# Méthode 1: Vérification hexdump
if command -v hexdump >/dev/null 2>&1; then
    log_info "Vérification avec hexdump..."
    if hexdump -C "${DISK}" | head -5 | grep -q "GRUB"; then
        log_success "✅ GRUB DÉTECTÉ dans MBR (hexdump)"
    else
        log_warning "⚠️ GRUB non détecté par hexdump"
    fi
fi

# Méthode 2: Vérification dd + strings
if command -v strings >/dev/null 2>&1; then
    log_info "Vérification avec strings..."
    if dd if="${DISK}" bs=512 count=1 2>/dev/null | strings | grep -q "GRUB"; then
        log_success "✅ GRUB DÉTECTÉ dans MBR (strings)"
    else
        log_warning "⚠️ GRUB non détecté par strings"
    fi
fi

# Méthode 3: Vérification file
if command -v file >/dev/null 2>&1; then
    log_info "Vérification avec file..."
    if dd if="${DISK}" bs=512 count=1 2>/dev/null | file - | grep -q "boot sector"; then
        log_success "✅ Secteur de boot DÉTECTÉ"
    else
        log_warning "⚠️ Secteur de boot non reconnu"
    fi
fi

# ============================================================================
# CRÉATION D'UN SCRIPT DE SECOURS
# ============================================================================
echo ""
log_info "━━━━ CRÉATION SCRIPT DE SECOURS ━━━━"

# Créer un script de secours dans le système
cat > "${MOUNT_POINT}/root/repare_grub_urgence.sh" << 'EOF'
#!/bin/bash
# Script de réparation GRUB d'urgence - À exécuter APRÈS boot

echo "🔧 Réparation GRUB d'urgence..."
if command -v grub-install >/dev/null 2>&1; then
    echo "Installation de GRUB dans MBR..."
    grub-install /dev/sda
    grub-mkconfig -o /boot/grub/grub.cfg
    echo "✅ GRUB réparé"
else
    echo "❌ grub-install non disponible"
    echo "Installez GRUB: emerge sys-boot/grub"
fi
EOF

chmod +x "${MOUNT_POINT}/root/repare_grub_urgence.sh"
log_success "Script de secours créé: /root/repare_grub_urgence.sh"

# ============================================================================
# INSTRUCTIONS DE BOOT MANUEL
# ============================================================================
echo ""
log_info "━━━━ INSTRUCTIONS DE BOOT MANUEL ━━━━"

cat > "${MOUNT_POINT}/boot/INSTRUCTIONS-BOOT.txt" << EOF
🆘 INSTRUCTIONS POUR BOOT MANUEL

Si le système ne démarre pas, suivez ces étapes:

1. Au démarrage, APPUYEZ SUR 'c' pour entrer dans la console GRUB
2. Entrez les commandes EXACTEMENT comme suit:

   set root=(hd0,msdos1)
   linux /${KERNEL_NAME} root=/dev/sda3 ro
   boot

3. Une fois connecté, exécutez:
   /root/repare_grub_urgence.sh

OU installez GRUB manuellement:
   grub-install /dev/sda
   grub-mkconfig -o /boot/grub/grub.cfg

Configuration:
- Disque: ${DISK}
- Noyau: ${KERNEL_NAME}
- Partition root: /dev/sda3
- Partition boot: /dev/sda1
EOF

log_success "Instructions créées: /boot/INSTRUCTIONS-BOOT.txt"

# ============================================================================
# RÉCAPITULATIF FINAL
# ============================================================================
echo ""
echo "================================================================"
log_info "RÉCAPITULATIF FINAL"
echo "================================================================"

echo ""
echo "📁 CONTENU DE /boot/:"
ls -la "${MOUNT_POINT}/boot/" | head -10

echo ""
echo "📄 FICHIER grub.cfg:"
if [ -f "${MOUNT_POINT}/boot/grub/grub.cfg" ]; then
    echo "✅ PRÉSENT"
    echo "--- Extrait ---"
    grep "^menuentry" "${MOUNT_POINT}/boot/grub/grub.cfg" | head -2
else
    echo "❌ ABSENT"
fi

echo ""
echo "🐧 NOYAU:"
ls "${MOUNT_POINT}/boot/vmlinuz"* 2>/dev/null && echo "✅ PRÉSENT" || echo "❌ ABSENT"

echo ""
echo "🔧 RÉSULTAT INSTALLATION MBR:"
if command -v hexdump >/dev/null 2>&1 && hexdump -C "${DISK}" 2>/dev/null | head -5 | grep -q "GRUB"; then
    log_success "🎉 GRUB EST DANS LE MBR!"
else
    log_warning "⚠️ GRUB PEUT NE PAS ÊTRE DANS LE MBR"
    log_info "Utilisez les instructions de boot manuel si nécessaire"
fi

# ============================================================================
# DÉMONTAGE ET REDÉMARRAGE
# ============================================================================
echo ""
echo "================================================================"
log_success "INSTALLATION TERMINÉE"
echo "================================================================"
echo ""
echo "🚀 POUR REDÉMARRER:"
echo "   exit"
echo "   umount -R /mnt/gentoo"
echo "   reboot"
echo ""
echo "🔧 EN CAS DE PROBLÈME:"
echo "   1. Au démarrage: Appuyer sur 'c' pour GRUB"
echo "   2. Utiliser les commandes de boot manuel"
echo "   3. Une fois booté: /root/repare_grub_urgence.sh"
echo ""
echo "⚠️  IMPORTANT: Retirez le LiveCD avant de redémarrer!"
echo "   VirtualBox: Paramètres > Stockage > Contrôleur > Démonter l'ISO"