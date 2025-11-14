#!/bin/bash
# Gentoo Installation Script - SUITE (Post-installation)
# Optimisé pour VirtualBox
# À exécuter APRÈS le premier script et APRÈS le chroot

set -euo pipefail

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "${MAGENTA}
==== $1 ====${NC}"; }

echo "================================================================"
echo "     Installation Gentoo - Suite et Optimisations VirtualBox"
echo "================================================================"
echo ""

# Vérifier qu'on est bien dans un environnement Gentoo
if [ ! -f "/etc/gentoo-release" ]; then
    log_error "Ce script doit être exécuté dans un environnement Gentoo"
    log_info "Êtes-vous dans le chroot ? Si non, faites :"
    echo "  chroot /mnt/gentoo /bin/bash"
    echo "  source /etc/profile"
    exit 1
fi

log_success "Environnement Gentoo détecté"

# ============================================================================
# INSTALLATION DES OUTILS VIRTUALBOX
# ============================================================================
log_section "Installation des Guest Additions VirtualBox"

log_info "Installation des dépendances pour VirtualBox"
emerge --noreplace --quiet \
    sys-apps/dbus \
    x11-base/xorg-server \
    x11-drivers/xf86-video-vesa \
    x11-drivers/xf86-input-evdev \
    2>&1 | grep -E ">>>|Emerging" || true

log_info "Installation de virtualbox-guest-additions"
emerge --noreplace --quiet app-emulation/virtualbox-guest-additions 2>&1 | grep -E ">>>|Emerging" || true
log_success "VirtualBox Guest Additions installées"

# Activation des services VirtualBox
log_info "Activation des services VirtualBox"
rc-update add virtualbox-guest-additions default 2>/dev/null || \
systemctl enable vboxservice 2>/dev/null || true
log_success "Services VirtualBox configurés"

# ============================================================================
# OPTIMISATIONS POUR VIRTUALBOX
# ============================================================================
log_section "Optimisations pour VirtualBox"

# Configuration du module noyau vboxguest
log_info "Configuration des modules VirtualBox"
cat >> /etc/modules-load.d/virtualbox.conf <<'EOF'
vboxguest
vboxsf
vboxvideo
EOF
log_success "Modules VirtualBox configurés pour le chargement automatique"

# Ajout de l'utilisateur au groupe vboxsf pour les dossiers partagés
if id -u student >/dev/null 2>&1; then
    usermod -aG vboxsf,vboxusers student
    log_success "Utilisateur 'student' ajouté aux groupes VirtualBox"
fi

# ============================================================================
# INSTALLATION D'UN ENVIRONNEMENT GRAPHIQUE LÉGER (OPTIONNEL)
# ============================================================================
log_section "Installation d'un environnement graphique (XFCE)"

read -p "Voulez-vous installer XFCE (environnement graphique léger) ? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Installation de XFCE et des outils graphiques (cela peut prendre du temps)"
    
    # Installation du serveur X
    log_info "Installation de Xorg..."
    emerge --noreplace --quiet x11-base/xorg-server 2>&1 | grep -E ">>>|Emerging" || true
    
    # Installation de XFCE
    log_info "Installation de XFCE4 (cela peut prendre 30-60 minutes)..."
    emerge --noreplace --quiet xfce-base/xfce4-meta 2>&1 | grep -E ">>>|Emerging" || true
    
    # Installation d'un gestionnaire de connexion
    log_info "Installation de LightDM (gestionnaire de connexion)"
    emerge --noreplace --quiet x11-misc/lightdm 2>&1 | grep -E ">>>|Emerging" || true
    
    # Configuration de LightDM
    rc-update add dbus default 2>/dev/null || systemctl enable dbus 2>/dev/null || true
    rc-update add lightdm default 2>/dev/null || systemctl enable lightdm 2>/dev/null || true
    
    # Installation d'un navigateur web
    log_info "Installation de Firefox..."
    emerge --noreplace --quiet www-client/firefox 2>&1 | grep -E ">>>|Emerging" || true
    
    log_success "Environnement graphique XFCE installé"
    
    # Configuration pour démarrer en mode graphique
    log_info "Configuration du démarrage en mode graphique"
    systemctl set-default graphical.target 2>/dev/null || \
    rc-update add xdm default 2>/dev/null || true
    
    log_success "Le système démarrera en mode graphique"
fi

# ============================================================================
# INSTALLATION D'OUTILS ESSENTIELS
# ============================================================================
log_section "Installation d'outils système essentiels"

log_info "Installation d'outils de base..."
emerge --noreplace --quiet \
    app-editors/vim \
    app-editors/nano \
    sys-apps/net-tools \
    sys-process/htop \
    sys-process/lsof \
    app-misc/tmux \
    app-arch/unzip \
    app-arch/zip \
    net-misc/wget \
    net-misc/curl \
    sys-apps/pciutils \
    sys-apps/usbutils \
    2>&1 | grep -E ">>>|Emerging" || true

log_success "Outils système installés"

# ============================================================================
# CONFIGURATION RÉSEAU AVANCÉE
# ============================================================================
log_section "Configuration réseau pour VirtualBox"

# Configuration pour NetworkManager (plus simple)
log_info "Installation de NetworkManager"
emerge --noreplace --quiet net-misc/networkmanager 2>&1 | grep -E ">>>|Emerging" || true

rc-update add NetworkManager default 2>/dev/null || \
systemctl enable NetworkManager 2>/dev/null || true

log_success "NetworkManager installé et activé"

# ============================================================================
# OPTIMISATIONS PERFORMANCE VIRTUALBOX
# ============================================================================
log_section "Optimisations des performances"

# Configuration du scheduler I/O pour VM
log_info "Configuration du scheduler I/O pour VM"
cat >> /etc/sysctl.d/99-vm-optimization.conf <<'EOF'
# Optimisations pour machine virtuelle
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
EOF

log_success "Paramètres kernel optimisés pour VM"

# ============================================================================
# CONFIGURATION DES DOSSIERS PARTAGÉS VIRTUALBOX
# ============================================================================
log_section "Configuration des dossiers partagés VirtualBox"

log_info "Création du point de montage pour les dossiers partagés"
mkdir -p /mnt/shared
chown student:users /mnt/shared 2>/dev/null || true

# Ajout dans fstab pour montage automatique
if ! grep -q "vboxsf" /etc/fstab; then
    echo "# VirtualBox shared folders" >> /etc/fstab
    echo "# Décommentez et adaptez selon vos besoins" >> /etc/fstab
    echo "#shared /mnt/shared vboxsf defaults,uid=1000,gid=100 0 0" >> /etc/fstab
    log_success "Entrée fstab ajoutée (commentée par défaut)"
else
    log_info "Entrée fstab pour dossiers partagés déjà présente"
fi

cat > /home/student/README-shared.txt 2>/dev/null <<'EOF' || true
=== Configuration des dossiers partagés VirtualBox ===

1. Dans VirtualBox, allez dans :
   Machine > Configuration > Dossiers partagés

2. Ajoutez un dossier partagé :
   - Nom : shared
   - Chemin : (votre dossier hôte)
   - Montage automatique : Oui

3. Dans Gentoo, montez avec :
   sudo mount -t vboxsf shared /mnt/shared

4. Pour un montage automatique au démarrage :
   Décommentez la ligne dans /etc/fstab et redémarrez

EOF

chown student:users /home/student/README-shared.txt 2>/dev/null || true
log_success "Documentation des dossiers partagés créée"

# ============================================================================
# CONFIGURATION SSH (OPTIONNEL)
# ============================================================================
log_section "Configuration SSH"

read -p "Voulez-vous installer et activer SSH ? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Installation d'OpenSSH"
    emerge --noreplace --quiet net-misc/openssh 2>&1 | grep -E ">>>|Emerging" || true
    
    # Configuration SSH sécurisée
    log_info "Configuration sécurisée de SSH"
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
    
    rc-update add sshd default 2>/dev/null || systemctl enable sshd 2>/dev/null || true
    
    log_success "SSH installé et configuré (connexion root désactivée)"
    echo ""
    log_info "Pour accéder en SSH depuis l'hôte :"
    echo "  1. Dans VirtualBox : Configuration > Réseau"
    echo "  2. Mode : NAT"
    echo "  3. Redirection de ports : 2222 (hôte) -> 22 (invité)"
    echo "  4. Connexion : ssh -p 2222 student@localhost"
fi

# ============================================================================
# CRÉATION D'UN SCRIPT DE MISE À JOUR SYSTÈME
# ============================================================================
log_section "Création de scripts utilitaires"

log_info "Création d'un script de mise à jour système"
cat > /usr/local/bin/update-system <<'EOF'
#!/bin/bash
# Script de mise à jour complète du système Gentoo

echo "=== Mise à jour du système Gentoo ==="
echo ""

echo "[1/4] Synchronisation de l'arbre Portage..."
emerge --sync

echo ""
echo "[2/4] Mise à jour de la liste des paquets..."
emerge --update --deep --newuse @world --ask

echo ""
echo "[3/4] Nettoyage des dépendances obsolètes..."
emerge --depclean --ask

echo ""
echo "[4/4] Mise à jour de la configuration..."
etc-update

echo ""
echo "✓ Mise à jour terminée !"
EOF

chmod +x /usr/local/bin/update-system
log_success "Script 'update-system' créé"

# Script de snapshot VM
log_info "Création d'un script d'information système"
cat > /usr/local/bin/system-info <<'EOF'
#!/bin/bash
# Affiche les informations système

echo "=== Informations Système Gentoo ==="
echo ""
echo "Hostname : $(hostname)"
echo "Kernel   : $(uname -r)"
echo "Uptime   : $(uptime -p)"
echo ""
echo "=== Utilisation des ressources ==="
free -h
echo ""
df -h | grep -E "^/dev|Filesystem"
echo ""
echo "=== Réseau ==="
ip -br addr
echo ""
echo "=== VirtualBox ==="
if lsmod | grep -q vboxguest; then
    echo "✓ Modules VirtualBox chargés"
else
    echo "✗ Modules VirtualBox NON chargés"
fi
EOF

chmod +x /usr/local/bin/system-info
log_success "Script 'system-info' créé"

# ============================================================================
# CONFIGURATION DE BASH POUR L'UTILISATEUR
# ============================================================================
log_section "Configuration de l'environnement utilisateur"

log_info "Configuration de bashrc pour student"
cat >> /home/student/.bashrc <<'EOF'

# Alias personnalisés
alias ll='ls -lah --color=auto'
alias update='sudo update-system'
alias info='system-info'
alias ports='sudo netstat -tulpn'

# Prompt coloré
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# Historique amélioré
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoredups:erasedups

echo "Bienvenue sur Gentoo Linux!"
echo "Tapez 'info' pour voir les informations système"
echo "Tapez 'update' pour mettre à jour le système"
EOF

chown student:users /home/student/.bashrc
log_success "Configuration bash personnalisée"

# ============================================================================
# RÉSUMÉ ET INSTRUCTIONS FINALES
# ============================================================================
echo ""
echo "================================================================"
log_success "🎉 Configuration post-installation terminée !"
echo "================================================================"
echo ""
echo "📦 Logiciels installés :"
echo "  ✓ VirtualBox Guest Additions (dossiers partagés, clipboard)"
echo "  ✓ Outils système (vim, nano, htop, curl, wget, etc.)"
echo "  ✓ NetworkManager (gestion réseau simplifiée)"
if [[ -f /usr/bin/startxfce4 ]]; then
    echo "  ✓ Environnement graphique XFCE"
fi
if [[ -f /usr/sbin/sshd ]]; then
    echo "  ✓ Serveur SSH"
fi
echo ""
echo "🔧 Optimisations appliquées :"
echo "  ✓ Modules VirtualBox configurés"
echo "  ✓ Paramètres kernel optimisés pour VM"
echo "  ✓ Dossiers partagés configurés (/mnt/shared)"
echo "  ✓ Scripts utilitaires créés"
echo ""
echo "👤 Comptes utilisateur :"
echo "  - root : gentoo (À CHANGER !)"
echo "  - student : student (À CHANGER !)"
echo ""
echo "🛠️ Commandes utiles :"
echo "  update-system  : Met à jour le système complet"
echo "  system-info    : Affiche les infos système"
echo "  htop           : Moniteur de ressources"
echo ""
echo "📁 Dossiers partagés VirtualBox :"
echo "  Lisez : /home/student/README-shared.txt"
echo "  Point de montage : /mnt/shared"
echo ""
echo "⚙️ Configuration VirtualBox recommandée :"
echo "  - Mémoire : 2048 MB minimum (4096 MB recommandé)"
echo "  - Processeurs : 2 cœurs minimum"
echo "  - Accélération 3D : Activée (pour XFCE)"
echo "  - Clipboard bidirectionnel : Activé"
echo "  - Dossier partagé : Configuré si nécessaire"
echo ""
echo "🔄 Prochaines étapes :"
echo "  1. Sortir du chroot si vous y êtes : exit"
echo "  2. Redémarrer la machine : reboot"
echo "  3. Retirer le LiveCD de VirtualBox"
echo "  4. Au premier démarrage, changer les mots de passe :"
echo "     passwd          (pour root)"
echo "     passwd student  (pour student)"
echo ""
if [[ -f /usr/bin/startxfce4 ]]; then
echo "  5. Le système démarrera en mode graphique automatiquement"
else
echo "  5. Pour installer XFCE plus tard, relancez ce script"
fi
echo ""
log_success "Votre système Gentoo est maintenant optimisé pour VirtualBox ! 🚀"
echo ""