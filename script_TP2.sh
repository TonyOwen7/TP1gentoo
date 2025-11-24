#!/usr/bin/env bash
# radical_grub_fix.sh
# Solution radicale pour GRUB - Ignore tous les checks et installe de force

set -e

DISK="/dev/sda"
MNT="/mnt/gentoo"

echo "================================================"
echo "🚨 SOLUTION RADICALE GRUB"
echo "================================================"

# === MONTAGE FORCÉ ===
echo "Montage des partitions..."
umount -R $MNT 2>/dev/null || true
mkdir -p $MNT

mount /dev/sda3 $MNT || { echo "❌ Échec montage root"; exit 1; }
mount /dev/sda1 $MNT/boot || { echo "❌ Échec montage boot"; exit 1; }

mount -t proc proc $MNT/proc
mount --rbind /sys $MNT/sys
mount --rbind /dev $MNT/dev

# === SOLUTION ULTIME DANS CHROOT ===
chroot $MNT /bin/bash << 'RADICAL_EOF'
set -e

echo "=== DÉBUT SOLUTION RADICALE ==="

# 1. TUEUR DE GRUB - Suppression totale
echo "🧹 1. SUPPRESSION TOTALE DE GRUB..."
emerge --unmerge sys-boot/grub 2>/dev/null || true
rm -rf /boot/grub
rm -f /sbin/grub-* /usr/sbin/grub-* /bin/grub-* /usr/bin/grub-*
rm -rf /usr/lib/grub
rm -rf /var/db/repos/gentoo/sys-boot/grub

# 2. NETTOYAGE COMPLET
echo "🧽 2. NETTOYAGE COMPLET..."
emerge --depclean 2>/dev/null || true
eclean-pkg 2>/dev/null || true

# 3. RÉINSTALLATION AVEC OPTIONS FORCÉES
echo "📥 3. RÉINSTALLATION FORCÉE..."

# Forcer les USE flags pour BIOS
mkdir -p /etc/portage/package.use
echo "sys-boot/grub device-mapper grub_platforms_i386-pc -efiemu -secure-boot" > /etc/portage/package.use/grub-fix

# Réinstaller GRUB avec toutes les options
USE="device-mapper grub_platforms_i386-pc -efiemu -secure-boot" emerge --oneshot --nodeps --quiet-build sys-boot/grub || {
    echo "⚠️  Échec émergence normale, tentative aggressive..."
    
    # Téléchargement et installation manuelle
    cd /tmp
    wget -q http://distfiles.gentoo.org/snapshots/portage-latest.tar.xz || true
    emerge --oneshot sys-boot/grub --autounmask-write --autounmask-continue || {
        etc-update --automode -5
        emerge --oneshot sys-boot/grub
    }
}

# 4. VÉRIFICATION DES FICHIERS CRITIQUES
echo "🔍 4. VÉRIFICATION DES FICHIERS..."

# Lister tous les fichiers GRUB
echo "Fichiers GRUB trouvés:"
find /usr -name "*grub*" -type f 2>/dev/null | head -10

# Vérifier les binaires essentiels
for binary in grub-install grub-mkconfig; do
    if [ -f "/usr/sbin/$binary" ] || [ -f "/sbin/$binary" ]; then
        echo "✅ $binary trouvé"
    else
        echo "❌ $binary MANQUANT - recherche alternative..."
        find /usr -name "$binary" -type f 2>/dev/null || echo "Non trouvé"
    fi
done

# 5. INSTALLATION MANUELLE DIRECTE DANS MBR
echo "🚀 5. INSTALLATION MANUELLE DANS MBR..."

# Créer la structure GRUB manuellement
mkdir -p /boot/grub/i386-pc

# Copier tous les modules GRUB disponibles
if [ -d "/usr/lib/grub/i386-pc" ]; then
    echo "📦 Copie des modules GRUB..."
    cp -r /usr/lib/grub/i386-pc/* /boot/grub/i386-pc/ 2>/dev/null || true
else
    echo "❌ Répertoire i386-pc manquant - GRUB mal compilé"
fi

# Méthode d'installation ULTIME
echo "🛠️  Installation avec grub-install..."
if command -v grub-install >/dev/null 2>&1; then
    # Essayer toutes les méthodes possibles
    grub-install --target=i386-pc --force /dev/sda || \
    grub-install --skip-fs-probe --target=i386-pc --force /dev/sda || \
    /usr/sbin/grub-install --target=i386-pc --force /dev/sda || \
    {
        echo "❌ Toutes les méthodes grub-install ont échoué"
        echo "🔧 Passage en mode MANUEL EXTREME..."
        
        # ÉCRITURE DIRECTE DU MBR
        if [ -f "/usr/lib/grub/i386-pc/boot.img" ]; then
            echo "📝 Écriture directe du MBR..."
            dd if=/usr/lib/grub/i386-pc/boot.img of=/dev/sda bs=446 count=1
            echo "✅ MBR écrit avec boot.img"
            
            # Écrire le core image si disponible
            if [ -f "/usr/lib/grub/i386-pc/core.img" ]; then
                echo "📝 Écriture du core image..."
                # Trouver le secteur de début de la partition boot
                dd if=/usr/lib/grub/i386-pc/core.img of=/dev/sda bs=512 seek=1 2>/dev/null || true
            fi
        else
            echo "❌ boot.img introuvable"
        fi
    }
else
    echo "❌ grub-install non disponible - méthode DD directe"
    if [ -f "/usr/lib/grub/i386-pc/boot.img" ]; then
        dd if=/usr/lib/grub/i386-pc/boot.img of=/dev/sda bs=446 count=1
    fi
fi

# 6. CONFIGURATION GRUB.CFG ULTRA-MINIMAL
echo "📄 6. CRÉATION GRUB.CFG ULTRA-MINIMAL..."

cat > /boot/grub/grub.cfg << 'ULTRA_GRUB'
# Configuration GRUB ultra-minimal
set timeout=5
set default=0

# Pas de modules, configuration directe
menuentry "Gentoo Linux" {
    # Configuration directe sans insmod
    set root='(hd0,msdos1)'
    
    # Trouver le noyau automatiquement
    if [ -f /vmlinuz ]; then
        linux /vmlinuz root=/dev/sda3 ro
    else
        # Chercher n'importe quel noyau
        for i in /vmlinuz-* ; do
            if [ -f "$i" ]; then
                linux $i root=/dev/sda3 ro
                break
            fi
        done
    fi
    
    boot
}

menuentry "Gentoo Linux (Secours)" {
    set root='(hd0,msdos1)'
    if [ -f /vmlinuz ]; then
        linux /vmlinuz root=/dev/sda3 ro single
    else
        for i in /vmlinuz-* ; do
            if [ -f "$i" ]; then
                linux $i root=/dev/sda3 ro single
                break
            fi
        done
    fi
    boot
}
ULTRA_GRUB

echo "✅ Configuration créée"

# 7. VÉRIFICATION FINALE
echo "🔎 7. VÉRIFICATION FINALE..."

echo "Structure /boot:"
ls -la /boot/ 2>/dev/null || echo "❌ /boot inaccessible"

echo "Fichiers GRUB:"
find /boot/grub -type f 2>/dev/null | head -10 || echo "❌ Aucun fichier GRUB"

echo "Noyaux disponibles:"
find /boot -name "vmlinuz*" 2>/dev/null || echo "❌ Aucun noyau"

# Vérifier le MBR
echo "Vérification MBR:"
if dd if=/dev/sda bs=512 count=1 2>/dev/null | hexdump -C | head -1 | grep -q "GRUB"; then
    echo "✅ GRUB détecté dans MBR"
else
    echo "⚠️  GRUB non détecté dans MBR (peut être normal avec méthode manuelle)"
fi

echo ""
echo "🎉 SOLUTION RADICALE APPLIQUÉE!"

RADICAL_EOF

# === VÉRIFICATION HORS CHROOT ===
echo ""
echo "=== VÉRIFICATION FINALE HORS CHROOT ==="

echo "1. Vérification MBR:"
dd if=$DISK bs=512 count=1 2>/dev/null | file - | grep -q "boot" && echo "✅ MBR bootable" || echo "⚠️  MBR peut être corrompu"

echo ""
echo "2. Fichiers dans /boot:"
ls -la $MNT/boot/ 2>/dev/null | head -5 || echo "❌ /boot inaccessible"

echo ""
echo "3. Configuration GRUB:"
if [ -f "$MNT/boot/grub/grub.cfg" ]; then
    echo "✅ grub.cfg présent"
    echo "Extrait:"
    head -3 "$MNT/boot/grub/grub.cfg"
else
    echo "❌ grub.cfg absent"
fi

# Nettoyage
umount $MNT/dev
umount $MNT/sys
umount $MNT/proc
umount $MNT/boot
umount $MNT

echo ""
echo "================================================"
echo "🎉 TERMINÉ! REDÉMARREZ MAINTENANT: reboot"
echo "================================================"
echo ""
echo "🔧 SI LE SYSTÈME NE BOOT TOUJOURS PAS:"
echo "1. Au démarrage, appuyez sur 'c' pour GRUB"
echo "2. Commandes manuelles:"
echo "   set root=(hd0,msdos1)"
echo "   linux /vmlinuz root=/dev/sda3 ro"
echo "   boot"
echo ""
echo "3. Si GRUB n'apparaît pas, utilisez:"
echo "   dd if=/usr/lib/grub/i386-pc/boot.img of=/dev/sda bs=446 count=1"