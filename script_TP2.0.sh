#!/bin/bash
# TP2 PARTIE 1 - Configuration système (Ex 2.1 à 2.4) - VERSION VERBOSE
# Affiche tout ce qui se passe en détail

set -euo pipefail

MOUNT_POINT="/mnt/gentoo"
RAPPORT="/root/rapport_tp2_partie1.txt"

echo "================================================================"
echo "     TP2 PARTIE 1 - Noyau et GRUB (Ex 2.1-2.4) - VERBOSE"
echo "================================================================"
echo ""

# Initialisation du rapport
cat > "${RAPPORT}" << 'EOF'
================================================================================
                    RAPPORT TP2 PARTIE 1 - NOYAU ET GRUB
================================================================================
Date: $(date '+%d/%m/%Y %H:%M')

EOF

echo "[INFO] Vérification du système monté..."

if [ ! -d "${MOUNT_POINT}/etc" ]; then
    echo "[INFO] Montage du système..."
    mkdir -p "${MOUNT_POINT}"
    mount /dev/sda3 "${MOUNT_POINT}"
    mkdir -p "${MOUNT_POINT}"/{boot,home}
    mount /dev/sda1 "${MOUNT_POINT}/boot" 2>/dev/null || true
    mount /dev/sda4 "${MOUNT_POINT}/home" 2>/dev/null || true
    swapon /dev/sda2 2>/dev/null || true
fi

mount -t proc /proc "${MOUNT_POINT}/proc" 2>/dev/null || true
mount --rbind /sys "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --rbind /dev "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --bind /run "${MOUNT_POINT}/run" 2>/dev/null || true
cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/" 2>/dev/null || true

echo "[OK] Système monté"

# Vérifier l'espace disque AVANT de commencer
echo ""
echo "════════════════════════════════════════════════════════════"
echo "[INFO] ESPACE DISQUE AVANT LE TP2:"
echo "════════════════════════════════════════════════════════════"
df -h "${MOUNT_POINT}" "${MOUNT_POINT}/boot" | grep -v tmpfs

echo ""
echo "════════════════════════════════════════════════════════════"
echo "[INFO] DÉTAIL DE L'UTILISATION DE /"
echo "════════════════════════════════════════════════════════════"
du -sh "${MOUNT_POINT}"/* 2>/dev/null | sort -hr | head -10

# ============================================================================
# DÉBUT DU CHROOT
# ============================================================================

chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_TP2_VERBOSE'
#!/bin/bash
set -euo pipefail

source /etc/profile
export PS1="(chroot) \$PS1"

RAPPORT="/root/rapport_tp2_partie1.txt"

echo ""
echo "================================================================"
echo "[TP2] DÉBUT - Exercices 2.1 à 2.4"
echo "================================================================"
echo ""

# ============================================================================
# EXERCICE 2.1 - SOURCES DU NOYAU
# ============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  EXERCICE 2.1 - Installation des sources du noyau         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

cat >> "${RAPPORT}" << 'RAPPORT_2_1'

────────────────────────────────────────────────────────────────────────────
EXERCICE 2.1 - Installation des sources du noyau
────────────────────────────────────────────────────────────────────────────
RAPPORT_2_1

echo "[INFO] Espace disque disponible AVANT installation des sources:"
df -h / | grep -v Filesystem

echo ""
echo "[INFO] Taille actuelle de /usr/src:"
du -sh /usr/src 2>/dev/null || echo "  /usr/src n'existe pas encore"

echo ""
echo "────────────────────────────────────────────────────────────"
echo "[STEP 1/5] Nettoyage préventif..."
echo "────────────────────────────────────────────────────────────"
echo "[CLEAN] Suppression du cache Portage..."
rm -rf /var/cache/distfiles/* 2>/dev/null || true
rm -rf /var/cache/binpkgs/* 2>/dev/null || true
rm -rf /tmp/* 2>/dev/null || true
echo "[OK] Cache nettoyé"

echo ""
echo "────────────────────────────────────────────────────────────"
echo "[STEP 2/5] Installation des sources du noyau avec emerge..."
echo "────────────────────────────────────────────────────────────"
echo "[INFO] Commande: emerge --noreplace sys-kernel/gentoo-sources"
echo "[INFO] Cela va télécharger et installer les sources (~150 Mo)"
echo ""

# Installation avec affichage en temps réel
if emerge --noreplace sys-kernel/gentoo-sources; then
    echo ""
    echo "[OK] ✓ Installation réussie"
else
    echo ""
    echo "[WARNING] Installation avec résolution de conflits..."
    emerge --autounmask-write sys-kernel/gentoo-sources || true
    etc-update --automode -5 2>/dev/null || true
    emerge sys-kernel/gentoo-sources
fi

echo ""
echo "────────────────────────────────────────────────────────────"
echo "[STEP 3/5] Vérification de l'installation..."
echo "────────────────────────────────────────────────────────────"

if ls -d /usr/src/linux-* >/dev/null 2>&1; then
    KERNEL_VER=$(ls -d /usr/src/linux-* | head -1 | sed 's|/usr/src/linux-||')
    KERNEL_DIR=$(ls -d /usr/src/linux-* | head -1)
    
    echo "[OK] Sources installées:"
    echo "  • Version: ${KERNEL_VER}"
    echo "  • Emplacement: ${KERNEL_DIR}"
    
    # Créer le lien symbolique
    ln -sf "${KERNEL_DIR}" /usr/src/linux
    echo "  • Lien symbolique: /usr/src/linux -> ${KERNEL_DIR}"
    
    # Taille des sources
    SOURCES_SIZE=$(du -sh /usr/src/linux 2>/dev/null | cut -f1)
    echo "  • Taille des sources: ${SOURCES_SIZE}"
    
    echo ""
    echo "[INFO] Contenu de /usr/src/linux (aperçu):"
    ls -lh /usr/src/linux | head -15
    
else
    echo "[ERROR] ✗ Échec de l'installation"
    exit 1
fi

echo ""
echo "────────────────────────────────────────────────────────────"
echo "[STEP 4/5] Nettoyage post-installation..."
echo "────────────────────────────────────────────────────────────"
echo "[CLEAN] Suppression des archives téléchargées..."
rm -rf /var/cache/distfiles/* 2>/dev/null || true
echo "[OK] Nettoyage effectué"

echo ""
echo "────────────────────────────────────────────────────────────"
echo "[STEP 5/5] Espace disque APRÈS installation des sources:"
echo "────────────────────────────────────────────────────────────"
df -h / | grep -v Filesystem

echo ""
echo "[SUCCESS] ✅ Exercice 2.2 terminé"
echo ""

# ============================================================================
# EXERCICE 2.3 - CONFIGURATION DU NOYAU
# ============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  EXERCICE 2.3 - Configuration du noyau                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

cd /usr/src/linux

echo "────────────────────────────────────────────────────────────"
echo "[STEP 1/6] Installation des outils de configuration..."
echo "────────────────────────────────────────────────────────────"
emerge --noreplace sys-devel/bc sys-devel/ncurses
rm -rf /var/cache/distfiles/* 2>/dev/null || true
echo "[OK] Outils installés"

echo ""
echo "────────────────────────────────────────────────────────────"
echo "[STEP 2/6] Génération de la configuration de base..."
echo "────────────────────────────────────────────────────────────"
if [ -f "/proc/config.gz" ]; then
    echo "[INFO] Utilisation de la config du noyau actuel"
    zcat /proc/config.gz > .config
else
    echo "[INFO] Génération de la config par défaut"
    make defconfig
fi
echo "[OK] Configuration de base créée"

echo ""
echo "────────────────────────────────────────────────────────────"
echo "[STEP 3/6] Préparation des scripts de configuration..."
echo "────────────────────────────────────────────────────────────"
make scripts
echo "[OK] Scripts préparés"

echo ""
echo "────────────────────────────────────────────────────────────"
echo "[STEP 4/6] Application des options pour VM..."
echo "────────────────────────────────────────────────────────────"

if [ -f "scripts/config" ]; then
    echo "[CONFIG] Activation des options requises:"
    echo "  • DEVTMPFS"
    ./scripts/config --enable DEVTMPFS
    ./scripts/config --enable DEVTMPFS_MOUNT
    
    echo "  • Systèmes de fichiers en statique"
    ./scripts/config --set-val EXT4_FS y
    ./scripts/config --set-val EXT2_FS y
    
    echo "  • Support VirtIO"
    ./scripts/config --enable VIRTIO_NET
    ./scripts/config --enable VIRTIO_BLK
    ./scripts/config --enable E1000
    ./scripts/config --enable SCSI_VIRTIO
    
    echo ""
    echo "[CONFIG] Désactivation pour accélérer la compilation:"
    echo "  • Debug noyau"
    ./scripts/config --disable DEBUG_KERNEL
    ./scripts/config --disable DEBUG_INFO
    
    echo "  • WiFi"
    ./scripts/config --disable CFG80211
    ./scripts/config --disable MAC80211
    ./scripts/config --disable WLAN
    
    echo "  • Drivers Mac"
    ./scripts/config --disable MACINTOSH_DRIVERS
    
    echo ""
    echo "[OK] Options configurées"
fi

echo ""
echo "────────────────────────────────────────────────────────────"
echo "[STEP 5/6] Application de la configuration..."
echo "────────────────────────────────────────────────────────────"
make olddefconfig
echo "[OK] Configuration finalisée"

echo ""
echo "────────────────────────────────────────────────────────────"
echo "[STEP 6/6] Vérification de la configuration..."
echo "────────────────────────────────────────────────────────────"
echo "[INFO] Options critiques vérifiées:"
grep -E "CONFIG_DEVTMPFS=|CONFIG_EXT4_FS=|CONFIG_DEBUG_KERNEL=|CONFIG_WLAN=" .config | head -10

echo ""
echo "[SUCCESS] ✅ Exercice 2.3 terminé - Noyau configuré"
echo ""

# ============================================================================
# EXERCICE 2.4 - COMPILATION ET INSTALLATION
# ============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  EXERCICE 2.4 - Compilation et installation               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

echo "⚠️  IMPORTANT: La compilation peut prendre 15-45 minutes"
echo "⚠️  selon la puissance de votre machine"
echo ""

echo "────────────────────────────────────────────────────────────"
echo "[STEP 1/8] Espace disque AVANT compilation:"
echo "────────────────────────────────────────────────────────────"
df -h / /boot | grep -v Filesystem

echo ""
echo "────────────────────────────────────────────────────────────"
echo "[STEP 2/8] COMPILATION DU NOYAU (make -j2)"
echo "────────────────────────────────────────────────────────────"
echo "[INFO] Début de la compilation: $(date '+%H:%M:%S')"
echo "[INFO] Utilisation de 2 threads parallèles"
echo ""

COMPILE_START=$(date +%s)

echo "┌────────────────────────────────────────────────────────────┐"
echo "│  COMPILATION EN COURS - AFFICHAGE EN TEMPS RÉEL           │"
echo "└────────────────────────────────────────────────────────────┘"
echo ""

# Compilation avec affichage en temps réel
if make -j2 2>&1 | tee /tmp/kernel_compile.log; then
    COMPILE_END=$(date +%s)
    COMPILE_TIME=$((COMPILE_END - COMPILE_START))
    COMPILE_MIN=$((COMPILE_TIME / 60))
    COMPILE_SEC=$((COMPILE_TIME % 60))
    
    echo ""
    echo "[OK] ✓ Compilation réussie"
    echo "[INFO] Temps de compilation: ${COMPILE_MIN}min ${COMPILE_SEC}s"
else
    echo ""
    echo "[WARNING] Compilation avec -j2 échouée, tentative avec 1 thread..."
    make 2>&1 | tee /tmp/kernel_compile.log
    
    COMPILE_END=$(date +%s)
    COMPILE_TIME=$((COMPILE_END - COMPILE_START))
    COMPILE_MIN=$((COMPILE_TIME / 60))
    COMPILE_SEC=$((COMPILE_TIME % 60))
    
    echo "[OK] Compilation réussie (1 thread)"
    echo "[INFO] Temps: ${COMPILE_MIN}min ${COMPILE_SEC}s"
fi

echo ""
echo "────────────────────────────────────────────────────────────"
echo "[STEP 3/8] Espace disque APRÈS compilation:"
echo "────────────────────────────────────────────────────────────"
df -h / | grep -v Filesystem
echo ""
echo "[INFO] Taille de /usr/src/linux après compilation:"
du -sh /usr/src/linux

echo ""
echo "────────────────────────────────────────────────────────────"
echo "[STEP 4/8] Installation des modules (make modules_install)"
echo "────────────────────────────────────────────────────────────"
echo "[INFO] Installation des modules dans /lib/modules/..."
make modules_install 2>&1 | tail -10
echo "[OK] Modules installés"

echo ""
echo "────────────────────────────────────────────────────────────"
echo "[STEP 5/8] Installation du noyau (make install)"
echo "────────────────────────────────────────────────────────────"
echo "[INFO] Copie du noyau dans /boot..."
make install 2>&1 | tail -10

echo ""
echo "[INFO] Contenu de /boot après installation:"
ls -lh /boot/
echo ""

if ls /boot/vmlinuz-* >/dev/null 2>&1; then
    KERNEL_FILE=$(ls /boot/vmlinuz-* | head -1)
    KERNEL_SIZE=$(du -h "$KERNEL_FILE" | cut -f1)
    echo "[OK] ✓ Noyau installé:"
    echo "  • Fichier: ${KERNEL_FILE}"
    echo "  • Taille: ${KERNEL_SIZE}"
else
    echo "[ERROR] ✗ Aucun noyau trouvé dans /boot"
    exit 1
fi

echo ""
echo "────────────────────────────────────────────────────────────"
echo "[STEP 6/8] Installation de GRUB"
echo "────────────────────────────────────────────────────────────"

if ! command -v grub-install >/dev/null 2>&1; then
    echo "[INFO] Installation du paquet GRUB..."
    emerge --noreplace sys-boot/grub
    rm -rf /var/cache/distfiles/* 2>/dev/null || true
else
    echo "[INFO] GRUB déjà installé"
fi

echo ""
echo "[INFO] Installation de GRUB sur /dev/sda..."
grub-install /dev/sda 2>&1 | grep -v "Installing"
echo "[OK] GRUB installé sur le disque"

echo ""
echo "────────────────────────────────────────────────────────────"
echo "[STEP 7/8] Génération de la configuration GRUB"
echo "────────────────────────────────────────────────────────────"
echo "[INFO] Commande: grub-mkconfig -o /boot/grub/grub.cfg"
echo ""

grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | grep -E "Found|Adding|done"

echo ""
echo "[OK] Configuration GRUB générée"

echo ""
echo "────────────────────────────────────────────────────────────"
echo "[STEP 8/8] Vérification du fichier grub.cfg"
echo "────────────────────────────────────────────────────────────"
echo "[INFO] Extrait du fichier /boot/grub/grub.cfg:"
echo ""
grep -E "^menuentry|^[[:space:]]+linux|^[[:space:]]+initrd" /boot/grub/grub.cfg | head -20

echo ""
echo "[INFO] Nombre d'entrées dans le menu GRUB:"
GRUB_ENTRIES=$(grep -c "^menuentry" /boot/grub/grub.cfg)
echo "  • ${GRUB_ENTRIES} entrée(s) de boot détectée(s)"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "RÉSUMÉ DE L'EXERCICE 2.4:"
echo "════════════════════════════════════════════════════════════"
echo "  ✓ Compilation du noyau: ${COMPILE_MIN}min ${COMPILE_SEC}s"
echo "  ✓ Noyau installé: ${KERNEL_FILE}"
echo "  ✓ Taille: ${KERNEL_SIZE}"
echo "  ✓ Modules installés dans /lib/modules/"
echo "  ✓ GRUB installé sur /dev/sda"
echo "  ✓ Configuration GRUB générée (${GRUB_ENTRIES} entrées)"
echo ""
echo "[SUCCESS] ✅ Exercice 2.4 terminé - Noyau et GRUB opérationnels"
echo ""

# ============================================================================
# RÉSUMÉ FINAL PARTIE 1
# ============================================================================
echo ""
echo "════════════════════════════════════════════════════════════"
echo "ESPACE DISQUE FINAL:"
echo "════════════════════════════════════════════════════════════"
df -h / /boot | grep -v Filesystem

echo ""
echo "════════════════════════════════════════════════════════════"
echo "PLUS GROS RÉPERTOIRES SUR /:"
echo "════════════════════════════════════════════════════════════"
du -sh /* 2>/dev/null | sort -hr | head -10

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║             🎉 TP2 PARTIE 1 TERMINÉ AVEC SUCCÈS           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "📋 RÉCAPITULATIF:"
echo "  ✅ Ex 2.1: Sources du noyau installées"
echo "  ✅ Ex 2.2: Matériel identifié"
echo "  ✅ Ex 2.3: Noyau configuré pour VM"
echo "  ✅ Ex 2.4: Noyau compilé et GRUB installé"
echo ""
echo "🚀 VOUS POUVEZ MAINTENANT:"
echo "  • Continuer avec les exercices 2.5-2.6"
echo "  • Ou redémarrer pour tester le système"
echo ""
echo "📄 Rapport sauvegardé: /root/rapport_tp2_partie1.txt"
echo ""

CHROOT_TP2_VERBOSE

# ============================================================================
# FIN DU SCRIPT
# ============================================================================

if [ -f "${MOUNT_POINT}/root/rapport_tp2_partie1.txt" ]; then
    cp "${MOUNT_POINT}/root/rapport_tp2_partie1.txt" /root/
    echo "[OK] Rapport copié: /root/rapport_tp2_partie1.txt"
fi

echo ""
echo "================================================================"
echo "[SUCCESS] ✅ SCRIPT TERMINÉ"
echo "================================================================"
echo ""
echo "Consultez le rapport pour voir tous les détails:"
echo "  cat /root/rapport_tp2_partie1.txt"
echo ""
 Exercice 2.1 terminé"
echo ""

# ============================================================================
# EXERCICE 2.2 - IDENTIFICATION MATÉRIEL
# ============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  EXERCICE 2.2 - Identification du matériel                ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

cat >> "${RAPPORT}" << 'RAPPORT_2_2'

────────────────────────────────────────────────────────────────────────────
EXERCICE 2.2 - Identification du matériel
────────────────────────────────────────────────────────────────────────────
RAPPORT_2_2

echo "────────────────────────────────────────────────────────────"
echo "[STEP 1/3] Installation de pciutils (si nécessaire)..."
echo "────────────────────────────────────────────────────────────"

if ! command -v lspci >/dev/null 2>&1; then
    echo "[INFO] Installation de pciutils..."
    emerge --noreplace sys-apps/pciutils
    rm -rf /var/cache/distfiles/* 2>/dev/null || true
else
    echo "[INFO] pciutils déjà installé"
fi

echo ""
echo "────────────────────────────────────────────────────────────"
echo "[STEP 2/3] Identification du matériel..."
echo "────────────────────────────────────────────────────────────"
echo ""

echo "[1] PÉRIPHÉRIQUES PCI:"
echo "══════════════════════════════════════════════════════════"
lspci | tee -a "${RAPPORT}"

echo ""
echo "[2] PROCESSEUR:"
echo "══════════════════════════════════════════════════════════"
grep -m1 "model name" /proc/cpuinfo | tee -a "${RAPPORT}"
echo "Nombre de cœurs: $(nproc)" | tee -a "${RAPPORT}"

echo ""
echo "[3] MÉMOIRE:"
echo "══════════════════════════════════════════════════════════"
free -h | tee -a "${RAPPORT}"

echo ""
echo "[4] DISQUES:"
echo "══════════════════════════════════════════════════════════"
lsblk | tee -a "${RAPPORT}"

echo ""
echo "[5] CARTE RÉSEAU:"
echo "══════════════════════════════════════════════════════════"
ip link show | grep -E "^[0-9]+:" | tee -a "${RAPPORT}"

echo ""
echo "[6] CARTE GRAPHIQUE:"
echo "══════════════════════════════════════════════════════════"
lspci | grep -iE "vga|3d|display" | tee -a "${RAPPORT}"

echo ""
echo "────────────────────────────────────────────────────────────"
echo "[STEP 3/3] Informations sauvegardées dans le rapport"
echo "────────────────────────────────────────────────────────────"

echo ""
echo "[SUCCESS] ✅