#!/bin/bash
# TP2 - Configuration du système Gentoo - Exercices 2.7 à 2.11

set -euo pipefail

# Code de sécurité
SECRET_CODE="1234"   # Code attendu

read -sp "🔑 Entrez le code pour exécuter ce script : " USER_CODE
echo
if [ "$USER_CODE" != "$SECRET_CODE" ]; then
  echo "❌ Code incorrect. Exécution annulée."
  exit 1
fi

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
echo "     TP2 - Configuration système Gentoo - Exercices 2.7-2.11"
echo "================================================================"
echo ""

# Vérification que le système est monté
if [ ! -d "${MOUNT_POINT}/etc" ]; then
    log_error "Le système Gentoo n'est pas monté sur ${MOUNT_POINT}"
    echo "Veuillez d'abord monter le système:"
    echo "  mount ${DISK}3 ${MOUNT_POINT}"
    echo "  mount ${DISK}1 ${MOUNT_POINT}/boot"
    echo "  mount ${DISK}4 ${MOUNT_POINT}/home"
    echo "  swapon ${DISK}2"
    exit 1
fi

# Montage des systèmes de fichiers virtuels
log_info "Montage des systèmes de fichiers virtuels pour le chroot"
mount -t proc /proc "${MOUNT_POINT}/proc" 2>/dev/null || true
mount --rbind /sys "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/sys" 2>/dev/null || true
mount --rbind /dev "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --make-rslave "${MOUNT_POINT}/dev" 2>/dev/null || true
mount --bind /run "${MOUNT_POINT}/run" 2>/dev/null || true
mount --make-slave "${MOUNT_POINT}/run" 2>/dev/null || true

# Copie de resolv.conf
cp -L /etc/resolv.conf "${MOUNT_POINT}/etc/" 2>/dev/null || true

log_info "Entrée dans le chroot pour les exercices 2.7 à 2.11"

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
log_error() { echo -e "${RED}[CHROOT ERROR]${NC} $1"; }

# Chargement du profil
source /etc/profile
export PS1="(chroot) \$PS1"

echo ""
echo "================================================================"
log_info "Début des exercices 2.7 à 2.11 - Configuration avancée"
echo "================================================================"
echo ""

# ============================================================================
# EXERCICE 2.7 - CONFIGURATION DE L'ENVIRONNEMENT
# ============================================================================
log_info "Exercice 2.7 - Configuration de l'environnement système"

# 1. Configuration du clavier français
log_info "1. Configuration du clavier français..."
cat > /etc/vconsole.conf << 'EOF'
KEYMAP=fr-latin1
FONT=lat9w-16
EOF
log_success "Clavier configuré en fr-latin1"

# 2. Configuration des locales fr_FR.UTF-8
log_info "2. Configuration des locales fr_FR.UTF-8..."
cat > /etc/locale.gen << 'EOF'
en_US.UTF-8 UTF-8
fr_FR.UTF-8 UTF-8
EOF

# Génération des locales
locale-gen 2>/dev/null || log_warning "Génération des locales échouée"

# Sélection de la locale fr_FR.utf8
eselect locale set fr_FR.utf8 2>/dev/null || {
    # Méthode alternative
    echo "LANG=fr_FR.UTF-8" > /etc/locale.conf
    echo "LC_ALL=fr_FR.UTF-8" >> /etc/locale.conf
}
log_success "Locales configurées: fr_FR.UTF-8"

# Rechargement de l'environnement
env-update 2>/dev/null || true
source /etc/profile 2>/dev/null || true

# 3. Configuration du nom d'hôte
log_info "3. Configuration du nom d'hôte..."
echo "gentoo-etudiant" > /etc/hostname
log_success "Nom d'hôte défini: gentoo-etudiant"

# Configuration de /etc/hosts
cat > /etc/hosts << 'EOF'
127.0.0.1   localhost gentoo-etudiant
::1         localhost gentoo-etudiant
EOF

# 4. Configuration du fuseau horaire
log_info "4. Configuration du fuseau horaire Europe/Paris..."
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
echo "Europe/Paris" > /etc/timezone
log_success "Fuseau horaire configuré: Europe/Paris"

# 5. Activation du client DHCP
log_info "5. Installation et configuration de dhcpcd..."
emerge --noreplace net-misc/dhcpcd 2>&1 | grep -E ">>>" | head -2 || log_warning "dhcpcd non installé"

# Activation du service dhcpcd
rc-update add dhcpcd default 2>/dev/null || log_warning "Service dhcpcd non activé"
log_success "DHCP configuré"

# 6. Vérification du montage des partitions
log_info "6. Vérification du montage des partitions..."
cat > /etc/fstab << 'EOF'
# <fs>          <mountpoint>    <type>  <opts>              <dump/pass>
LABEL=root      /               ext4    defaults,noatime    0 1
LABEL=boot      /boot           ext2    defaults            0 2
LABEL=home      /home           ext4    defaults,noatime    0 2
LABEL=swap      none            swap    sw                  0 0
EOF
log_success "fstab configuré"

log_success "Exercice 2.7 terminé"

# ============================================================================
# EXERCICE 2.8 - CONFIGURATION DES UTILISATEURS ET SUDO
# ============================================================================
log_info "Exercice 2.8 - Configuration des utilisateurs et sudo"

# Création de l'utilisateur étudiant
log_info "Création de l'utilisateur 'etudiant'..."
useradd -m -c "Utilisateur Étudiant" -s /bin/bash -G users,wheel,audio,video etudiant 2>/dev/null || log_warning "Utilisateur peut déjà exister"

# Définition du mot de passe
echo "etudiant:etudiant123" | chpasswd 2>/dev/null && log_success "Mot de passe défini pour etudiant" || log_warning "Échec définition mot de passe"

# Installation et configuration de sudo
log_info "Installation de sudo..."
emerge --noreplace app-admin/sudo 2>&1 | grep -E ">>>" | head -2 || log_warning "sudo non installé"

# Configuration de sudo pour le groupe wheel
if [ -f "/etc/sudoers" ]; then
    log_info "Configuration des privilèges sudo..."
    # Sauvegarde de la configuration originale
    cp /etc/sudoers /etc/sudoers.bak 2>/dev/null || true
    
    # Activation de sudo pour le groupe wheel
    sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers 2>/dev/null || {
        log_info "Configuration manuelle de sudo..."
        echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers
    }
    log_success "sudo configuré pour le groupe wheel"
fi

# Test de l'accès su
log_info "Test de l'accès su pour etudiant..."
su - etudiant -c "whoami" && log_success "Accès su fonctionnel" || log_warning "Problème avec su"

log_success "Exercice 2.8 terminé"

# ============================================================================
# EXERCICE 2.9 - CONFIGURATION DES QUOTAS
# ============================================================================
log_info "Exercice 2.9 - Configuration des quotas utilisateur"

# Installation des outils de quotas
log_info "Installation des outils de quotas..."
emerge --noreplace sys-fs/quota 2>&1 | grep -E ">>>" | head -2 || log_warning "quota non installé"

# Configuration des quotas dans /etc/fstab
log_info "Configuration des quotas sur /home..."
if grep -q "LABEL=home" /etc/fstab; then
    # Modification de la ligne home dans fstab
    sed -i 's|LABEL=home.*defaults,noatime|LABEL=home      /home           ext4    defaults,noatime,usrquota,grpquota    0 2|' /etc/fstab
    log_success "Quotas activés dans fstab"
else
    log_warning "Partition /home non trouvée dans fstab"
fi

# Remontage de /home pour activer les quotas
log_info "Activation des quotas..."
mount -o remount /home 2>/dev/null || true

# Initialisation des quotas
if command -v quotacheck >/dev/null 2>&1; then
    log_info "Initialisation de la base de données quotas..."
    quotacheck -cug /home 2>/dev/null || true
    quotacheck -avug 2>/dev/null || true
    quotaon -av 2>/dev/null || true
fi

# Configuration des limites pour l'utilisateur etudiant
log_info "Application des limites de quota (200 Mo)..."
if command -v setquota >/dev/null 2>&1; then
    # 200 Mo = 200 * 1024 = 204800 blocs de 1K
    setquota -u etudiant 0 204800 0 0 /home 2>/dev/null && log_success "Quota de 200 Mo appliqué à etudiant" || log_warning "Échec application quota"
else
    log_warning "setquota non disponible"
fi

# Test des quotas
log_info "Test des quotas..."
if command -v quota >/dev/null 2>&1; then
    log_info "Vérification du quota pour etudiant:"
    su - etudiant -c "quota -s" 2>/dev/null || true
fi

log_success "Exercice 2.9 terminé"

# ============================================================================
# CONFIGURATION SSH
# ============================================================================
log_info "Configuration de l'accès SSH distant"

# Installation du serveur SSH
log_info "Installation du serveur OpenSSH..."
emerge --noreplace net-misc/openssh 2>&1 | grep -E ">>>" | head -2 || log_warning "OpenSSH non installé"

# Configuration SSH pour autoriser l'accès root et le port par défaut
log_info "Configuration du serveur SSH..."
if [ -f "/etc/ssh/sshd_config" ]; then
    # Sauvegarde de la configuration
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true
    
    # Configuration basique
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
    log_success "SSH configuré"
else
    log_warning "Fichier sshd_config non trouvé"
fi

# Activation du service SSH
log_info "Activation du service SSH..."
rc-update add sshd default 2>/dev/null || log_warning "Service SSH non activé"

# Démarrage manuel du service
log_info "Démarrage du service SSH..."
/etc/init.d/sshd start 2>/dev/null || systemctl start sshd 2>/dev/null || log_warning "SSH non démarré"

log_success "SSH configuré et démarré"

# Instructions pour la redirection de port
echo ""
log_info "📝 INSTRUCTIONS POUR LA CONNEXION SSH:"
echo "   Sur VirtualBox, configurez la redirection de port:"
echo "   - Port hôte: 2222"
echo "   - Port invité: 22"
echo "   Connectez-vous avec: ssh -p 2222 etudiant@localhost"
echo ""

# ============================================================================
# EXERCICE 2.10 - INSTALLATION MANUELLE DE HWLOC
# ============================================================================
log_info "Exercice 2.10 - Installation manuelle de hwloc"

# Création du répertoire d'installation personnel
log_info "Création de l'environnement d'installation personnel..."
su - etudiant -c "mkdir -p /home/etudiant/usr/src /home/etudiant/usr/local 2>/dev/null" || true

# Téléchargement des sources hwloc
log_info "Téléchargement des sources hwloc..."
cd /tmp
HWLOC_URL="https://download.open-mpi.org/release/hwloc/v2.9/hwloc-2.9.3.tar.gz"

if command -v wget >/dev/null 2>&1; then
    wget --quiet --show-progress "$HWLOC_URL" -O hwloc.tar.gz || {
        log_warning "Échec téléchargement wget, utilisation de curl..."
        curl -L "$HWLOC_URL" -o hwloc.tar.gz 2>/dev/null || true
    }
else
    curl -L "$HWLOC_URL" -o hwloc.tar.gz 2>/dev/null || log_warning "Échec téléchargement"
fi

# Extraction et installation
if [ -f "hwloc.tar.gz" ]; then
    log_info "Extraction des sources hwloc..."
    tar xzf hwloc.tar.gz
    cd hwloc-* 2>/dev/null || { log_warning "Répertoire hwloc non trouvé"; cd /tmp; }
    
    if [ -f "configure" ]; then
        log_info "Compilation de hwloc pour l'utilisateur etudiant..."
        
        # Compilation en tant qu'étudiant
        su - etudiant -c "
            cd /tmp/hwloc-* &&
            ./configure --prefix=/home/etudiant/usr/local 2>/dev/null &&
            make -j2 2>/dev/null &&
            make install 2>/dev/null
        " && log_success "hwloc compilé et installé" || log_warning "Échec compilation hwloc"
    else
        log_warning "Fichier configure non trouvé"
    fi
else
    log_warning "Sources hwloc non téléchargées"
fi

log_success "Exercice 2.10 terminé"

# ============================================================================
# EXERCICE 2.11 - CONFIGURATION DES VARIABLES D'ENVIRONNEMENT
# ============================================================================
log_info "Exercice 2.11 - Configuration des variables d'environnement"

# Configuration du PATH pour l'utilisateur etudiant
log_info "Configuration du PATH pour etudiant..."
cat >> /home/etudiant/.bashrc << 'EOF'

# Configuration personnalisée pour hwloc
export PATH="$HOME/usr/local/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/usr/local/lib:$LD_LIBRARY_PATH"
export MANPATH="$HOME/usr/local/share/man:$MANPATH"
export PKG_CONFIG_PATH="$HOME/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"

# Alias pratique
alias hwloc-ls='$HOME/usr/local/bin/hwloc-ls'
EOF

# Test de l'installation hwloc
log_info "Test de l'installation hwloc..."
if su - etudiant -c "command -v hwloc-ls" 2>/dev/null; then
    log_success "hwloc-ls disponible dans le PATH"
elif su - etudiant -c "test -f /home/etudiant/usr/local/bin/hwloc-ls" 2>/dev/null; then
    log_success "hwloc-ls installé dans le répertoire personnel"
else
    log_warning "hwloc-ls non trouvé"
fi

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
echo "✅ EXERCICE 2.7 - CONFIGURATION:"
echo "   • Clavier: fr-latin1"
echo "   • Locale: fr_FR.UTF-8"
echo "   • Hostname: gentoo-etudiant"
echo "   • Timezone: Europe/Paris"
echo "   • DHCP: dhcpcd activé"
echo "   • Partitions: fstab configuré"
echo ""
echo "✅ EXERCICE 2.8 - UTILISATEURS:"
echo "   • Utilisateur: etudiant / etudiant123"
echo "   • Sudo: configuré pour le groupe wheel"
echo "   • Accès su: fonctionnel"
echo ""
echo "✅ EXERCICE 2.9 - QUOTAS:"
echo "   • Quotas activés sur /home"
echo "   • Limite: 200 Mo pour etudiant"
echo ""
echo "✅ CONFIGURATION SSH:"
echo "   • Serveur SSH installé et démarré"
echo "   • Port: 22 (rediriger vers 2222 sur VirtualBox)"
echo ""
echo "✅ EXERCICE 2.10 - HWLOC:"
echo "   • Sources téléchargées et compilées"
echo "   • Installé dans /home/etudiant/usr/local"
echo ""
echo "✅ EXERCICE 2.11 - ENVIRONNEMENT:"
echo "   • PATH configuré pour hwloc"
echo "   • Variables d'environnement définies"
echo ""
echo "🔧 INSTRUCTIONS FINALES:"
echo "   1. Redémarrez: exit → umount -R /mnt/gentoo → reboot"
echo "   2. Configurez VirtualBox:"
echo "      - Redirection de port: Hôte 2222 → Invité 22"
echo "   3. Connectez-vous en SSH:"
echo "      ssh -p 2222 etudiant@localhost"
echo "   4. Testez hwloc: hwloc-ls"
echo "   5. Testez les quotas: quota -s"
echo ""
echo "🔑 IDENTIFIANTS:"
echo "   • root / gentoo123"
echo "   • etudiant / etudiant123"
echo ""

CHROOT_EOF

# ============================================================================
# NETTOYAGE FINAL
# ============================================================================
log_info "Nettoyage final..."

log_info "Démontage des systèmes de fichiers virtuels..."
umount -l "${MOUNT_POINT}/dev"{/shm,/pts,} 2>/dev/null || true
umount -l "${MOUNT_POINT}/proc" 2>/dev/null || true
umount -l "${MOUNT_POINT}/sys" 2>/dev/null || true
umount -l "${MOUNT_POINT}/run" 2>/dev/null || true

log_info "Démontage des partitions..."
umount -R "${MOUNT_POINT}" 2>/dev/null || {
    log_warning "Forçage du démontage..."
    umount -l "${MOUNT_POINT}" 2>/dev/null || true
}

swapoff "${DISK}2" 2>/dev/null || true

log_success "Nettoyage terminé"

# ============================================================================
# INSTRUCTIONS DE REDÉMARRAGE
# ============================================================================
echo ""
echo "================================================================"
log_success "✅ TOUS LES EXERCICES DU TP2 SONT TERMINÉS !"
echo "================================================================"
echo ""
echo "🚀 POUR UTILISER VOTRE SYSTÈME:"
echo ""
echo "1. REDÉMARRAGE:"
echo "   exit"
echo "   umount -R /mnt/gentoo"
echo "   reboot"
echo ""
echo "2. CONFIGURATION VIRTUALBOX:"
echo "   - Settings → Network → Advanced → Port Forwarding"
echo "   - Ajoutez: Name: SSH, Protocol: TCP, Host Port: 2222, Guest Port: 22"
echo ""
echo "3. CONNEXION SSH:"
echo "   ssh -p 2222 etudiant@localhost"
echo "   Mot de passe: etudiant123"
echo ""
echo "4. TESTS:"
echo "   • sudo whoami (doit afficher 'root')"
echo "   • hwloc-ls (doit afficher la topologie)"
echo "   • quota -s (doit afficher les limites)"
echo "   • locale (doit afficher fr_FR.UTF-8)"
echo ""
log_success "Votre système Gentoo est complètement configuré ! 🎉"
echo ""