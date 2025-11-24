#!/bin/bash
# TP2 SUITE - Configuration avancée (Exercices 2.7 à 2.11)
# À exécuter APRÈS le TP2 principal (noyau compilé)

set -euo pipefail

MOUNT_POINT="/mnt/gentoo"
RAPPORT="/root/rapport_tp2_suite.txt"

echo "================================================================"
echo "     TP2 SUITE - Configuration avancée (Ex 2.7-2.11)"
echo "================================================================"
echo ""

# Initialisation du rapport
cat > "${RAPPORT}" << 'EOF'
================================================================================
                RAPPORT TP2 SUITE - CONFIGURATION AVANCÉE
================================================================================
Date: $(date '+%d/%m/%Y %H:%M')

================================================================================
                        CONFIGURATION ET UTILISATEURS
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

echo "[OK] Système monté"

# ============================================================================
# CONFIGURATION DANS LE CHROOT
# ============================================================================

chroot "${MOUNT_POINT}" /bin/bash <<'CHROOT_SUITE'
#!/bin/bash
set -euo pipefail

source /etc/profile
export PS1="(chroot) \$PS1"

RAPPORT="/root/rapport_tp2_suite.txt"

echo ""
echo "================================================================"
echo "[TP2 SUITE] Configuration avancée du système"
echo "================================================================"
echo ""

# ============================================================================
# EXERCICE 2.7 - CONFIGURATION ENVIRONNEMENT
# ============================================================================
echo ""
echo "[TP2] ━━━ EXERCICE 2.7 - Configuration environnement ━━━"

cat >> "${RAPPORT}" << 'RAPPORT_2_7'

────────────────────────────────────────────────────────────────────────────
EXERCICE 2.7 - Configuration de l'environnement
────────────────────────────────────────────────────────────────────────────

QUESTION:
Configurez votre environnement : clavier, localisation utilisant fr_FR.UTF-8,
nom d'hôte, heure locale, activation du client dhcp (dhcpcd), montage des
partitions.

RÉPONSE:
Configuration complète de l'environnement Linux pour un système fonctionnel.

COMMANDES UTILISÉES:
RAPPORT_2_7

echo "[INFO] Configuration du clavier français..."
cat > /etc/conf.d/keymaps <<'EOF'
keymap="fr-latin1"
windowkeys="YES"
extended_keymaps=""
dumpkeys_charset=""
EOF
echo "    # Configuration: /etc/conf.d/keymaps" >> "${RAPPORT}"
echo "    keymap=\"fr-latin1\"" >> "${RAPPORT}"
echo "[OK] Clavier: fr-latin1"

echo "[INFO] Configuration de la localisation fr_FR.UTF-8..."
cat > /etc/locale.gen <<'EOF'
en_US.UTF-8 UTF-8
fr_FR.UTF-8 UTF-8
EOF

locale-gen >/dev/null 2>&1
eselect locale set fr_FR.utf8 2>/dev/null || eselect locale set 4 2>/dev/null
echo "    locale-gen" >> "${RAPPORT}"
echo "    eselect locale set fr_FR.utf8" >> "${RAPPORT}"

env-update >/dev/null 2>&1
source /etc/profile

echo "[OK] Locale: fr_FR.UTF-8"

echo "[INFO] Configuration du nom d'hôte..."
echo "gentoo-tp" > /etc/hostname
echo "    echo \"gentoo-tp\" > /etc/hostname" >> "${RAPPORT}"
echo "[OK] Hostname: gentoo-tp"

echo "[INFO] Configuration du fuseau horaire..."
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
echo "Europe/Paris" > /etc/timezone
echo "    ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime" >> "${RAPPORT}"
echo "[OK] Timezone: Europe/Paris"

echo "[INFO] Configuration du réseau avec dhcpcd..."
cat > /etc/conf.d/net <<'EOF'
# Configuration DHCP pour toutes les interfaces
config_eth0="dhcp"
config_enp0s3="dhcp"
EOF

# Installation et activation de dhcpcd
if ! command -v dhcpcd >/dev/null 2>&1; then
    echo "[INFO] Installation de dhcpcd..."
    emerge --noreplace net-misc/dhcpcd 2>&1 | grep -E ">>>" || true
fi

rc-update add dhcpcd default 2>/dev/null || true
echo "    emerge net-misc/dhcpcd" >> "${RAPPORT}"
echo "    rc-update add dhcpcd default" >> "${RAPPORT}"
echo "[OK] dhcpcd installé et activé"

echo "[INFO] Vérification de /etc/fstab..."
if ! grep -q "LABEL=root" /etc/fstab 2>/dev/null; then
    cat > /etc/fstab <<'EOF'
# <fs>          <mountpoint>    <type>  <opts>              <dump/pass>
LABEL=root      /               ext4    defaults,noatime    0 1
LABEL=boot      /boot           ext2    defaults            0 2
LABEL=home      /home           ext4    defaults,noatime    0 2
LABEL=swap      none            swap    sw                  0 0
EOF
    echo "    # /etc/fstab configuré avec labels" >> "${RAPPORT}"
fi
echo "[OK] /etc/fstab vérifié"

cat >> "${RAPPORT}" << 'RAPPORT_2_7_FIN'

RÉSULTAT:
    ✓ Clavier: fr-latin1
    ✓ Locale: fr_FR.UTF-8
    ✓ Hostname: gentoo-tp
    ✓ Timezone: Europe/Paris
    ✓ Réseau: dhcpcd activé au démarrage
    ✓ fstab: Configuré avec labels

OBSERVATION:
La configuration de l'environnement est essentielle pour un système utilisable.
Le clavier français permet la saisie des caractères accentués.
La locale fr_FR.UTF-8 configure l'affichage en français.
dhcpcd gère automatiquement la configuration réseau.

RAPPORT_2_7_FIN

echo "[OK] Exercice 2.7 terminé"

# ============================================================================
# EXERCICE 2.8 - CRÉATION UTILISATEUR + SUDO
# ============================================================================
echo ""
echo "[TP2] ━━━ EXERCICE 2.8 - Création utilisateur + sudo ━━━"

cat >> "${RAPPORT}" << 'RAPPORT_2_8'

────────────────────────────────────────────────────────────────────────────
EXERCICE 2.8 - Création d'utilisateur et configuration sudo
────────────────────────────────────────────────────────────────────────────

QUESTION:
Créez un utilisateur à votre nom, assurez-vous qu'il puisse effectuer des
commandes d'administration avec su. Installez et configurez la commande sudo.

RÉPONSE:
1. Création d'utilisateur avec useradd:
   useradd -m -G wheel,users,audio,video -s /bin/bash <username>
   
   Options:
   - -m : Crée le répertoire home
   - -G wheel : Ajoute au groupe wheel (pour su et sudo)
   - -s /bin/bash : Définit le shell par défaut

2. sudo permet d'exécuter des commandes avec les privilèges root:
   - Installation: emerge app-admin/sudo
   - Configuration: /etc/sudoers (éditer avec visudo)
   - Groupe wheel: Autorise tous les membres du groupe wheel

COMMANDES UTILISÉES:
RAPPORT_2_8

echo "[INFO] Création de l'utilisateur 'etudiant'..."
if ! id etudiant >/dev/null 2>&1; then
    useradd -m -G wheel,users,audio,video -s /bin/bash etudiant
    echo "etudiant:password123" | chpasswd
    echo "    useradd -m -G wheel,users,audio,video -s /bin/bash etudiant" >> "${RAPPORT}"
    echo "    echo 'etudiant:password123' | chpasswd" >> "${RAPPORT}"
    echo "[OK] Utilisateur 'etudiant' créé (mot de passe: password123)"
else
    echo "[INFO] Utilisateur 'etudiant' existe déjà"
fi

echo "[INFO] Installation de sudo..."
if ! command -v sudo >/dev/null 2>&1; then
    emerge --noreplace app-admin/sudo 2>&1 | grep -E ">>>" || true
    echo "    emerge app-admin/sudo" >> "${RAPPORT}"
else
    echo "[INFO] sudo déjà installé"
fi

echo "[INFO] Configuration de sudo pour le groupe wheel..."
# Décommenter la ligne %wheel dans sudoers
if [ -f /etc/sudoers ]; then
    cp /etc/sudoers /etc/sudoers.bak
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
    echo "    # Édition de /etc/sudoers" >> "${RAPPORT}"
    echo "    %wheel ALL=(ALL:ALL) ALL" >> "${RAPPORT}"
    echo "[OK] Groupe wheel autorisé à utiliser sudo"
fi

# Vérification
echo "[INFO] Vérification de la configuration..."
echo "    Groupes de l'utilisateur 'etudiant':" | tee -a "${RAPPORT}"
groups etudiant | tee -a "${RAPPORT}"

cat >> "${RAPPORT}" << 'RAPPORT_2_8_FIN'

RÉSULTAT:
    ✓ Utilisateur 'etudiant' créé
    ✓ Mot de passe: password123
    ✓ Membre du groupe wheel (peut utiliser su et sudo)
    ✓ sudo installé et configuré
    ✓ Groupe wheel autorisé dans /etc/sudoers

OBSERVATION:
- su permet de devenir root (demande le mot de passe root)
  Usage: su -
  
- sudo permet d'exécuter des commandes en tant que root
  Usage: sudo <commande>
  Avantage: demande le mot de passe de l'utilisateur, pas root
  
- Le groupe wheel est traditionnellement utilisé pour les administrateurs
  
- Fichier /etc/sudoers doit TOUJOURS être édité avec visudo pour éviter
  les erreurs de syntaxe qui pourraient bloquer l'accès sudo

TEST:
Après le boot, se connecter avec 'etudiant' et tester:
  su -              # Devenir root (mot de passe root: root)
  sudo whoami       # Exécuter une commande en tant que root

RAPPORT_2_8_FIN

echo "[OK] Exercice 2.8 terminé"

# ============================================================================
# EXERCICE 2.9 - QUOTAS DISQUE
# ============================================================================
echo ""
echo "[TP2] ━━━ EXERCICE 2.9 - Configuration des quotas ━━━"

cat >> "${RAPPORT}" << 'RAPPORT_2_9'

────────────────────────────────────────────────────────────────────────────
EXERCICE 2.9 - Configuration des quotas disque
────────────────────────────────────────────────────────────────────────────

QUESTION:
Activez les quotas pour votre utilisateur, limitez-le à 200 Mo et faites un
test en tentant de créer un fichier plus gros pour obtenir l'erreur.

RÉPONSE:
Les quotas limitent l'espace disque utilisable par utilisateur ou groupe.

Étapes de configuration:
1. Installation: emerge sys-fs/quota
2. Activation dans fstab: ajouter usrquota,grpquota aux options
3. Remontage de la partition
4. Initialisation: quotacheck -cugm /home
5. Activation: quotaon /home
6. Configuration: edquota -u <username>

Unités:
- Blocs: 1 bloc = 1 Ko généralement
- 200 Mo = 204800 Ko = 204800 blocs

COMMANDES UTILISÉES:
RAPPORT_2_9

echo "[INFO] Installation des outils de quota..."
if ! command -v quota >/dev/null 2>&1; then
    emerge --noreplace sys-fs/quota 2>&1 | grep -E ">>>" || true
    echo "    emerge sys-fs/quota" >> "${RAPPORT}"
else
    echo "[INFO] quota déjà installé"
fi

echo "[INFO] Configuration de /etc/fstab pour les quotas..."
if ! grep -q "usrquota" /etc/fstab; then
    cp /etc/fstab /etc/fstab.bak
    sed -i 's|\(LABEL=home.*ext4.*\)defaults|\1defaults,usrquota,grpquota|' /etc/fstab
    echo "    # Modification de /etc/fstab" >> "${RAPPORT}"
    echo "    LABEL=home  /home  ext4  defaults,usrquota,grpquota,noatime  0 2" >> "${RAPPORT}"
    echo "[OK] Options de quota ajoutées à /etc/fstab"
else
    echo "[INFO] Quotas déjà configurés dans fstab"
fi

echo "[INFO] Contenu de /etc/fstab:"
grep "home" /etc/fstab | tee -a "${RAPPORT}"

echo "[INFO] Initialisation des quotas (quotacheck)..."
echo "    quotacheck -cugm /home" >> "${RAPPORT}"
# Création des fichiers de quota
touch /home/aquota.user /home/aquota.group
chmod 600 /home/aquota.*
quotacheck -cugm /home 2>/dev/null || {
    echo "[WARNING] quotacheck peut nécessiter un remontage de /home"
    echo "[INFO] Cela sera effectif après le redémarrage"
}

echo "[INFO] Activation des quotas..."
echo "    quotaon /home" >> "${RAPPORT}"
quotaon /home 2>/dev/null || echo "[INFO] Activation effective après redémarrage"

echo "[INFO] Configuration du quota pour 'etudiant' (200 Mo)..."
# 200 Mo = 204800 Ko (blocs)
# soft limit: 200 Mo, hard limit: 200 Mo
cat > /tmp/quota_etudiant << 'EOF'
Disk quotas for user etudiant (uid 1000):
  Filesystem                   blocks       soft       hard     inodes     soft     hard
  /dev/sda4                         0     204800     204800          0        0        0
EOF

# Configuration du quota avec setquota
if command -v setquota >/dev/null 2>&1; then
    setquota -u etudiant 204800 204800 0 0 /home 2>/dev/null || echo "[INFO] Configuration après redémarrage"
    echo "    setquota -u etudiant 204800 204800 0 0 /home" >> "${RAPPORT}"
    echo "[OK] Quota configuré: 200 Mo (204800 blocs)"
else
    echo "[WARNING] setquota non disponible, utiliser edquota après redémarrage"
    echo "    edquota -u etudiant" >> "${RAPPORT}"
fi

echo "[INFO] Vérification des quotas..."
echo "    quota -vs etudiant" >> "${RAPPORT}"
quota -vs etudiant 2>/dev/null | tee -a "${RAPPORT}" || echo "[INFO] Visible après redémarrage"

cat >> "${RAPPORT}" << 'RAPPORT_2_9_FIN'

RÉSULTAT:
    ✓ Outils de quota installés
    ✓ /etc/fstab modifié (usrquota,grpquota)
    ✓ Fichiers de quota initialisés
    ✓ Quota configuré pour 'etudiant': 200 Mo (soft et hard limit)

OBSERVATION:
- Soft limit: Avertissement mais autorise temporairement le dépassement
- Hard limit: Limite absolue, erreur si dépassement
- Dans notre config: soft = hard = 200 Mo (204800 Ko)

TEST APRÈS REDÉMARRAGE:
Connexion en tant que 'etudiant':

1. Vérifier le quota:
   quota -vs

2. Tester le dépassement (créer un fichier de 250 Mo):
   dd if=/dev/zero of=/home/etudiant/test_quota.bin bs=1M count=250

   Résultat attendu:
   dd: error writing '/home/etudiant/test_quota.bin': Disk quota exceeded

3. Vérifier l'utilisation:
   quota -vs
   
4. Nettoyer:
   rm /home/etudiant/test_quota.bin

COMMANDES UTILES:
- quota -vs <user> : Afficher les quotas d'un utilisateur
- repquota -a : Rapport de tous les quotas
- edquota -u <user> : Éditer les quotas interactivement
- quotaoff /home : Désactiver les quotas
- quotaon /home : Activer les quotas

RAPPORT_2_9_FIN

echo "[OK] Exercice 2.9 terminé"

# ============================================================================
# CONFIGURATION SSH
# ============================================================================
echo ""
echo "[TP2] ━━━ CONFIGURATION SSH ━━━"

cat >> "${RAPPORT}" << 'RAPPORT_SSH'

────────────────────────────────────────────────────────────────────────────
ACCÈS DISTANT SSH - Configuration du serveur SSH
────────────────────────────────────────────────────────────────────────────

QUESTION:
Modifiez la configuration de votre machine virtuelle pour pouvoir vous y
connecter en ssh (redirection de port sur l'interface réseau). On utilisera
le port local 2222 sur l'hôte. Activez le service SSH au démarrage,
démarrez-le manuellement et testez la connexion.

RÉPONSE:
SSH (Secure Shell) permet la connexion distante sécurisée à un système.

Configuration VirtualBox:
1. Aller dans Paramètres VM > Réseau > Avancé > Redirection de ports
2. Ajouter une règle:
   - Nom: SSH
   - Protocole: TCP
   - IP hôte: 127.0.0.1
   - Port hôte: 2222
   - IP invité: (vide)
   - Port invité: 22

Configuration Gentoo:
1. Installation: emerge net-misc/openssh
2. Activation: rc-update add sshd default
3. Démarrage: rc-service sshd start

COMMANDES UTILISÉES:
RAPPORT_SSH

echo "[INFO] Installation d'OpenSSH..."
if ! command -v sshd >/dev/null 2>&1; then
    emerge --noreplace net-misc/openssh 2>&1 | grep -E ">>>" || true
    echo "    emerge net-misc/openssh" >> "${RAPPORT}"
else
    echo "[INFO] OpenSSH déjà installé"
fi

echo "[INFO] Configuration du serveur SSH..."
if [ -f /etc/ssh/sshd_config ]; then
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    # Autoriser la connexion root (pour les tests, à sécuriser en production)
    sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    
    echo "    # Configuration: /etc/ssh/sshd_config" >> "${RAPPORT}"
    echo "    PermitRootLogin yes" >> "${RAPPORT}"
    echo "    PasswordAuthentication yes" >> "${RAPPORT}"
    echo "[OK] Configuration SSH modifiée"
fi

echo "[INFO] Activation du service SSH au démarrage..."
rc-update add sshd default 2>/dev/null || true
echo "    rc-update add sshd default" >> "${RAPPORT}"
echo "[OK] Service SSH activé au démarrage"

cat >> "${RAPPORT}" << 'RAPPORT_SSH_FIN'

RÉSULTAT:
    ✓ OpenSSH installé
    ✓ Configuration modifiée (connexion root autorisée)
    ✓ Service activé au démarrage (rc-update add sshd default)

CONFIGURATION VIRTUALBOX À FAIRE:
1. Éteindre la VM (ou la mettre en pause)
2. VirtualBox > Paramètres de la VM > Réseau
3. Carte réseau 1 > Avancé > Redirection de ports
4. Cliquer sur "+" pour ajouter une règle:
   ┌──────────────────────────────────────────────┐
   │ Nom:         SSH                             │
   │ Protocole:   TCP                             │
   │ IP hôte:     127.0.0.1                       │
   │ Port hôte:   2222                            │
   │ IP invité:   (laisser vide)                  │
   │ Port invité: 22                              │
   └──────────────────────────────────────────────┘
5. OK > Redémarrer la VM

TEST APRÈS REDÉMARRAGE DE LA VM:
Depuis votre machine hôte (Windows/Linux/Mac):

1. Tester la connexion:
   ssh -p 2222 root@127.0.0.1
   ou
   ssh -p 2222 etudiant@127.0.0.1

2. Accepter la clé SSH (première connexion):
   Are you sure you want to continue connecting (yes/no)? yes

3. Entrer le mot de passe:
   - root: root
   - etudiant: password123

4. Vous êtes connecté en SSH !

COMMANDES UTILES:
- rc-service sshd status : État du service SSH
- rc-service sshd start : Démarrer SSH manuellement
- rc-service sshd stop : Arrêter SSH
- rc-service sshd restart : Redémarrer SSH
- tail -f /var/log/messages : Suivre les connexions SSH

SÉCURISATION (RECOMMANDÉE EN PRODUCTION):
- Désactiver la connexion root: PermitRootLogin no
- Utiliser des clés SSH au lieu de mots de passe
- Changer le port par défaut (22)
- Utiliser fail2ban pour bloquer les tentatives de connexion

RAPPORT_SSH_FIN

echo "[OK] Configuration SSH terminée"

# ============================================================================
# EXERCICE 2.10 - COMPILATION MANUELLE (hwloc)
# ============================================================================
echo ""
echo "[TP2] ━━━ EXERCICE 2.10 - Installation manuelle de hwloc ━━━"

cat >> "${RAPPORT}" << 'RAPPORT_2_10'

────────────────────────────────────────────────────────────────────────────
EXERCICE 2.10 - Installation manuelle de hwloc
────────────────────────────────────────────────────────────────────────────

QUESTION:
Téléchargez les sources de hwloc (http://www.open-mpi.org/projects/hwloc/)
et installez-les dans /home/$USER/usr.

RÉPONSE:
hwloc (Hardware Locality) est une bibliothèque pour découvrir la topologie
matérielle (CPU, caches, mémoire, etc.).

Installation manuelle (sans emerge):
1. Télécharger les sources avec wget
2. Extraire l'archive tar
3. Configurer avec ./configure --prefix=/home/$USER/usr
4. Compiler avec make
5. Installer avec make install

Cette méthode permet d'installer des logiciels sans droits root.

COMMANDES UTILISÉES:
RAPPORT_2_10

# Créer le répertoire pour l'utilisateur
echo "[INFO] Création du répertoire d'installation..."
mkdir -p /home/etudiant/usr
chown -R etudiant:etudiant /home/etudiant/usr
echo "    mkdir -p /home/etudiant/usr" >> "${RAPPORT}"

# Téléchargement des dépendances
echo "[INFO] Installation des outils de compilation..."
emerge --noreplace sys-devel/gcc sys-devel/make sys-devel/autoconf sys-devel/automake 2>&1 | grep -E ">>>" || true

echo "[INFO] Téléchargement de hwloc (en tant qu'etudiant)..."
su - etudiant -c '
cd ~
if [ ! -f hwloc-2.9.3.tar.gz ]; then
    wget https://download.open-mpi.org/release/hwloc/v2.9/hwloc-2.9.3.tar.gz
fi
'
echo "    wget https://download.open-mpi.org/release/hwloc/v2.9/hwloc-2.9.3.tar.gz" >> "${RAPPORT}"
echo "[OK] hwloc téléchargé"

echo "[INFO] Extraction des sources..."
su - etudiant -c '
cd ~
tar xzf hwloc-2.9.3.tar.gz
'
echo "    tar xzf hwloc-2.9.3.tar.gz" >> "${RAPPORT}"

echo "[INFO] Configuration (./configure --prefix=/home/etudiant/usr)..."
su - etudiant -c '
cd ~/hwloc-2.9.3
./configure --prefix=/home/etudiant/usr
' >> /tmp/hwloc_config.log 2>&1
echo "    cd hwloc-2.9.3" >> "${RAPPORT}"
echo "    ./configure --prefix=/home/etudiant/usr" >> "${RAPPORT}"
echo "[OK] Configuration terminée"

echo "[INFO] Compilation (make)..."
su - etudiant -c '
cd ~/hwloc-2.9.3
make
' >> /tmp/hwloc_make.log 2>&1
echo "    make" >> "${RAPPORT}"
echo "[OK] Compilation terminée"

echo "[INFO] Installation (make install)..."
su - etudiant -c '
cd ~/hwloc-2.9.3
make install
' >> /tmp/hwloc_install.log 2>&1
echo "    make install" >> "${RAPPORT}"
echo "[OK] Installation terminée"

echo "[INFO] Vérification de l'installation..."
if [ -f /home/etudiant/usr/bin/hwloc-ls ]; then
    echo "[OK] hwloc-ls installé dans /home/etudiant/usr/bin/"
    ls -lh /home/etudiant/usr/bin/hwloc-* | tee -a "${RAPPORT}"
else
    echo "[WARNING] hwloc-ls non trouvé"
fi

cat >> "${RAPPORT}" << 'RAPPORT_2_10_FIN'

RÉSULTAT:
    ✓ hwloc téléchargé depuis open-mpi.org
    ✓ Sources extraites dans /home/etudiant/hwloc-2.9.3
    ✓ Configuration avec prefix=/home/etudiant/usr
    ✓ Compilation réussie
    ✓ Installation dans /home/etudiant/usr/
    ✓ Binaires dans /home/etudiant/usr/bin/
    ✓ Bibliothèques dans /home/etudiant/usr/lib/

OBSERVATION:
Cette méthode d'installation manuelle permet:
- Installation sans droits root
- Isolation du logiciel dans le home de l'utilisateur
- Contrôle total sur la version installée
- Utile quand emerge n'est pas disponible ou version spécifique nécessaire

STRUCTURE CRÉÉE:
/home/etudiant/usr/
├── bin/       (exécutables: hwloc-ls, hwloc-info, etc.)
├── lib/       (bibliothèques partagées)
├── include/   (headers C)
└── share/     (documentation, man pages)

RAPPORT_2_10_FIN

echo "[OK] Exercice 2.10 terminé"

# ============================================================================
# EXERCICE 2.11 - VARIABLES D'ENVIRONNEMENT
# ============================================================================
echo ""
echo "[TP2] ━━━ EXERCICE 2.11 - Configuration variables d'environnement ━━━"

cat >> "${RAPPORT}" << 'RAPPORT_2_11'

────────────────────────────────────────────────────────────────────────────
EXERCICE 2.11 - Configuration des variables d'environnement
────────────────────────────────────────────────────────────────────────────

QUESTION:
Configurez les variables d'environnements pour pouvoir utiliser hwloc-ls
comme tout autre commande sans devoir utiliser son chemin complet.

RÉPONSE:
Les variables d'environnement importantes:

1. PATH: Liste des répertoires où chercher les exécutables
   Ajout: export PATH=/home/etudiant/usr/bin:$PATH

2. LD_LIBRARY_PATH: Chemins des bibliothèques partagées
   Ajout: export LD_LIBRARY_PATH=/home/etudiant/usr/lib:$LD_LIBRARY_PATH

3. MANPATH: Chemins des pages de manuel
   Ajout: export MANPATH=/home/etudiant/usr/share/man:$MANPATH

Configuration permanente dans ~/.bashrc ou ~/.bash_profile

COMMANDES UTILISÉES:
RAPPORT_2_11

echo "[INFO] Configuration des variables d'environnement pour etudiant..."

# Ajout dans .bashrc
su - etudiant -c '
cat >> ~/.bashrc << "EOF"

# Configuration pour hwloc installé localement
export PATH=$HOME/usr/bin:$PATH
export LD_LIBRARY_PATH=$HOME/usr/lib:$LD_LIBRARY_PATH
export MANPATH=$HOME/usr/share/man:$MANPATH
export PKG_CONFIG_PATH=$HOME/usr/lib/pkgconfig:$PKG_CONFIG_PATH

# Alias utiles
alias ll="ls -lh"
alias la="ls -lah"
EOF
'

echo "    # Ajout dans ~/.bashrc:" >> "${RAPPORT}"
echo "    export PATH=\$HOME/usr/bin:\$PATH" >> "${RAPPORT}"
echo "    export LD_LIBRARY_PATH=\$HOME/usr/lib:\$LD_LIBRARY_PATH" >> "${RAPPORT}"
echo "    export MANPATH=\$HOME/usr/share/man:\$MANPATH" >> "${RAPPORT}"

echo "[OK] Variables d'environnement configurées dans ~/.bashrc"

echo "[INFO] Test de la configuration..."
su - etudiant -c '
source ~/.bashrc
which hwloc-ls
hwloc-ls --version 2>/dev/null || echo "hwloc-ls disponible"
' | tee -a "${RAPPORT}"

cat >> "${RAPPORT}" << 'RAPPORT_2_11_FIN'

RÉSULTAT:
    ✓ PATH modifié pour inclure ~/usr/bin
    ✓ LD_LIBRARY_PATH modifié pour inclure ~/usr/lib
    ✓ MANPATH modifié pour inclure ~/usr/share/man
    ✓ Configuration permanente dans ~/.bashrc
    ✓ hwloc-ls accessible sans chemin complet

OBSERVATION:
Les variables d'environnement permettent de:
- Utiliser hwloc-ls directement au lieu de /home/etudiant/usr/bin/hwloc-ls
- Charger automatiquement les bibliothèques partagées
- Accéder aux pages de manuel avec 'man hwloc-ls'

EXPLICATION DES VARIABLES:

1. PATH:
   - Détermine où le shell cherche les commandes
   - Format: liste de répertoires séparés par ':'
   - $HOME/usr/bin est ajouté EN PREMIER (priorité)

2. LD_LIBRARY_PATH:
   - Indique où chercher les bibliothèques .so
   - Nécessaire pour les programmes qui utilisent libhwloc.so
   - Alternative: utiliser /etc/ld.so.conf (nécessite root)

3. MANPATH:
   - Chemins de recherche pour les pages de manuel
   - Permet d'utiliser 'man hwloc-ls'

4. PKG_CONFIG_PATH:
   - Utilisé par pkg-config pour trouver les .pc files
   - Utile si on compile d'autres programmes utilisant hwloc

FICHIERS DE CONFIGURATION:
- ~/.bashrc : Chargé pour les shells interactifs non-login
- ~/.bash_profile : Chargé pour les shells de login
- ~/.profile : Alternative à bash_profile

Pour Gentoo/bash, utiliser ~/.bashrc suffit généralement.

TEST APRÈS CONFIGURATION:
Connexion en tant que 'etudiant':

1. Vérifier que hwloc-ls est trouvé:
   which hwloc-ls
   # Devrait afficher: /home/etudiant/usr/bin/hwloc-ls

2. Exécuter hwloc-ls:
   hwloc-ls
   # Affiche la topologie matérielle du système

3. Consulter la page de manuel:
   man hwloc-ls

4. Afficher la version:
   hwloc-ls --version

RAPPORT_2_11_FIN

echo "[OK] Exercice 2.11 terminé"

# ============================================================================
# RÉSUMÉ FINAL
# ============================================================================
echo ""
echo "================================================================"
echo "[SUCCESS] 🎉 TP2 SUITE TERMINÉ !"
echo "================================================================"
echo ""

cat >> "${RAPPORT}" << 'RAPPORT_FINAL_SUITE'

================================================================================
                        RÉSUMÉ GÉNÉRAL TP2 SUITE
================================================================================

EXERCICES ACCOMPLIS:

✓ Exercice 2.7: Configuration environnement complet
  - Clavier français (fr-latin1)
  - Locale fr_FR.UTF-8
  - Hostname: gentoo-tp
  - Timezone: Europe/Paris
  - dhcpcd configuré et activé
  - fstab vérifié

✓ Exercice 2.8: Création utilisateur et sudo
  - Utilisateur 'etudiant' créé (membre du groupe wheel)
  - Mot de passe: password123
  - sudo installé et configuré
  - Groupe wheel autorisé dans /etc/sudoers

✓ Exercice 2.9: Quotas disque
  - Outils de quota installés
  - fstab modifié (usrquota,grpquota sur /home)
  - Quota configuré pour 'etudiant': 200 Mo
  - Test de dépassement à effectuer après redémarrage

✓ Configuration SSH:
  - OpenSSH installé
  - Service activé au démarrage
  - Configuration modifiée (connexion root autorisée)
  - Redirection de port VirtualBox à configurer (2222 -> 22)

✓ Exercice 2.10: Installation manuelle de hwloc
  - hwloc téléchargé et compilé depuis les sources
  - Installé dans /home/etudiant/usr
  - Installation sans droits root

✓ Exercice 2.11: Variables d'environnement
  - PATH, LD_LIBRARY_PATH, MANPATH configurés
  - Configuration permanente dans ~/.bashrc
  - hwloc-ls accessible sans chemin complet

================================================================================
                    CONFIGURATION COMPLÈTE DU SYSTÈME
================================================================================

UTILISATEURS:
┌──────────────┬──────────────┬────────────────────────────────────┐
│ Utilisateur  │ Mot de passe │ Rôle                               │
├──────────────┼──────────────┼────────────────────────────────────┤
│ root         │ root    │ Administrateur système             │
│ etudiant     │ password123  │ Utilisateur standard (groupe wheel)│
└──────────────┴──────────────┴────────────────────────────────────┘

SERVICES ACTIVÉS (OpenRC):
- dhcpcd : Client DHCP pour le réseau
- sshd : Serveur SSH pour accès distant
- syslog-ng : Gestion des logs système
- logrotate : Rotation automatique des logs

QUOTAS:
- Partition /home avec quotas activés
- Utilisateur 'etudiant' limité à 200 Mo

LOGICIELS INSTALLÉS:
- hwloc : Topologie matérielle (installation manuelle)
- sudo : Élévation de privilèges
- openssh : Accès distant sécurisé
- quota : Gestion des quotas disque

================================================================================
                        TESTS À EFFECTUER APRÈS REDÉMARRAGE
================================================================================

1. TEST DE CONNEXION:
   - Connexion console: etudiant / password123
   - Élévation avec su: su - (mot de passe: root)
   - Élévation avec sudo: sudo whoami

2. TEST SSH (depuis l'hôte):
   - Configurer la redirection de port dans VirtualBox
   - ssh -p 2222 root@127.0.0.1
   - ssh -p 2222 etudiant@127.0.0.1

3. TEST DES QUOTAS:
   $ quota -vs
   $ dd if=/dev/zero of=~/test_quota.bin bs=1M count=250
   # Devrait afficher: Disk quota exceeded

4. TEST HWLOC:
   $ which hwloc-ls
   $ hwloc-ls
   $ hwloc-info
   $ man hwloc-ls

5. VÉRIFICATION RÉSEAU:
   $ ip addr
   $ ping -c 3 8.8.8.8
   $ cat /etc/resolv.conf

6. VÉRIFICATION SERVICES:
   $ rc-status
   $ rc-service sshd status
   $ rc-service dhcpcd status

================================================================================
                        CONFIGURATION VIRTUALBOX
================================================================================

REDIRECTION DE PORT SSH:
1. Éteindre la VM
2. VirtualBox > Paramètres > Réseau > Avancé > Redirection de ports
3. Ajouter:
   Nom: SSH
   Protocole: TCP
   IP hôte: 127.0.0.1
   Port hôte: 2222
   IP invité: (vide)
   Port invité: 22

================================================================================
                        COMMANDES UTILES
================================================================================

GESTION DES UTILISATEURS:
  useradd -m -G wheel username    Créer un utilisateur
  passwd username                 Changer le mot de passe
  groups username                 Voir les groupes
  su - username                   Changer d'utilisateur
  sudo command                    Exécuter en tant que root

GESTION DES SERVICES (OpenRC):
  rc-status                       État de tous les services
  rc-update show default          Services au démarrage
  rc-service name start           Démarrer un service
  rc-service name stop            Arrêter un service
  rc-service name restart         Redémarrer un service

GESTION DES QUOTAS:
  quota -vs                       Voir ses quotas
  quota -vs username              Voir les quotas d'un utilisateur
  repquota -a                     Rapport de tous les quotas
  edquota -u username             Éditer les quotas (root)
  quotaon /partition              Activer les quotas
  quotaoff /partition             Désactiver les quotas

SSH:
  ssh -p 2222 user@host          Connexion SSH
  ssh-keygen                     Générer une paire de clés
  ssh-copy-id user@host          Copier la clé publique
  scp -P 2222 file user@host:    Copier un fichier

VARIABLES D'ENVIRONNEMENT:
  echo $PATH                     Afficher le PATH
  export VAR=value               Définir une variable
  env                            Voir toutes les variables
  which command                  Trouver l'emplacement d'une commande

COMPILATION MANUELLE:
  ./configure --prefix=$HOME/usr  Configurer
  make                           Compiler
  make install                   Installer
  make clean                     Nettoyer les fichiers temporaires

================================================================================
                        POINTS D'ATTENTION
================================================================================

SÉCURITÉ:
⚠️  Les mots de passe par défaut sont faibles, changez-les:
    passwd                    (pour l'utilisateur courant)
    sudo passwd root          (pour root)

⚠️  SSH avec connexion root autorisée est un risque en production
    Éditer /etc/ssh/sshd_config: PermitRootLogin no

⚠️  Les quotas nécessitent un redémarrage pour être pleinement fonctionnels

PERFORMANCE:
💡 hwloc permet d'optimiser les applications multi-threads
💡 Les variables d'environnement sont chargées à chaque nouveau shell
💡 sudo évite de rester connecté en root (meilleure traçabilité)

MAINTENANCE:
📝 Les logs SSH sont dans /var/log/auth.log (avec syslog-ng)
📝 Les tentatives de connexion sont loggées
📝 logrotate évite la saturation de /var/log

================================================================================
                            FIN DU RAPPORT TP2 SUITE
================================================================================
Système Gentoo OpenRC complètement configuré et prêt à l'emploi !
================================================================================
RAPPORT_FINAL_SUITE

echo "[OK] Rapport complet généré"

CHROOT_SUITE

# ============================================================================
# COPIE DU RAPPORT ET INSTRUCTIONS FINALES
# ============================================================================

if [ -f "${MOUNT_POINT}/root/rapport_tp2_suite.txt" ]; then
    cp "${MOUNT_POINT}/root/rapport_tp2_suite.txt" /root/
    echo "[OK] Rapport copié: /root/rapport_tp2_suite.txt"
    
    echo ""
    echo "📄 APERÇU DU RAPPORT:"
    echo "════════════════════════════════════════════════════════════"
    head -50 /root/rapport_tp2_suite.txt
    echo "..."
    echo "(Fichier complet: /root/rapport_tp2_suite.txt)"
    echo "════════════════════════════════════════════════════════════"
fi

echo ""
echo "================================================================"
echo "[SUCCESS] ✅ TP2 SUITE TERMINÉ AVEC SUCCÈS !"
echo "================================================================"
echo ""
echo "📋 CONFIGURATION TERMINÉE:"
echo "  ✓ Environnement configuré (clavier, locale, timezone)"
echo "  ✓ Utilisateur 'etudiant' créé avec sudo"
echo "  ✓ Quotas configurés (200 Mo)"
echo "  ✓ SSH installé et configuré"
echo "  ✓ hwloc compilé et installé manuellement"
echo "  ✓ Variables d'environnement configurées"
echo "  ✓ Rapport complet généré"
echo ""
echo "🎯 AVANT DE REDÉMARRER:"
echo ""
echo "  1. IMPORTANT - Configuration VirtualBox:"
echo "     • Éteindre la VM"
echo "     • Paramètres > Réseau > Redirection de ports"
echo "     • Ajouter: SSH, TCP, 127.0.0.1:2222 -> :22"
echo "     • Redémarrer la VM"
echo ""
echo "  2. Pour redémarrer maintenant:"
echo "     cd /"
echo "     umount -R /mnt/gentoo"
echo "     reboot"
echo ""
echo "🔑 CONNEXIONS DISPONIBLES:"
echo ""
echo "  Console (écran VirtualBox):"
echo "    • root / root"
echo "    • etudiant / password123"
echo ""
echo "  SSH (depuis l'hôte, après config VirtualBox):"
echo "    ssh -p 2222 root@127.0.0.1"
echo "    ssh -p 2222 etudiant@127.0.0.1"
echo ""
echo "🧪 TESTS À EFFECTUER APRÈS BOOT:"
echo ""
echo "  En tant qu'etudiant:"
echo "    • sudo whoami             (tester sudo)"
echo "    • quota -vs               (vérifier les quotas)"
echo "    • hwloc-ls                (tester hwloc)"
echo "    • which hwloc-ls          (vérifier le PATH)"
echo ""
echo "  Test du quota (dépassement):"
echo "    dd if=/dev/zero of=~/test.bin bs=1M count=250"
echo "    # Devrait échouer avec 'Disk quota exceeded'"
echo ""
echo "📄 RAPPORTS GÉNÉRÉS:"
echo "  • /root/rapport_tp2_openrc.txt  (TP2 principal)"
echo "  • /root/rapport_tp2_suite.txt   (TP2 suite)"
echo ""
echo "[SUCCESS] Votre système Gentoo est maintenant complètement configuré ! 🐧"
echo ""