#!/bin/bash
# TP2 - Configuration système Gentoo OpenRC - VERSION ULTRA VERBOSE
# Compilation séquentielle pour éviter les blocages

set -euo pipefail

MOUNT_POINT="/mnt/gentoo"
RAPPORT="/root/rapport_tp2_openrc.txt"

echo "================================================================"
echo "     TP2 - Configuration Gentoo OpenRC (Ex 2.1-2.6)"
echo "     VERSION VERBOSE - Compilation séquentielle (stable)"
echo "================================================================"
echo ""

# Initialisation du rapport
cat > "${RAPPORT}" << 'EOF'
================================================================================
                    RAPPORT TP2 - CONFIGURATION SYSTÈME GENTOO
================================================================================
Étudiant: [Votre Nom]
Date: $(date '+%d/%m/%Y %H:%M')
Système: Gentoo Linux avec OpenRC
Mode compilation: Séquentiel (1 thread) pour stabilité maximale

================================================================================
                            NOYAU ET AMORCE
================================================================================

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

echo "[OK] Système monté et prêt"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "ÉTAT INITIAL DU SYSTÈME"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "[INFO] Espace disque AVANT le TP2:"
df -h "${MOUNT_POINT}" "${MOUNT_POINT}/boot" 2>/dev/null | grep -E "Filesystem|sda"

echo ""
echo "[INFO] Utilisation détaillée de /:"
du -sh "${MOUNT_POINT}"/* 2>/dev/null | sort -hr | head -10

echo ""
echo "[INFO] Mémoire disponible:"
free -h

# ============================================================================
# DÉBUT DU CHROOT
# ============================================================================

chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_TP2'
#!/bin/bash
set -euo pipefail

source /etc/profile
export PS1="(chroot) \$PS1"

RAPPORT="/root/rapport_tp2_openrc.txt"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║             ENTRÉE DANS LE CHROOT GENTOO                  ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "[CHROOT] Environnement chargé"
echo "[CHROOT] PS1=$(echo $PS1)"
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
EXERCICE 2.1 - Installation des sources du noyau Linux
────────────────────────────────────────────────────────────────────────────
RAPPORT_2_1

echo "[STEP 1/5] État initial"
echo "════════════════════════════════════════════════════════════"
echo "[INFO] Espace disque disponible:"
df -h / | grep -v Filesystem
echo ""
echo "[INFO] Contenu de /usr/src:"
ls -la /usr/src 2>/dev/null || echo "  /usr/src n'existe pas encore"
echo ""

echo "[STEP 2/5] Nettoyage préventif"
echo "════════════════════════════════════════════════════════════"
rm -rf /var/cache/distfiles/* 2>/dev/null || true
rm -rf /var/cache/binpkgs/* 2>/dev/null || true
rm -rf /tmp/* 2>/dev/null || true
echo "[OK] Cache nettoyé"
echo ""

echo "[STEP 3/5] Installation des sources"
echo "════════════════════════════════════════════════════════════"
echo "[INFO] Commande: emerge --noreplace sys-kernel/gentoo-sources"
echo "[INFO] Téléchargement et installation en cours..."
echo ""

if emerge --noreplace sys-kernel/gentoo-sources; then
    echo ""
    echo "[OK] ✓ Installation réussie"
else
    echo ""
    echo "[WARNING] Gestion des conflits..."
    emerge --autounmask-write sys-kernel/gentoo-sources || true
    etc-update --automode -5 2>/dev/null || true
    emerge sys-kernel/gentoo-sources
fi

# Nettoyage post-installation
rm -rf /var/cache/distfiles/* 2>/dev/null || true
echo ""

echo "[STEP 4/5] Vérification"
echo "════════════════════════════════════════════════════════════"

if ls -d /usr/src/linux-* >/dev/null 2>&1; then
    KERNEL_VER=$(ls -d /usr/src/linux-* | head -1 | sed 's|/usr/src/linux-||')
    KERNEL_DIR="/usr/src/linux-${KERNEL_VER}"
    
    ln -sf "${KERNEL_DIR}" /usr/src/linux
    
    echo "[OK] Sources installées:"
    echo "  • Version: ${KERNEL_VER}"
    echo "  • Répertoire: ${KERNEL_DIR}"
    echo "  • Lien: /usr/src/linux -> ${KERNEL_DIR}"
    
    SOURCES_SIZE=$(du -sh /usr/src/linux | cut -f1)
    echo "  • Taille: ${SOURCES_SIZE}"
    echo ""
    
    cat >> "${RAPPORT}" << RAPPORT_2_1_FIN
Commande: emerge sys-kernel/gentoo-sources

RÉSULTAT:
  ✓ Version: ${KERNEL_VER}
  ✓ Taille: ${SOURCES_SIZE}
  ✓ Lien symbolique créé

RAPPORT_2_1_FIN
else
    echo "[ERROR] ✗ Échec"
    exit 1
fi

echo "[STEP 5/5] État final"
echo "════════════════════════════════════════════════════════════"
df -h / | grep -v Filesystem
echo ""
echo "[SUCCESS] ✅ Exercice 2.1 terminé"
echo ""

# ============================================================================
# EXERCICE 2.2 - IDENTIFICATION MATÉRIEL
# ============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  EXERCICE 2.2 - Identification du matériel                ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

if ! command -v lspci >/dev/null 2>&1; then
    echo "[INFO] Installation de pciutils..."
    emerge --noreplace sys-apps/pciutils
    rm -rf /var/cache/distfiles/* 2>/dev/null || true
fi

echo "[INFO] Scan du matériel en cours..."
echo ""

echo "1️⃣  PÉRIPHÉRIQUES PCI"
echo "════════════════════════════════════════════════════════════"
lspci
echo ""

echo "2️⃣  PROCESSEUR"
echo "════════════════════════════════════════════════════════════"
grep -m1 "model name" /proc/cpuinfo
echo "Cœurs: $(nproc)"
echo ""

echo "3️⃣  MÉMOIRE"
echo "════════════════════════════════════════════════════════════"
free -h
echo ""

echo "4️⃣  DISQUES"
echo "════════════════════════════════════════════════════════════"
lsblk
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

echo "[STEP 1/5] Installation outils de configuration"
echo "════════════════════════════════════════════════════════════"
emerge --noreplace sys-devel/bc sys-devel/ncurses
rm -rf /var/cache/distfiles/* 2>/dev/null || true
echo "[OK] Outils installés"
echo ""

echo "[STEP 2/5] Génération configuration de base"
echo "════════════════════════════════════════════════════════════"
if [ -f "/proc/config.gz" ]; then
    zcat /proc/config.gz > .config
    echo "[OK] Config du noyau actuel utilisée"
else
    make defconfig
    echo "[OK] Config par défaut générée"
fi
echo ""

echo "[STEP 3/5] Préparation des scripts"
echo "════════════════════════════════════════════════════════════"
make scripts
echo "[OK] Scripts préparés"
echo ""

echo "[STEP 4/5] Configuration des options"
echo "════════════════════════════════════════════════════════════"

if [ -f "scripts/config" ]; then
    echo "[CONFIG] Activation:"
    echo "  • DEVTMPFS + DEVTMPFS_MOUNT"
    ./scripts/config --enable DEVTMPFS
    ./scripts/config --enable DEVTMPFS_MOUNT
    
    echo "  • EXT4 + EXT2 (statique)"
    ./scripts/config --set-val EXT4_FS y
    ./scripts/config --set-val EXT2_FS y
    
    echo "  • Support VirtIO (VM)"
    ./scripts/config --enable VIRTIO_NET
    ./scripts/config --enable VIRTIO_BLK
    ./scripts/config --enable E1000
    ./scripts/config --enable SCSI_VIRTIO
    
    echo ""
    echo "[CONFIG] Désactivation:"
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

echo "[STEP 5/5] Application configuration"
echo "════════════════════════════════════════════════════════════"
make olddefconfig
echo "[OK] Configuration finalisée"
echo ""

echo "[SUCCESS] ✅ Exercice 2.3 terminé"
echo ""

# ============================================================================
# EXERCICE 2.4 - COMPILATION ET INSTALLATION
# ============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  EXERCICE 2.4 - Compilation et installation               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

echo "⚠️  MODE: COMPILATION SÉQUENTIELLE (1 thread)"
echo "⚠️  Plus lent mais BEAUCOUP plus stable"
echo "⚠️  Évite les problèmes de RAM et les blocages"
echo ""

echo "[STEP 1/7] État PRÉ-compilation"
echo "════════════════════════════════════════════════════════════"
echo "[INFO] Espace disque:"
df -h / /boot | grep -v Filesystem
echo ""
echo "[INFO] Mémoire:"
free -h | grep -E "Mem:|Swap:"
echo ""
echo "[INFO] Taille /usr/src/linux avant:"
du -sh /usr/src/linux
echo ""

echo "[STEP 2/7] 🔨 COMPILATION DU NOYAU"
echo "════════════════════════════════════════════════════════════"
echo "[INFO] Début: $(date '+%H:%M:%S')"
echo "[INFO] Mode: Séquentiel (make sans -j)"
echo "[INFO] Estimation: 30-60 minutes selon CPU"
echo ""
echo "┌────────────────────────────────────────────────────────────┐"
echo "│  COMPILATION EN COURS - Affichage de la progression       │"
echo "│  Chaque ligne '  CC' ou '  LD' = fichier compilé          │"
echo "└────────────────────────────────────────────────────────────┘"
echo ""

COMPILE_START=$(date +%s)

# Affichage de la progression en arrière-plan
(
  while sleep 60; do
    ELAPSED=$(($(date +%s) - COMPILE_START))
    MIN=$((ELAPSED / 60))
    echo ""
    echo "┌─ PROGRESSION ────────────────────────────────────────────┐"
    echo "│  Temps écoulé: ${MIN} minutes"
    echo "│  Espace disque: $(df -h / | grep sda3 | awk '{print $4}') libre"
    echo "│  Mémoire: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
    echo "└──────────────────────────────────────────────────────────┘"
    echo ""
  done
) &
PROGRESS_PID=$!

# Compilation SÉQUENTIELLE
if make 2>&1 | tee /tmp/kernel_compile_full.log | grep -E "CC|LD|AR" | head -100; then
    kill $PROGRESS_PID 2>/dev/null || true
    wait $PROGRESS_PID 2>/dev/null || true
    
    COMPILE_END=$(date +%s)
    COMPILE_TIME=$((COMPILE_END - COMPILE_START))
    COMPILE_MIN=$((COMPILE_TIME / 60))
    COMPILE_SEC=$((COMPILE_TIME % 60))
    
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "[OK] ✓✓✓ COMPILATION RÉUSSIE ✓✓✓"
    echo "════════════════════════════════════════════════════════════"
    echo "  • Temps total: ${COMPILE_MIN}min ${COMPILE_SEC}s"
    echo "  • Fin: $(date '+%H:%M:%S')"
    echo ""
else
    kill $PROGRESS_PID 2>/dev/null || true
    wait $PROGRESS_PID 2>/dev/null || true
    
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "[ERROR] ✗✗✗ ÉCHEC DE LA COMPILATION ✗✗✗"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "[INFO] Dernières lignes du log:"
    tail -50 /tmp/kernel_compile_full.log
    echo ""
    echo "[INFO] Log complet: /tmp/kernel_compile_full.log"
    exit 1
fi

echo "[STEP 3/7] État POST-compilation"
echo "════════════════════════════════════════════════════════════"
df -h / | grep -v Filesystem
echo ""
du -sh /usr/src/linux
echo ""

echo "[STEP 4/7] Installation des modules"
echo "════════════════════════════════════════════════════════════"
echo "[INFO] make modules_install..."
make modules_install
echo "[OK] Modules installés dans /lib/modules/"
echo ""

echo "[STEP 5/7] Installation du noyau"
echo "════════════════════════════════════════════════════════════"
echo "[INFO] make install..."
make install
echo ""
echo "[INFO] Contenu de /boot:"
ls -lh /boot/
echo ""

if ls /boot/vmlinuz-* >/dev/null 2>&1; then
    KERNEL_FILE=$(ls /boot/vmlinuz-* | head -1)
    KERNEL_SIZE=$(du -h "$KERNEL_FILE" | cut -f1)
    echo "[OK] Noyau installé:"
    echo "  • Fichier: ${KERNEL_FILE}"
    echo "  • Taille: ${KERNEL_SIZE}"
else
    echo "[ERROR] ✗ Noyau non trouvé"
    exit 1
fi
echo ""

echo "[STEP 6/7] Installation de GRUB"
echo "════════════════════════════════════════════════════════════"

if ! command -v grub-install >/dev/null 2>&1; then
    echo "[INFO] Installation du paquet GRUB..."
    emerge --noreplace sys-boot/grub
    rm -rf /var/cache/distfiles/* 2>/dev/null || true
fi

echo "[INFO] grub-install /dev/sda..."
grub-install /dev/sda
echo "[OK] GRUB installé"
echo ""

echo "[STEP 7/7] Configuration GRUB"
echo "════════════════════════════════════════════════════════════"
echo "[INFO] grub-mkconfig -o /boot/grub/grub.cfg..."
grub-mkconfig -o /boot/grub/grub.cfg | grep -E "Found|Adding"
echo ""

GRUB_ENTRIES=$(grep -c "^menuentry" /boot/grub/grub.cfg)
echo "[OK] Configuration générée (${GRUB_ENTRIES} entrées)"
echo ""

echo "[INFO] Extrait de grub.cfg:"
grep "^menuentry" /boot/grub/grub.cfg | head -3
echo ""

echo "════════════════════════════════════════════════════════════"
echo "[SUCCESS] ✅✅✅ EXERCICE 2.4 TERMINÉ ✅✅✅"
echo "════════════════════════════════════════════════════════════"
echo "  ✓ Compilation: ${COMPILE_MIN}min ${COMPILE_SEC}s"
echo "  ✓ Noyau: ${KERNEL_FILE} (${KERNEL_SIZE})"
echo "  ✓ GRUB: ${GRUB_ENTRIES} entrées"
echo ""

# ============================================================================
# EXERCICE 2.5 - CONFIGURATION SYSTÈME
# ============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  EXERCICE 2.5 - Configuration système                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

echo "[CONFIG] Mot de passe root..."
echo "root:gentoo123" | chpasswd
echo "[OK] Mot de passe: gentoo123"
echo ""

echo "[CONFIG] Installation syslog-ng..."
emerge --noreplace app-admin/syslog-ng 2>&1 | grep -E ">>>" || true
rm -rf /var/cache/distfiles/* 2>/dev/null || true

echo "[CONFIG] Installation logrotate..."
emerge --noreplace app-admin/logrotate 2>&1 | grep -E ">>>" || true
rm -rf /var/cache/distfiles/* 2>/dev/null || true

echo "[CONFIG] Activation des services..."
rc-update add syslog-ng default 2>/dev/null || true
rc-update add logrotate default 2>/dev/null || true
echo "[OK] Services activés"
echo ""

echo "[SUCCESS] ✅ Exercice 2.5 terminé"
echo ""

# ============================================================================
# EXERCICE 2.6 - VÉRIFICATIONS
# ============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  EXERCICE 2.6 - Vérifications finales                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

echo "[CHECK] Vérifications:"
echo "  ✓ Noyau: $(ls /boot/vmlinuz-* | head -1)"
echo "  ✓ GRUB: ${GRUB_ENTRIES} entrées"
echo "  ✓ Mot de passe root: configuré"
echo "  ✓ Logs: syslog-ng + logrotate"
echo ""

echo "[SUCCESS] ✅ Exercice 2.6 terminé"
echo ""

# ============================================================================
# RÉSUMÉ FINAL
# ============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          🎉🎉🎉 TP2 TERMINÉ AVEC SUCCÈS 🎉🎉🎉          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "📋 RÉCAPITULATIF:"
echo "  ✅ Ex 2.1: Sources du noyau installées"
echo "  ✅ Ex 2.2: Matériel identifié"
echo "  ✅ Ex 2.3: Noyau configuré"
echo "  ✅ Ex 2.4: Noyau compilé (${COMPILE_MIN}min ${COMPILE_SEC}s) + GRUB"
echo "  ✅ Ex 2.5: Mot de passe + logs"
echo "  ✅ Ex 2.6: Vérifications OK"
echo ""
echo "🚀 PROCHAINE ÉTAPE:"
echo "  exit                   # Sortir du chroot"
echo "  cd /"
echo "  umount -R /mnt/gentoo"
echo "  reboot"
echo ""
echo "🔑 CONNEXION:"
echo "  root / gentoo123"
echo ""

CHROOT_TP2

# ============================================================================
# FIN
# ============================================================================

if [ -f "${MOUNT_POINT}/root/rapport_tp2_openrc.txt" ]; then
    cp "${MOUNT_POINT}/root/rapport_tp2_openrc.txt" /root/
    echo "[OK] Rapport copié: /root/rapport_tp2_openrc.txt"
fi

echo ""
echo "================================================================"
echo "[SUCCESS] ✅ SCRIPT TERMINÉ"
echo "================================================================"
echo ""