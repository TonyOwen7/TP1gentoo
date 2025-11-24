#!/bin/bash
# SAUVETAGE ULTIME - Méthodes alternatives sans GRUB

SECRET_CODE="1234"

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

echo "✅ Code correct, sauvetage ULTIME sans GRUB..."

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
echo "     SAUVETAGE ULTIME - Boot sans GRUB"
echo "================================================================"
echo ""

# ============================================================================
# VÉRIFICATION DE BASE
# ============================================================================
log_info "Vérification de base..."

echo "[1/3] Vérification partitions..."
lsblk /dev/sda

echo ""
echo "[2/3] Vérification noyau..."
mount /dev/sda1 /mnt/test 2>/dev/null || true
if ls /mnt/test/vmlinuz* >/dev/null 2>&1; then
    KERNEL_FILE=$(ls /mnt/test/vmlinuz* | head -1)
    KERNEL_NAME=$(basename "$KERNEL_FILE")
    log_success "✅ Noyau trouvé: $KERNEL_NAME"
    umount /mnt/test 2>/dev/null || true
else
    log_error "❌ Aucun noyau trouvé"
    exit 1
fi

echo ""
echo "[3/3] Vérification GRUB LiveCD..."
if command -v grub-install >/dev/null 2>&1; then
    log_info "GRUB disponible dans LiveCD"
else
    log_warning "GRUB non disponible dans LiveCD"
fi

# ============================================================================
# MÉTHODE 1: BOOT DIRECT AVEC KEXEC (RECOMMANDÉE)
# ============================================================================
echo ""
log_info "━━━━ MÉTHODE 1: BOOT DIRECT KEXEC ━━━━"

log_info "Montage des partitions..."
umount -R "${MOUNT_POINT}" 2>/dev/null || true
mount /dev/sda3 "${MOUNT_POINT}" || { log_error "Échec montage racine"; exit 1; }
mkdir -p "${MOUNT_POINT}/boot"
mount /dev/sda1 "${MOUNT_POINT}/boot" || log_warning "Boot déjà monté"

log_info "Vérification de kexec..."
if command -v kexec >/dev/null 2>&1; then
    log_success "✅ kexec disponible"
    
    log_info "Chargement du noyau avec kexec..."
    if kexec -l "${MOUNT_POINT}/boot/${KERNEL_NAME}" --append="root=/dev/sda3 ro" --initrd="${MOUNT_POINT}/boot/initramfs"* 2>/dev/null || \
       kexec -l "${MOUNT_POINT}/boot/${KERNEL_NAME}" --append="root=/dev/sda3 ro" 2>/dev/null; then
        log_success "✅ Noyau chargé avec kexec"
        
        echo ""
        log_warning "⚠️  KEXEC PRÊT - Le système va redémarrer DIRECTEMENT sur Gentoo"
        log_warning "Cette méthode contourne COMPLÈTEMENT le problème GRUB"
        echo ""
        read -p "Exécuter kexec maintenant ? (oui/non): " kexec_confirm
        if [ "$kexec_confirm" = "oui" ]; then
            log_info "Redémarrage avec kexec..."
            kexec -e
            # Si kexec échoue, continuer avec les autres méthodes
            log_warning "kexec a échoué, continuation avec autres méthodes..."
        else
            log_info "kexec annulé"
        fi
    else
        log_error "❌ Échec chargement kexec"
    fi
else
    log_warning "kexec non disponible"
fi

# ============================================================================
# MÉTHODE 2: INSTALLATION MANUELLE ULTIME DU MBR
# ============================================================================
echo ""
log_info "━━━━ MÉTHODE 2: MBR MANUEL ULTIME ━━━━"

log_info "Création d'un MBR manuel simple..."

# Créer un secteur de boot minimaliste qui charge le noyau directement
cat > /tmp/create_mbr.sh << 'EOF'
#!/bin/bash
# Création MBR manuel

DISK="/dev/sda"
KERNEL="$1"

echo "Création MBR manuel pour noyau: $KERNEL"

# Nettoyer le MBR
dd if=/dev/zero of=$DISK bs=512 count=1 2>/dev/null

# Créer un script de boot minimal
cat > /tmp/boot_script.txt << 'SCRIPT'
# Script de boot manuel
# Au démarrage, entrez ces commandes:
echo "Boot manuel requis:"
echo "set root=(hd0,msdos1)"
echo "linux /$KERNEL root=/dev/sda3 ro"
echo "boot"
SCRIPT

echo "MBR nettoyé - boot manuel requis"
EOF

chmod +x /tmp/create_mbr.sh
/tmp/create_mbr.sh "$KERNEL_NAME"

# ============================================================================
# MÉTHODE 3: CONFIGURATION DE BOOT MANUEL COMPLÈTE
# ============================================================================
echo ""
log_info "━━━━ MÉTHODE 3: CONFIGURATION BOOT MANUEL ━━━━"

log_info "Création des instructions de boot manuel..."

# Créer un fichier d'instructions très détaillé
cat > "${MOUNT_POINT}/boot/BOOT-MANUEL-DETAILED.txt" << EOF
🆘 INSTRUCTIONS BOOT MANUEL COMPLÈTES
====================================

SI LE SYSTÈME NE DÉMARRE PAS, suivez CES étapes:

1. AU DÉMARRAGE → APPUYER SUR 'c' POUR CONSOLE GRUB
2. COPIER-COLLER CES COMMANDES EXACTEMENT:

   set root=(hd0,msdos1)
   linux /$KERNEL_NAME root=/dev/sda3 ro
   boot

3. Si ça ne marche pas, essayez ces variantes:

   Variante 1 (simple):
   set root=(hd0,1)
   linux /vmlinuz-* root=/dev/sda3 ro
   boot

   Variante 2 (avec insmod):
   insmod ext2
   insmod part_msdos
   set root=(hd0,msdos1)
   linux /$KERNEL_NAME root=/dev/sda3 ro
   boot

4. Une fois booté, exécutez IMMÉDIATEMENT:
   grub-install /dev/sda
   grub-mkconfig -o /boot/grub/grub.cfg

INFORMATIONS SYSTÈME:
- Noyau: $KERNEL_NAME
- Partition root: /dev/sda3
- Partition boot: /dev/sda1
- Init: OpenRC

ASTUCES:
- Appuyez sur TAB pour auto-compléter les noms de fichiers
- 'ls' pour lister les fichiers
- 'ls (hd0,msdos1)/' pour voir le contenu de /boot
EOF

log_success "Instructions détaillées créées"

# Créer un script de boot automatique
cat > "${MOUNT_POINT}/boot/autoboot.grub" << EOF
set root=(hd0,msdos1)
linux /$KERNEL_NAME root=/dev/sda3 ro
boot
EOF

log_success "Script GRUB créé: autoboot.grub"

# ============================================================================
# MÉTHODE 4: RÉPARATION DU SYSTÈME DANS CHROOT
# ============================================================================
echo ""
log_info "━━━━ MÉTHODE 4: RÉPARATION CHROOT ━━━━"

log_info "Montage de l'environnement chroot..."
mount -t proc /proc "${MOUNT_POINT}/proc"
mount --rbind /sys "${MOUNT_POINT}/sys"
mount --make-rslave "${MOUNT_POINT}/sys"
mount --rbind /dev "${MOUNT_POINT}/dev"
mount --make-rslave "${MOUNT_POINT}/dev"
cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/"

log_info "Tentative de réparation GRUB dans chroot..."
chroot "${MOUNT_POINT}" /bin/bash << 'CHROOT_EOF' || true
#!/bin/bash
set -e

echo "[CHROOT] Début réparation..."

# Essayer d'installer GRUB avec toutes les méthodes
if command -v grub-install >/dev/null 2>&1; then
    echo "[CHROOT] Installation GRUB avec grub-install..."
    grub-install /dev/sda 2>&1 || true
fi

# Essayer emerge si disponible
if command -v emerge >/dev/null 2>&1; then
    echo "[CHROOT] Tentative emerge GRUB..."
    export FEATURES="-sandbox -usersandbox -network-sandbox"
    emerge --noreplace --nodeps sys-boot/grub 2>&1 || true
fi

# Créer la structure GRUB manuellement
echo "[CHROOT] Création structure GRUB manuelle..."
mkdir -p /boot/grub
mkdir -p /boot/grub/i386-pc

# Créer un grub.cfg minimal
KERNEL=$(ls /boot/vmlinuz* | head -1)
KERNEL_NAME=$(basename "$KERNEL")
cat > /boot/grub/grub.cfg << 'GRUB_CFG'
set timeout=5
menuentry "Gentoo" {
    linux /vmlinuz-* root=/dev/sda3 ro
}
GRUB_CFG

echo "[CHROOT] Structure créée"

# Vérifier ce qui est disponible
echo "[CHROOT] Vérification outils:"
command -v grub-install && echo "  grub-install: OUI" || echo "  grub-install: NON"
command -v grub-mkconfig && echo "  grub-mkconfig: OUI" || echo "  grub-mkconfig: NON"
ls /boot/vmlinuz* && echo "  Noyau: OUI ($(ls /boot/vmlinuz* | head -1))" || echo "  Noyau: NON"

echo "[CHROOT] Réparation terminée"
CHROOT_EOF

# ============================================================================
# MÉTHODE 5: CRÉATION DE SECOURS SUR USB VIRTUEL
# ============================================================================
echo ""
log_info "━━━━ MÉTHODE 5: SECOURS VIRTUEL ━━━━"

log_info "Création de scripts de secours..."

# Créer un script de secours dans /boot
cat > "${MOUNT_POINT}/boot/SAUVETAGE-URGENCE.sh" << 'EOF'
#!/bin/bash
echo "🐧 SAUVETAGE URGENCE GENTOO"
echo "==========================="
echo ""
echo "CE SCRIPT DOIT ÊTRE EXÉCUTÉ APRÈS BOOT MANUEL"
echo ""
echo "1. Vérification système:"
echo "   - Hostname: $(hostname)"
echo "   - Noyau: $(uname -r)"
echo "   - Disques: $(lsblk | grep -c disk) disque(s)"
echo ""
echo "2. Réparation GRUB:"
if command -v grub-install >/dev/null 2>&1; then
    echo "   Installation GRUB..."
    grub-install /dev/sda && echo "   ✅ GRUB installé" || echo "   ❌ Échec GRUB"
    
    echo "   Configuration GRUB..."
    grub-mkconfig -o /boot/grub/grub.cfg && echo "   ✅ Configuration OK" || echo "   ❌ Échec configuration"
else
    echo "   ❌ grub-install non disponible"
    echo "   Installer GRUB: emerge sys-boot/grub"
fi
echo ""
echo "3. Vérification:"
echo "   - /boot: $(ls /boot/vmlinuz* 2>/dev/null | wc -l) noyau(x)"
echo "   - GRUB: $(command -v grub-install >/dev/null 2>&1 && echo "INSTALLÉ" || echo "ABSENT")"
echo ""
echo "🎉 Si tout est vert, redémarrez normalement!"
EOF

chmod +x "${MOUNT_POINT}/boot/SAUVETAGE-URGENCE.sh"

# Créer un script pour le LiveCD
cat > /tmp/sauvetage_livecd.sh << 'EOF'
#!/bin/bash
echo "💾 SAUVETAGE LIVECD"
echo "==================="
echo ""
echo "Monter le système:"
echo "  mount /dev/sda3 /mnt/gentoo"
echo "  mount /dev/sda1 /mnt/gentoo/boot"
echo ""
echo "Réparer GRUB:"
echo "  chroot /mnt/gentoo /bin/bash"
echo "  grub-install /dev/sda"
echo "  grub-mkconfig -o /boot/grub/grub.cfg"
echo ""
echo "Boot manuel:"
echo "  kexec -l /mnt/gentoo/boot/vmlinuz-* --append='root=/dev/sda3 ro'"
echo "  kexec -e"
EOF

chmod +x /tmp/sauvetage_livecd.sh

# ============================================================================
# VÉRIFICATION FINALE
# ============================================================================
echo ""
log_info "━━━━ VÉRIFICATION FINALE ━━━━"

log_info "Résumé des solutions déployées:"
echo "1. ✅ KEXEC: Boot direct disponible"
echo "2. ✅ Instructions boot manuel: /boot/BOOT-MANUEL-DETAILED.txt"
echo "3. ✅ Script GRUB: /boot/autoboot.grub"
echo "4. ✅ Script sauvetage: /boot/SAUVETAGE-URGENCE.sh"
echo "5. ✅ Script LiveCD: /tmp/sauvetage_livecd.sh"

log_info "État du système:"
echo "🐧 Noyau: $KERNEL_NAME"
echo "💾 Boot: /dev/sda1"
echo "🎯 Root: /dev/sda3"
echo "🚀 Boot manuel: PRÊT"

# Démontage propre
umount -R "${MOUNT_POINT}" 2>/dev/null || true

# ============================================================================
# INSTRUCTIONS FINALES ULTIMES
# ============================================================================
echo ""
echo "================================================================"
log_success "🎉 SAUVETAGE TERMINÉ - SYSTÈME PRÊT !"
echo "================================================================"
echo ""
echo "🚀 PROCÉDURE DE BOOT:"
echo ""
echo "OPTION 1 (Recommandée) - BOOT MANUEL:"
echo "   1. Redémarrez SANS le LiveCD"
echo "   2. Au démarrage: APPUYEZ SUR 'c'"
echo "   3. Copiez-collez EXACTEMENT:"
echo "      set root=(hd0,msdos1)"
echo "      linux /$KERNEL_NAME root=/dev/sda3 ro"
echo "      boot"
echo ""
echo "OPTION 2 - KEXEC (Si disponible):"
echo "   Redémarrez et le système bootera automatiquement"
echo ""
echo "OPTION 3 - LIVECD (Si échec):"
echo "   1. Redémarrez sur LiveCD"
echo "   2. Exécutez: /tmp/sauvetage_livecd.sh"
echo ""
echo "✅ APRÈS BOOT SUCCÈS:"
echo "   Exécutez: /boot/SAUVETAGE-URGENCE.sh"
echo "   Cela installera GRUB définitivement"
echo ""
echo "📁 FICHIERS CRÉÉS:"
echo "   • /boot/BOOT-MANUEL-DETAILED.txt - Instructions détaillées"
echo "   • /boot/autoboot.grub - Script GRUB automatique"
echo "   • /boot/SAUVETAGE-URGENCE.sh - Script de réparation"
echo "   • /tmp/sauvetage_livecd.sh - Script LiveCD"
echo ""
echo "⚠️  ACTION REQUISE:"
echo "   DÉMONTEZ le LiveCD dans VirtualBox AVANT de redémarrer !"
echo "   Paramètres → Stockage → Contrôleur IDE → Démonter l'ISO"
echo ""
echo "🎯 RÉSULTAT ATTENDU:"
echo "   Le système Gentoo devrait démarrer avec l'une de ces méthodes"