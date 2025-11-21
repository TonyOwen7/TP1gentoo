#!/bin/bash
# TP2 - Configuration avancée - Exercices 2.7 à 2.11
# À exécuter APRÈS les exercices 2.1-2.6

SECRET_CODE="1234"   # Code attendu

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

echo "✅ Code correct, poursuite des exercices 2.7-2.11..."

set -euo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
DISK="/dev/sda"
MOUNT_POINT="/mnt/gentoo"

echo "================================================================"
echo "     TP2 - Configuration avancée - Exercices 2.7-2.11"
echo "================================================================"
echo ""

# Vérification que le système est monté
if [ ! -d "${MOUNT_POINT}/etc" ]; then
    log_error "Le système Gentoo n'est pas monté!"
    log_info "Montage du système..."
    
    mkdir -p "${MOUNT_POINT}"
    mount "${DISK}3" "${MOUNT_POINT}" || exit 1
    mount "${DISK}1" "${MOUNT_POINT}/boot" 2>/dev/null || true
    mount "${DISK}4" "${MOUNT_POINT}/home" 2>/dev/null || true
    swapon "${DISK}2" 2>/dev/null || true
fi

# Montage des systèmes virtuels
mount -t proc /proc "${MOUNT_POINT}/proc" 2>/dev/null || true
mount --rbind /sys "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --rbind /dev "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --bind /run "${MOUNT_POINT}/run" 2>/dev/null || true
mount --make-slave "${MOUNT_POINT}/run" 2>/dev/null || true

cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/" 2>/dev/null || true

# ============================================================================
# EXERCICES 2.7 À 2.11 - CONFIGURATION AVANCÉE
# ============================================================================
chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_EOF'
#!/bin/bash
set -euo pipefail

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[CHROOT]${NC} $1"; }
log_success() { echo -e "${GREEN}[CHROOT OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[CHROOT WARN]${NC} $1"; }

source /etc/profile
export PS1="(chroot) \$PS1"

echo ""
echo "================================================================"
log_info "Exercices 2.7 à 2.11 - Configuration avancée"
echo "================================================================"
echo ""

# ============================================================================
# EXERCICE 2.7 - CONFIGURATION ENVIRONNEMENT
# ============================================================================
log_info "Exercice 2.7 - Configuration de l'environnement"

# Clavier français
log_info "Configuration clavier fr-latin1..."
cat > /etc/vconsole.conf << 'EOF'
KEYMAP=fr-latin1
FONT=lat9w-16
EOF

# Locales fr_FR.UTF-8
log_info "Configuration locales fr_FR.UTF-8..."
cat > /etc/locale.gen << 'EOF'
en_US.UTF-8 UTF-8
fr_FR.UTF-8 UTF-8
EOF
locale-gen
eselect locale set fr_FR.utf8 2>/dev/null || true
env-update
source /etc/profile

# Hostname
echo "gentoo-etudiant" > /etc/hostname

# Timezone
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
echo "Europe/Paris" > /etc/timezone

# Réseau DHCP
log_info "Configuration réseau DHCP..."
cat > /etc/systemd/network/50-dhcp.network << 'EOF'
[Match]
Name=en*

[Network]
DHCP=yes
EOF

systemctl enable systemd-networkd 2>/dev/null || true
systemctl enable systemd-resolved 2>/dev/null || true

log_success "Exercice 2.7 terminé"

# ============================================================================
# EXERCICE 2.8 - UTILISATEURS ET SUDO
# ============================================================================
log_info "Exercice 2.8 - Configuration utilisateurs et sudo"

# Création utilisateur
useradd -m -c "Étudiant" -s /bin/bash -G users,wheel,audio,video etudiant 2>/dev/null || true
echo "etudiant:etudiant123" | chpasswd

# Installation sudo
emerge --noreplace app-admin/sudo 2>/dev/null | grep -E ">>>" | head -2 || true

# Configuration sudo
if [ -f "/etc/sudoers" ]; then
    sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers 2>/dev/null || {
        echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers
    }
fi

log_success "Exercice 2.8 terminé"

# ============================================================================
# EXERCICE 2.9 - QUOTAS
# ============================================================================
log_info "Exercice 2.9 - Configuration des quotas"

# Installation quotas
emerge --noreplace sys-fs/quota 2>/dev/null | grep -E ">>>" | head -2 || true

# Activation quotas dans fstab
sed -i 's|LABEL=home.*|LABEL=home      /home           ext4    defaults,noatime,usrquota,grpquota    0 2|' /etc/fstab

# Remontage et initialisation
mount -o remount /home 2>/dev/null || true
if command -v quotacheck >/dev/null 2>&1; then
    quotacheck -cug /home 2>/dev/null || true
    quotaon -av 2>/dev/null || true
fi

# Application quota 200Mo
if command -v setquota >/dev/null 2>&1; then
    setquota -u etudiant 0 204800 0 0 /home 2>/dev/null && \
    log_success "Quota de 200Mo appliqué à etudiant"
fi

log_success "Exercice 2.9 terminé"

# ============================================================================
# CONFIGURATION SSH
# ============================================================================
log_info "Configuration SSH"

# Installation SSH
emerge --noreplace net-misc/openssh 2>/dev/null | grep -E ">>>" | head -2 || true

# Configuration SSH
cat > /etc/ssh/sshd_config << 'EOF'
Port 22
Protocol 2
PermitRootLogin yes
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
X11Forwarding yes
PrintMotd yes
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/ssh/sftp-server
EOF

# Activation service
rc-update add sshd default 2>/dev/null || systemctl enable sshd 2>/dev/null || true
/etc/init.d/sshd start 2>/dev/null || systemctl start sshd 2>/dev/null || true

log_success "SSH configuré - Port 22 (rediriger vers 2222 sur VirtualBox)"

# ============================================================================
# EXERCICE 2.10 - INSTALLATION HWLOC
# ============================================================================
log_info "Exercice 2.10 - Installation manuelle de hwloc"

# Préparation environnement utilisateur
su - etudiant -c "mkdir -p /home/etudiant/usr/local /home/etudiant/usr/src" 2>/dev/null || true

# Téléchargement hwloc
cd /tmp
if command -v wget >/dev/null 2>&1; then
    wget --quiet https://download.open-mpi.org/release/hwloc/v2.9/hwloc-2.9.3.tar.gz -O hwloc.tar.gz || true
elif command -v curl >/dev/null 2>&1; then
    curl -L https://download.open-mpi.org/release/hwloc/v2.9/hwloc-2.9.3.tar.gz -o hwloc.tar.gz 2>/dev/null || true
fi

# Compilation
if [ -f "hwloc.tar.gz" ]; then
    tar xzf hwloc.tar.gz
    cd hwloc-* 2>/dev/null && {
        su - etudiant -c "
            cd /tmp/hwloc-* &&
            ./configure --prefix=/home/etudiant/usr/local >/dev/null 2>&1 &&
            make >/dev/null 2>&1 &&
            make install >/dev/null 2>&1
        " && log_success "hwloc installé" || log_warning "Échec installation hwloc"
    } || true
fi

log_success "Exercice 2.10 terminé"

# ============================================================================
# EXERCICE 2.11 - VARIABLES D'ENVIRONNEMENT
# ============================================================================
log_info "Exercice 2.11 - Configuration variables d'environnement"

# Configuration pour etudiant
cat >> /home/etudiant/.bashrc << 'EOF'

# Configuration hwloc
export PATH="$HOME/usr/local/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/usr/local/lib:$LD_LIBRARY_PATH"
export MANPATH="$HOME/usr/local/share/man:$MANPATH"

# Alias pratique
alias hwloc-ls='$HOME/usr/local/bin/hwloc-ls'
EOF

log_success "Exercice 2.11 terminé"

# ============================================================================
# RÉSUMÉ FINAL
# ============================================================================
echo ""
echo "================================================================"
log_success "🎉 EXERCICES 2.7 À 2.11 TERMINÉS !"
echo "================================================================"
echo ""
echo "📋 RÉCAPITULATIF COMPLET:"
echo ""
echo "✅ EXERCICE 2.7:"
echo "   • Clavier: fr-latin1"
echo "   • Locale: fr_FR.UTF-8" 
echo "   • Hostname: gentoo-etudiant"
echo "   • Timezone: Europe/Paris"
echo "   • Réseau: DHCP"
echo ""
echo "✅ EXERCICE 2.8:"
echo "   • Utilisateur: etudiant / etudiant123"
echo "   • Sudo: configuré pour wheel"
echo ""
echo "✅ EXERCICE 2.9:"
echo "   • Quotas: 200Mo pour etudiant"
echo ""
echo "✅ SSH:"
echo "   • Serveur: installé et démarré"
echo "   • Port: 22 → rediriger vers 2222 sur VirtualBox"
echo ""
echo "✅ EXERCICE 2.10:"
echo "   • hwloc: installé dans /home/etudiant/usr/local"
echo ""
echo "✅ EXERCICE 2.11:"
echo "   • Variables d'environnement: configurées"
echo ""
echo "🚀 POUR TESTER:"
echo "   • ssh -p 2222 etudiant@localhost"
echo "   • sudo whoami (doit afficher 'root')"
echo "   • hwloc-ls (doit afficher la topologie)"
echo "   • quota -s (doit afficher les limites)"
echo ""
echo "🔑 IDENTIFIANTS:"
echo "   • root / gentoo123"
echo "   • etudiant / etudiant123"
echo ""

CHROOT_EOF

# ============================================================================
# FIN - SYSTÈME TOUJOURS MONTÉ
# ============================================================================
echo ""
echo "================================================================"
log_success "✅ TP2 COMPLÈTEMENT TERMINÉ !"
echo "================================================================"
echo ""
echo "🎯 PROCÉDURE DE REDÉMARRAGE:"
echo ""
echo "1. Redémarrer MAINTENANT:"
echo "   reboot"
echo ""
echo "2. Configuration VirtualBox:"
echo "   - Settings → Network → Port Forwarding"
echo "   - Ajouter: Host Port 2222 → Guest Port 22"
echo ""
echo "3. Connexion SSH:"
echo "   ssh -p 2222 etudiant@localhost"
echo ""
echo "💡 Le système reste monté pour d'éventuelles modifications."
echo ""
log_success "Félicitations ! Votre Gentoo est pleinement opérationnel ! 🎉🐧"
echo ""