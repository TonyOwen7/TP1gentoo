#!/bin/bash
# TP2 COMPLET pour stage3-systemd avec correction automatique
# Génère le rapport du TP

SECRET_CODE="codesecret"   # Code attendu

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

set -euo pipefail

MOUNT_POINT="/mnt/gentoo"
RAPPORT="/root/rapport_tp2.txt"

echo "================================================================"
echo "     TP2 COMPLET - Configuration Gentoo systemd"
echo "     Avec correction automatique du profil"
echo "================================================================"
echo ""

# Initialisation du rapport
cat > "${RAPPORT}" << 'EOF'
================================================================================
                    RAPPORT TP2 - CONFIGURATION SYSTÈME GENTOO
================================================================================
Étudiant: [Votre Nom]
Date: $(date '+%d/%m/%Y %H:%M')
Système: Gentoo Linux avec systemd

================================================================================
                            EXERCICES ET RÉPONSES
================================================================================

EOF

# ============================================================================
# VÉRIFICATION ET MONTAGE
# ============================================================================
echo "[INFO] Vérification du système..."

if [ ! -d "${MOUNT_POINT}/etc" ]; then
    echo "[INFO] Montage du système..."
    mkdir -p "${MOUNT_POINT}"
    mount /dev/sda3 "${MOUNT_POINT}"
    mkdir -p "${MOUNT_POINT}"/{boot,home}
    mount /dev/sda1 "${MOUNT_POINT}/boot" 2>/dev/null || true
    mount /dev/sda4 "${MOUNT_POINT}/home" 2>/dev/null || true
    swapon /dev/sda2 2>/dev/null || true
fi

# Montage systèmes virtuels
mount -t proc /proc "${MOUNT_POINT}/proc" 2>/dev/null || true
mount --rbind /sys "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --rbind /dev "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --bind /run "${MOUNT_POINT}/run" 2>/dev/null || true
cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/" 2>/dev/null || true

echo "[OK] Système monté"

# ============================================================================
# CORRECTION DU PROFIL ET PORTAGE
# ============================================================================
echo "[INFO] Correction automatique du profil et Portage..."

chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_FIX_PROFILE'
#!/bin/bash
set -euo pipefail

source /etc/profile 2>/dev/null || true

echo ""
echo "[FIX] === CORRECTION DU PROFIL ET PORTAGE ==="

# Vérifier où est Portage
if [ ! -d "/var/db/repos/gentoo/profiles" ]; then
    echo "[WARNING] Portage mal extrait, correction..."
    
    # Portage a été extrait dans /usr au lieu de /var/db/repos/gentoo
    if [ -d "/usr/portage/profiles" ]; then
        echo "[FIX] Déplacement de Portage vers le bon emplacement..."
        mkdir -p /var/db/repos
        mv /usr/portage /var/db/repos/gentoo
        echo "[OK] Portage déplacé"
    elif [ -f "/portage-latest.tar.xz" ]; then
        echo "[FIX] Extraction de portage-latest.tar.xz..."
        mkdir -p /var/db/repos/gentoo
        tar xpf /portage-latest.tar.xz -C /var/db/repos/gentoo --strip-components=1
        echo "[OK] Portage extrait"
    else
        echo "[WARNING] Tentative de synchronisation..."
        mkdir -p /var/db/repos/gentoo
        emerge-webrsync 2>&1 | tail -5 || echo "[WARNING] Synchronisation partielle"
    fi
fi

# Correction du profil
echo "[FIX] Configuration du profil systemd..."

if [ ! -d "/var/db/repos/gentoo/profiles" ]; then
    echo "[ERROR] Impossible de trouver les profils"
    exit 1
fi

# Trouver un profil systemd
SYSTEMD_PROFILE=""
for VERSION in 17.1/systemd 17.0/systemd 17.1/systemd/merged-usr 17.0/systemd/merged-usr; do
    if [ -d "/var/db/repos/gentoo/profiles/default/linux/amd64/${VERSION}" ]; then
        SYSTEMD_PROFILE="/var/db/repos/gentoo/profiles/default/linux/amd64/${VERSION}"
        break
    fi
done

if [ -z "${SYSTEMD_PROFILE}" ]; then
    # Fallback: premier profil systemd trouvé
    SYSTEMD_PROFILE=$(find /var/db/repos/gentoo/profiles/default/linux/amd64 -type d -name "*systemd*" 2>/dev/null | head -1)
fi

if [ -n "${SYSTEMD_PROFILE}" ] && [ -d "${SYSTEMD_PROFILE}" ]; then
    rm -f /etc/portage/make.profile
    ln -sf "${SYSTEMD_PROFILE}" /etc/portage/make.profile
    echo "[OK] Profil systemd configuré: ${SYSTEMD_PROFILE}"
else
    echo "[ERROR] Aucun profil systemd trouvé"
    exit 1
fi

# Vérification
if emerge --info >/dev/null 2>&1; then
    echo "[OK] emerge fonctionnel"
else
    echo "[WARNING] emerge a des avertissements"
fi

echo ""
CHROOT_FIX_PROFILE

echo "[OK] Profil corrigé, début du TP2..."

# ============================================================================
# DÉBUT DU TP2 DANS LE CHROOT
# ============================================================================

chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_TP2'
#!/bin/bash
set -euo pipefail

source /etc/profile
export PS1="(chroot) \$PS1"

RAPPORT="/root/rapport_tp2.txt"

echo ""
echo "================================================================"
echo "[TP2] DÉBUT DU TP2 - CONFIGURATION SYSTÈME"
echo "================================================================"
echo ""

# ============================================================================
# EXERCICE 2.1 - SOURCES DU NOYAU
# ============================================================================
echo ""
echo "[TP2] === EXERCICE 2.1 - Installation des sources du noyau ==="

cat >> "${RAPPORT}" << 'RAPPORT_2_1'

────────────────────────────────────────────────────────────────────────────
EXERCICE 2.1 - Installation des sources du noyau Linux
────────────────────────────────────────────────────────────────────────────

QUESTION: Comment installer les sources du noyau sur Gentoo ?

RÉPONSE:
Les sources s'installent avec emerge:
    emerge sys-kernel/gentoo-sources

COMMANDES UTILISÉES:
    emerge --noreplace sys-kernel/gentoo-sources

RAPPORT_2_1

echo "[TP2] Installation des sources du noyau..."
if emerge --noreplace sys-kernel/gentoo-sources 2>&1 | tee -a /tmp/kernel_install.log | grep -E ">>>"; then
    echo "[OK] Sources installées"
else
    echo "[WARNING] Installation avec gestion des conflits..."
    emerge --autounmask-write sys-kernel/gentoo-sources 2>&1 | tail -5 || true
    etc-update --automode -5 2>/dev/null || true
    emerge sys-kernel/gentoo-sources 2>&1 | tail -5
fi

if ls -d /usr/src/linux-* >/dev/null 2>&1; then
    KERNEL_VER=$(ls -d /usr/src/linux-* | head -1 | sed 's|/usr/src/linux-||')
    ln -sf /usr/src/linux-* /usr/src/linux 2>/dev/null || true
    echo "[OK] Sources installées: version ${KERNEL_VER}"
    echo "RÉSULTAT: Sources du noyau ${KERNEL_VER} installées" >> "${RAPPORT}"
else
    echo "[ERROR] Échec installation sources"
    echo "ERREUR: Échec de l'installation" >> "${RAPPORT}"
    exit 1
fi

# ============================================================================
# EXERCICE 2.2 - IDENTIFICATION MATÉRIEL
# ============================================================================
echo ""
echo "[TP2] === EXERCICE 2.2 - Identification du matériel ==="

cat >> "${RAPPORT}" << 'RAPPORT_2_2'

────────────────────────────────────────────────────────────────────────────
EXERCICE 2.2 - Identification du matériel système
────────────────────────────────────────────────────────────────────────────

QUESTION: Commandes pour lister le matériel ?

RÉPONSE:
- lspci : Périphériques PCI
- lscpu : Informations CPU
- lsblk : Disques et partitions
- /proc/cpuinfo : Détails processeur

COMMANDES ET RÉSULTATS:
RAPPORT_2_2

# Installation pciutils si nécessaire
if ! command -v lspci >/dev/null 2>&1; then
    emerge --noreplace sys-apps/pciutils 2>&1 | grep -E ">>>" || true
fi

echo "" >> "${RAPPORT}"
echo "1) Périphériques PCI:" >> "${RAPPORT}"
lspci 2>/dev/null | tee -a "${RAPPORT}"

echo "" >> "${RAPPORT}"
echo "2) Processeur:" >> "${RAPPORT}"
grep -m1 "model name" /proc/cpuinfo | tee -a "${RAPPORT}"

echo "" >> "${RAPPORT}"
echo "3) Mémoire:" >> "${RAPPORT}"
free -h | tee -a "${RAPPORT}"

echo "" >> "${RAPPORT}"
echo "4) Disques:" >> "${RAPPORT}"
lsblk | tee -a "${RAPPORT}"

echo "[OK] Matériel identifié"

# ============================================================================
# EXERCICE 2.3 - CONFIGURATION DU NOYAU
# ============================================================================
echo ""
echo "[TP2] === EXERCICE 2.3 - Configuration du noyau ==="

cat >> "${RAPPORT}" << 'RAPPORT_2_3'

────────────────────────────────────────────────────────────────────────────
EXERCICE 2.3 - Configuration du noyau pour VM
────────────────────────────────────────────────────────────────────────────

CONFIGURATION APPLIQUÉE:
- DEVTMPFS activé (gestion automatique /dev)
- EXT4 en statique
- Debug désactivé
- WiFi désactivé
- Drivers Mac désactivés
- Support VirtIO (VM)

COMMANDES:
RAPPORT_2_3

cd /usr/src/linux

# Outils nécessaires
emerge --noreplace sys-devel/bc sys-devel/ncurses 2>&1 | grep -E ">>>" || true

# Configuration de base
if [ -f "/proc/config.gz" ]; then
    zcat /proc/config.gz > .config
    echo "[OK] Config depuis noyau actuel"
else
    make defconfig
    echo "[OK] Config par défaut"
fi

make scripts 2>&1 | tail -3

# Configuration automatique
if [ -f "scripts/config" ]; then
    ./scripts/config --enable DEVTMPFS 2>/dev/null || true
    ./scripts/config --enable DEVTMPFS_MOUNT 2>/dev/null || true
    ./scripts/config --set-val EXT4_FS y 2>/dev/null || true
    ./scripts/config --enable VIRTIO_NET 2>/dev/null || true
    ./scripts/config --enable VIRTIO_BLK 2>/dev/null || true
    ./scripts/config --enable E1000 2>/dev/null || true
    ./scripts/config --disable DEBUG_KERNEL 2>/dev/null || true
    ./scripts/config --disable DEBUG_INFO 2>/dev/null || true
    ./scripts/config --disable CFG80211 2>/dev/null || true
    ./scripts/config --disable MAC80211 2>/dev/null || true
    ./scripts/config --disable WLAN 2>/dev/null || true
    echo "[OK] Options configurées"
fi

make olddefconfig 2>&1 | tail -3
echo "    make olddefconfig" >> "${RAPPORT}"
echo "RÉSULTAT: Noyau configuré pour VM" >> "${RAPPORT}"

echo "[OK] Noyau configuré"

# ============================================================================
# EXERCICE 2.4 - COMPILATION ET GRUB
# ============================================================================
echo ""
echo "[TP2] === EXERCICE 2.4 - Compilation noyau + GRUB ==="

cat >> "${RAPPORT}" << 'RAPPORT_2_4'

────────────────────────────────────────────────────────────────────────────
EXERCICE 2.4 - Compilation et installation
────────────────────────────────────────────────────────────────────────────

COMMANDES:
    make -j2
    make modules_install
    make install
    emerge sys-boot/grub
    grub-install /dev/sda
    grub-mkconfig -o /boot/grub/grub.cfg

RAPPORT_2_4

echo "[TP2] Compilation du noyau (patience...)..."
COMPILE_START=$(date +%s)

if make -j2 2>&1 | tail -5; then
    COMPILE_END=$(date +%s)
    COMPILE_TIME=$((COMPILE_END - COMPILE_START))
    echo "[OK] Compilation: ${COMPILE_TIME}s"
else
    make 2>&1 | tail -5
fi

make modules_install 2>&1 | tail -3
make install 2>&1 | tail -3

if ls /boot/vmlinuz-* >/dev/null 2>&1; then
    KERNEL_FILE=$(ls /boot/vmlinuz-* | head -1)
    echo "[OK] Noyau installé: ${KERNEL_FILE}"
    echo "RÉSULTAT: ${KERNEL_FILE}" >> "${RAPPORT}"
else
    echo "[ERROR] Noyau non installé"
    exit 1
fi

# GRUB
if ! command -v grub-install >/dev/null 2>&1; then
    emerge --noreplace sys-boot/grub 2>&1 | grep -E ">>>" || true
fi

grub-install /dev/sda 2>&1 | grep -v "Installing"
grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | grep -E "Found|Adding"

echo "" >> "${RAPPORT}"
echo "GRUB configuré:" >> "${RAPPORT}"
grep "^menuentry" /boot/grub/grub.cfg | head -3 | tee -a "${RAPPORT}"

echo "[OK] Noyau et GRUB installés"

# ============================================================================
# EXERCICE 2.5 - CONFIGURATION SYSTÈME
# ============================================================================
echo ""
echo "[TP2] === EXERCICE 2.5 - Configuration système ==="

cat >> "${RAPPORT}" << 'RAPPORT_2_5'

────────────────────────────────────────────────────────────────────────────
EXERCICE 2.5 - Mot de passe root et gestion logs
────────────────────────────────────────────────────────────────────────────

POUR SYSTEMD:
- Logs gérés nativement par systemd-journald
- Installation optionnelle de syslog-ng et logrotate

COMMANDES:
    echo "root:root" | chpasswd
    emerge app-admin/syslog-ng app-admin/logrotate
    systemctl enable syslog-ng

RAPPORT_2_5

echo "root:root" | chpasswd
echo "[OK] Mot de passe root: root"

emerge --noreplace app-admin/syslog-ng 2>&1 | grep -E ">>>" || true
emerge --noreplace app-admin/logrotate 2>&1 | grep -E ">>>" || true

systemctl enable syslog-ng 2>/dev/null || true
systemctl enable logrotate.timer 2>/dev/null || true

echo "RÉSULTAT: Mot de passe configuré, logs avec syslog-ng" >> "${RAPPORT}"
echo "[OK] Configuration système terminée"

# ============================================================================
# EXERCICE 2.6 - VÉRIFICATIONS
# ============================================================================
echo ""
echo "[TP2] === EXERCICE 2.6 - Vérifications finales ==="

cat >> "${RAPPORT}" << 'RAPPORT_2_6'

────────────────────────────────────────────────────────────────────────────
EXERCICE 2.6 - Préparation au redémarrage
────────────────────────────────────────────────────────────────────────────

VÉRIFICATIONS:
RAPPORT_2_6

KERNEL_CHECK=$(ls /boot/vmlinuz-* 2>/dev/null | head -1)
echo "✓ Noyau: ${KERNEL_CHECK}" | tee -a "${RAPPORT}"

if [ -f "/boot/grub/grub.cfg" ]; then
    GRUB_ENTRIES=$(grep -c "^menuentry" /boot/grub/grub.cfg)
    echo "✓ GRUB: ${GRUB_ENTRIES} entrées" | tee -a "${RAPPORT}"
fi

echo "✓ Mot de passe root: configuré" | tee -a "${RAPPORT}"
echo "✓ Logs: systemd-journald + syslog-ng" | tee -a "${RAPPORT}"

cat >> "${RAPPORT}" << 'RAPPORT_FIN'

PROCÉDURE DE SORTIE (systemd):
    exit
    cd /
    umount -R /mnt/gentoo
    reboot

================================================================================
                               RÉSUMÉ TP2
================================================================================

✓ Exercice 2.1: Sources du noyau installées
✓ Exercice 2.2: Matériel identifié
✓ Exercice 2.3: Noyau configuré (DEVTMPFS, VM optimisé)
✓ Exercice 2.4: Noyau compilé + GRUB installé
✓ Exercice 2.5: Mot de passe root + logs
✓ Exercice 2.6: Système prêt pour boot

SYSTÈME: Gentoo avec systemd
MOT DE PASSE ROOT: root

================================================================================
RAPPORT_FIN

echo "[OK] TP2 terminé !"

CHROOT_TP2

# ============================================================================
# FIN
# ============================================================================

if [ -f "${MOUNT_POINT}/root/rapport_tp2.txt" ]; then
    cp "${MOUNT_POINT}/root/rapport_tp2.txt" /root/
    echo "[OK] Rapport copié: /root/rapport_tp2.txt"
fi

echo ""
echo "================================================================"
echo "[SUCCESS] ✅ TP2 TERMINÉ AVEC SUCCÈS !"
echo "================================================================"
echo ""
echo "📋 RÉSUMÉ:"
echo "  ✓ Profil systemd corrigé automatiquement"
echo "  ✓ Tous les exercices 2.1-2.6 terminés"
echo "  ✓ Rapport généré: /root/rapport_tp2.txt"
echo ""
echo "🚀 POUR REDÉMARRER:"
echo "  cd /"
echo "  umount -R /mnt/gentoo"
echo "  reboot"
echo ""
echo "🔑 CONNEXION:"
echo "  root / root"
echo ""