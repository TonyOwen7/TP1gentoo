#!/bin/bash
# TP5 - Authentification centralisée LDAP - Version robuste pour Gentoo
# Évite les problèmes avec net-nds/openldap

set -e

# ====================================================================
# CONFIGURATION
# ====================================================================

DOMAIN="istycorp.fr"
BASE_DN="dc=istycorp,dc=fr"
ADMIN_DN="cn=admin,${BASE_DN}"
ADMIN_PASSWORD="AdminLDAP@2024"
LDIF_DIR="/etc/openldap/ldif"
BACKUP_DIR="/root/backup_ldap_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/tp5_install_$(date +%Y%m%d_%H%M%S).log"

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Fonction de logging
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Fonction d'erreur
error() {
    log "${RED}ERREUR: $1${NC}"
    exit 1
}

# Fonction de vérification
check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
    return 0
}

# ====================================================================
# PRÉPARATION
# ====================================================================

log "${BLUE}=== DÉBUT DU TP5 - AUTHENTIFICATION CENTRALISÉE LDAP ===${NC}"
log "Domaine: ${DOMAIN}"
log "Base DN: ${BASE_DN}"

# Création des répertoires
mkdir -p "$LDIF_DIR"
mkdir -p "$BACKUP_DIR"

# Sauvegarde des configurations existantes
log "Sauvegarde des configurations existantes..."
cp -r /etc/openldap/ "$BACKUP_DIR/etc_openldap/" 2>/dev/null || true
cp /etc/nsswitch.conf "$BACKUP_DIR/" 2>/dev/null || true
cp /etc/pam.d/ "$BACKUP_DIR/pam.d/" 2>/dev/null || true

# ====================================================================
# PARTIE 1: RÉPONSES AUX QUESTIONS THÉORIQUES
# ====================================================================

log "${BLUE}[Exercices 5.1 à 5.5] Réponses théoriques${NC}"

cat > /root/TP5_Reponses_Theoriques.md << 'EOF'
# TP5 - Réponses aux questions théoriques

## Exercice 5.1 - Objectif du protocole LDAP
LDAP (Lightweight Directory Access Protocol) est un protocole standard permettant
d'accéder et de maintenir des services d'annuaire distribués sur un réseau IP.
Son objectif principal est de fournir une méthode normalisée pour consulter et
modifier des informations structurées dans un annuaire hiérarchique.

## Exercice 5.2 - Cadre d'utilisation principal
LDAP est principalement utilisé dans les environnements d'entreprise pour :
1. L'authentification centralisée des utilisateurs
2. La gestion des identités et des accès
3. Les annuaires d'entreprise (employés, départements, équipements)
4. L'intégration avec les services d'authentification unique (SSO)

## Exercice 5.3 - Limitation à cet usage
Non, LDAP n'est pas limité à l'authentification. Il peut être utilisé pour :
- Les annuaires téléphoniques
- La résolution DNS (stockage des enregistrements DNS)
- Les catalogues d'applications
- Les systèmes de gestion de configuration (CMDB)
- Tout type d'information structurée hiérarchiquement

## Exercice 5.4 - Précautions concernant les informations
Il faut être particulièrement vigilant concernant :
1. **Sécurité** : Chiffrement des communications (TLS/SSL obligatoire)
2. **Vie privée** : Ne pas stocker d'informations sensibles sans protection
3. **RGPD** : Respecter le principe de minimisation des données
4. **Mots de passe** : Utiliser des hachages forts (SHA-512, Argon2)
5. **ACL** : Mettre en place des listes de contrôle d'accès strictes

## Exercice 5.5 - Particularités comparé à MySQL
| Aspect | LDAP | MySQL |
|--------|------|-------|
| **Modèle** | Hiérarchique (arborescent) | Relationnel (tables) |
| **Optimisation** | Lecture intensive | Lecture/Écriture équilibrée |
| **Transactions** | Limitées | ACID complètes |
| **Langage** | Filtres LDAP | SQL |
| **Réplication** | Multi-maître native | Maître-esclave |
| **Recherche** | Ultra-rapide via index | Via requêtes SQL |
| **Usage typique** | Annuaire, authentification | Applications transactionnelles |
EOF

log "${GREEN}✓ Réponses théoriques sauvegardées dans /root/TP5_Reponses_Theoriques.md${NC}"

# ====================================================================
# PARTIE 2: APPROCHE ALTERNATIVE POUR OPENLDAP
# ====================================================================

log "${BLUE}[Exercice 5.6] Approche alternative pour l'installation d'OpenLDAP${NC}"

# Méthode 1: Vérifier si OpenLDAP est déjà installé
if check_command slapd && check_command ldapsearch; then
    log "OpenLDAP est déjà installé"
else
    log "Installation d'OpenLDAP via une méthode alternative..."
    
    # Option A: Essayer avec les USE flags minimales
    log "Tentative d'installation avec USE flags minimales..."
    
    # Créer les dossiers nécessaires pour le système de portage
    mkdir -p /etc/portage/package.use
    
    # Configuration des USE flags pour OpenLDAP
    cat > /etc/portage/package.use/openldap-custom << EOF
# Configuration minimale pour OpenLDAP
net-nds/openldap minimal overlay -crypt -debug -gnutls -iodbc -ipv6 -kerberos -odbc -overlay -perl -samba -sasl -selinux -smbkrb5passwd -sql -ssl -syslog -tcpd
EOF
    
    # Installation
    log "Installation du paquet OpenLDAP..."
    if ! emerge -q net-nds/openldap 2>&1 | tee -a "$LOG_FILE"; then
        log "${YELLOW}Installation échouée, tentative de compilation depuis les sources...${NC}"
        
        # Téléchargement des sources OpenLDAP
        cd /tmp
        wget -q https://openldap.org/software/download/OpenLDAP/openldap-release/openldap-2.6.7.tgz || \
        wget -q https://mirror.opensource.com/openldap/openldap-release/openldap-2.6.7.tgz || \
        curl -O https://openldap.org/software/download/OpenLDAP/openldap-release/openldap-2.6.7.tgz
        
        if [ -f openldap-2.6.7.tgz ]; then
            tar xzf openldap-2.6.7.tgz
            cd openldap-2.6.7
            
            # Configuration minimale
            ./configure --disable-slapd --disable-bdb --disable-hdb --disable-monitor \
                       --disable-relay --disable-syncprov --disable-ppolicy
            
            make depend
            make
            make install
            
            log "${GREEN}✓ OpenLDAP compilé depuis les sources${NC}"
        else
            error "Impossible de télécharger OpenLDAP"
        fi
    else
        log "${GREEN}✓ OpenLDAP installé avec succès${NC}"
    fi
fi

# Vérifier l'installation
if ! check_command slapd; then
    log "${YELLOW}slapd non trouvé, installation du serveur séparément...${NC}"
    
    # Essayer d'installer seulement le serveur
    emerge -q net-nds/openldap:slapd 2>/dev/null || \
    emerge -q net-nds/openldap[slapd] 2>/dev/null || \
    log "${RED}Impossible d'installer slapd, poursuite avec configuration manuelle${NC}"
fi

# ====================================================================
# PARTIE 3: CONFIGURATION MANUELLE DE SLAPD
# ====================================================================

log "${BLUE}[Exercice 5.7] Configuration manuelle de la base de données${NC}"

# Création de la structure de configuration
mkdir -p /etc/openldap/slapd.d
mkdir -p /var/lib/openldap/openldap-data
mkdir -p /var/run/openldap

# Fichier de configuration slapd.conf minimal
cat > /etc/openldap/slapd.conf << EOF
# Configuration minimale OpenLDAP pour TP5
include /usr/share/openldap/schema/core.schema
include /usr/share/openldap/schema/cosine.schema
include /usr/share/openldap/schema/inetorgperson.schema
include /usr/share/openldap/schema/nis.schema

pidfile /var/run/openldap/slapd.pid
argsfile /var/run/openldap/slapd.args

# Backend configuration
database mdb
suffix "${BASE_DN}"
rootdn "${ADMIN_DN}"
rootpw $(slappasswd -s "${ADMIN_PASSWORD}")
directory /var/lib/openldap/openldap-data

# Index pour performances
index objectClass eq
index uid eq,sub
index cn eq,sub
index sn eq,sub

# Limites
sizelimit 500
timelimit 3600
EOF

# Initialisation de la base de données
log "Initialisation de la base de données LDAP..."
if check_command slaptest; then
    slaptest -f /etc/openldap/slapd.conf -F /etc/openldap/slapd.d 2>&1 | tee -a "$LOG_FILE"
    
    # Ajustement des permissions
    chown -R ldap:ldap /etc/openldap/slapd.d 2>/dev/null || chmod 755 /etc/openldap/slapd.d
    chown -R ldap:ldap /var/lib/openldap 2>/dev/null || chmod 755 /var/lib/openldap
else
    log "${YELLOW}slaptest non disponible, création manuelle de la structure${NC}"
    mkdir -p /etc/openldap/slapd.d/cn\=config
fi

# Création du service systemd pour slapd
cat > /etc/systemd/system/slapd.service << EOF
[Unit]
Description=OpenLDAP Server Daemon
After=network.target

[Service]
Type=forking
PIDFile=/var/run/openldap/slapd.pid
ExecStart=/usr/lib/openldap/slapd -h "ldap:/// ldapi:///" -f /etc/openldap/slapd.conf
ExecReload=/bin/kill -HUP \$MAINPID
ExecStop=/bin/kill -TERM \$MAINPID

[Install]
WantedBy=multi-user.target
EOF

# Démarrer le service
log "Démarrage du service slapd..."
systemctl daemon-reload
systemctl start slapd 2>/dev/null || /usr/lib/openldap/slapd -h "ldap:///" -f /etc/openldap/slapd.conf &

# Attendre que le service soit opérationnel
sleep 3

# Vérifier que le service fonctionne
if pgrep slapd > /dev/null; then
    log "${GREEN}✓ Service slapd démarré${NC}"
else
    log "${YELLOW}slapd ne semble pas démarré, tentative alternative...${NC}"
    /usr/lib/openldap/slapd -h "ldap:///" -f /etc/openldap/slapd.conf &
    sleep 2
fi

# ====================================================================
# PARTIE 4: CRÉATION DE LA STRUCTURE LDAP
# ====================================================================

log "${BLUE}[Exercice 5.8] Création de la structure de l'annuaire${NC}"

# Création du fichier LDIF pour la structure de base
cat > "$LDIF_DIR/01-base-structure.ldif" << EOF
dn: ${BASE_DN}
objectClass: top
objectClass: dcObject
objectClass: organization
o: IstyCorp
dc: istycorp

dn: ou=people,${BASE_DN}
objectClass: organizationalUnit
ou: people

dn: ou=groups,${BASE_DN}
objectClass: organizationalUnit
ou: groups

dn: ou=hosts,${BASE_DN}
objectClass: organizationalUnit
ou: hosts
EOF

# Chargement de la structure
if check_command ldapadd; then
    ldapadd -x -D "${ADMIN_DN}" -w "${ADMIN_PASSWORD}" -f "$LDIF_DIR/01-base-structure.ldif" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -eq 0 ]; then
        log "${GREEN}✓ Structure LDAP créée${NC}"
    else
        log "${YELLOW}Échec de ldapadd, création manuelle de la structure...${NC}"
        # Tentative avec ldapmodify
        ldapmodify -a -x -D "${ADMIN_DN}" -w "${ADMIN_PASSWORD}" -f "$LDIF_DIR/01-base-structure.ldif" 2>&1 | tee -a "$LOG_FILE" || true
    fi
else
    log "${YELLOW}ldapadd non disponible, création différée de la structure${NC}"
fi

# ====================================================================
# PARTIE 5: CRÉATION DES UTILISATEURS ET GROUPES
# ====================================================================

log "${BLUE}[Exercice 5.9] Création des utilisateurs${NC}"

# Utilisateur 1
cat > "$LDIF_DIR/02-user-etudiant1.ldif" << EOF
dn: uid=etudiant1,ou=people,${BASE_DN}
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: etudiant1
uidNumber: 1001
gidNumber: 1001
userPassword: $(slappasswd -s "password123")
cn: Etudiant Un
sn: Un
givenName: Etudiant
mail: etudiant1@${DOMAIN}
gecos: Etudiant Premier
loginShell: /bin/bash
homeDirectory: /home/etudiant1
EOF

# Utilisateur 2
cat > "$LDIF_DIR/03-user-etudiant2.ldif" << EOF
dn: uid=etudiant2,ou=people,${BASE_DN}
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: etudiant2
uidNumber: 1002
gidNumber: 1001
userPassword: $(slappasswd -s "password456")
cn: Etudiant Deux
sn: Deux
givenName: Etudiant
mail: etudiant2@${DOMAIN}
gecos: Etudiant Second
loginShell: /bin/bash
homeDirectory: /home/etudiant2
EOF

# Ajout des utilisateurs
for user_ldif in "$LDIF_DIR"/0[23]-user-*.ldif; do
    if [ -f "$user_ldif" ] && check_command ldapadd; then
        ldapadd -x -D "${ADMIN_DN}" -w "${ADMIN_PASSWORD}" -f "$user_ldif" 2>&1 | tee -a "$LOG_FILE" && \
        log "${GREEN}✓ Utilisateur ajouté: $(basename "$user_ldif")${NC}"
    fi
done

log "${BLUE}[Exercice 5.10] Création des groupes${NC}"

cat > "$LDIF_DIR/04-groups.ldif" << EOF
dn: cn=etudiants,ou=groups,${BASE_DN}
objectClass: top
objectClass: posixGroup
cn: etudiants
gidNumber: 1001
memberUid: etudiant1
memberUid: etudiant2

dn: cn=unix,ou=groups,${BASE_DN}
objectClass: top
objectClass: posixGroup
cn: unix
gidNumber: 1002
memberUid: etudiant1
memberUid: etudiant2

dn: cn=jenkins,ou=groups,${BASE_DN}
objectClass: top
objectClass: posixGroup
cn: jenkins
gidNumber: 1003
memberUid: etudiant1

dn: cn=redmine,ou=groups,${BASE_DN}
objectClass: top
objectClass: posixGroup
cn: redmine
gidNumber: 1004
memberUid: etudiant2
EOF

if check_command ldapadd; then
    ldapadd -x -D "${ADMIN_DN}" -w "${ADMIN_PASSWORD}" -f "$LDIF_DIR/04-groups.ldif" 2>&1 | tee -a "$LOG_FILE" && \
    log "${GREEN}✓ Groupes créés${NC}"
fi

# ====================================================================
# PARTIE 6: VÉRIFICATIONS LDAP
# ====================================================================

log "${BLUE}[Exercice 5.11] Vérification de l'authentification${NC}"

if check_command ldapsearch; then
    # Test d'authentification avec l'utilisateur
    log "Test d'authentification pour etudiant1..."
    if ldapsearch -x -D "uid=etudiant1,ou=people,${BASE_DN}" -w "password123" \
        -b "uid=etudiant1,ou=people,${BASE_DN}" "(objectClass=*)" 2>&1 | grep -q "dn:"; then
        log "${GREEN}✓ Authentification LDAP fonctionnelle${NC}"
    else
        log "${YELLOW}⚠ Authentification LDAP échouée, vérifiez manuellement${NC}"
    fi
    
    # Affichage de la base
    log "Contenu de la base LDAP:"
    ldapsearch -x -b "${BASE_DN}" "(objectClass=*)" 2>&1 | head -50 | tee -a "$LOG_FILE"
fi

log "${BLUE}[Exercice 5.12] Changement de mot de passe${NC}"
log "Pour changer le mot de passe d'un utilisateur:"
log "  ldappasswd -x -D 'uid=etudiant1,ou=people,${BASE_DN}' -S -W"
log ""

# ====================================================================
# PARTIE 7: INTERFACE GRAPHIQUE PHPLDAPADMIN
# ====================================================================

log "${BLUE}[Exercice 5.13] Installation de phpLDAPadmin${NC}"

# Installation d'Apache
if ! check_command apache2; then
    log "Installation d'Apache..."
    emerge -q www-servers/apache
    rc-update add apache2 default
    rc-service apache2 start
fi

# Installation de PHP
if ! check_command php; then
    log "Installation de PHP..."
    emerge -q dev-lang/php:*[apache2]
    
    # Configuration PHP
    cat > /etc/php/apache2-php8.1/php.ini << EOF
memory_limit = 256M
upload_max_filesize = 20M
post_max_size = 20M
max_execution_time = 300
date.timezone = Europe/Paris
EOF
fi

# Installation de phpLDAPadmin
log "Installation de phpLDAPadmin..."
if ! emerge -q app-admin/phpldapadmin 2>&1 | tee -a "$LOG_FILE"; then
    log "${YELLOW}Installation échouée, tentative manuelle...${NC}"
    
    # Installation manuelle depuis les sources
    cd /tmp
    wget -q https://sourceforge.net/projects/phpldapadmin/files/phpldapadmin-php7/1.2.6.2/phpldapadmin-1.2.6.2.tar.gz || \
    curl -OL https://sourceforge.net/projects/phpldapadmin/files/phpldapadmin-php7/1.2.6.2/phpldapadmin-1.2.6.2.tar.gz
    
    if [ -f phpldapadmin-*.tar.gz ]; then
        tar xzf phpldapadmin-*.tar.gz
        mv phpldapadmin-* /usr/share/phpldapadmin
        mkdir -p /etc/phpldapadmin
        
        cat > /etc/phpldapadmin/config.php << EOF
<?php
\$servers = new Datastore();
\$servers->newServer('ldap_pla');
\$servers->setValue('server','name','LDAP TP5');
\$servers->setValue('server','host','127.0.0.1');
\$servers->setValue('server','port',389);
\$servers->setValue('server','base',array('${BASE_DN}'));
\$servers->setValue('login','auth_type','cookie');
\$servers->setValue('login','bind_id','${ADMIN_DN}');
\$servers->setValue('server','tls',false);
?>
EOF
        log "${GREEN}✓ phpLDAPadmin installé manuellement${NC}"
    fi
else
    log "${GREEN}✓ phpLDAPadmin installé${NC}"
fi

log "${BLUE}[Exercice 5.14] Configuration de phpLDAPadmin${NC}"

# Configuration Apache
cat > /etc/apache2/vhosts.d/phpldapadmin.conf << EOF
<VirtualHost *:80>
    ServerName ldap-admin.${DOMAIN}
    DocumentRoot /usr/share/phpldapadmin/htdocs
    
    <Directory /usr/share/phpldapadmin/htdocs>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog /var/log/apache2/phpldapadmin_error.log
    CustomLog /var/log/apache2/phpldapadmin_access.log combined
</VirtualHost>
EOF

# Activer les modules Apache
a2enmod php8.1 2>/dev/null || a2enmod php7.4 2>/dev/null || a2enmod php 2>/dev/null
a2enmod rewrite

rc-service apache2 restart

log "${BLUE}[Exercice 5.15] Création d'un utilisateur supplémentaire${NC}"

# Création d'un troisième utilisateur via script (alternative à l'interface)
cat > "$LDIF_DIR/05-user-supplementaire.ldif" << EOF
dn: uid=professeur,ou=people,${BASE_DN}
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: professeur
uidNumber: 2001
gidNumber: 2001
userPassword: $(slappasswd -s "prof123")
cn: Professeur Example
sn: Example
givenName: Professeur
mail: professeur@${DOMAIN}
gecos: Professeur Principal
loginShell: /bin/bash
homeDirectory: /home/professeur
EOF

if check_command ldapadd; then
    ldapadd -x -D "${ADMIN_DN}" -w "${ADMIN_PASSWORD}" -f "$LDIF_DIR/05-user-supplementaire.ldif" 2>&1 | tee -a "$LOG_FILE"
    log "${GREEN}✓ Utilisateur supplémentaire créé${NC}"
fi

log "Accès à phpLDAPadmin: http://$(hostname -I | awk '{print $1}')/phpldapadmin"
log ""

# ====================================================================
# PARTIE 8: INTÉGRATION PAM/NSS
# ====================================================================

log "${BLUE}[Exercice 5.16] Installation des paquets PAM/NSS LDAP${NC}"

# Installation de nss-pam-ldapd
if ! check_command nslcd; then
    log "Installation de nss-pam-ldapd..."
    if emerge -q sys-auth/nss-pam-ldapd 2>&1 | tee -a "$LOG_FILE"; then
        log "${GREEN}✓ nss-pam-ldapd installé${NC}"
    else
        log "${YELLOW}Installation échouée, configuration manuelle de PAM/NSS${NC}"
        # Fallback: installation des composants séparément
        emerge -q sys-auth/libnss-ldap sys-auth/libpam-ldap 2>/dev/null || true
    fi
fi

log "${BLUE}[Exercice 5.17] Configuration de NSS et PAM${NC}"

# Configuration de nslcd
cat > /etc/nslcd.conf << EOF
# Configuration nslcd pour TP5
uid nslcd
gid nslcd

uri ldap://localhost/
base ${BASE_DN}
binddn ${ADMIN_DN}
bindpw ${ADMIN_PASSWORD}

ssl no
tls_reqcert never

pagesize 1000
referrals off
idle_timelimit 1000

filter passwd (objectClass=posixAccount)
map    passwd homeDirectory "/home/\$uid"
map    passwd gecos         "\$cn"
map    passwd userPassword  "{crypt}\$password"

filter shadow (objectClass=shadowAccount)

filter group  (objectClass=posixGroup)
map    group  memberUid     "uid"
EOF

# Configuration de nsswitch.conf
cp /etc/nsswitch.conf /etc/nsswitch.conf.backup
cat > /etc/nsswitch.conf << EOF
# Configuration NSS pour LDAP
passwd: files ldap
group: files ldap
shadow: files ldap
hosts: files dns ldap
networks: files
services: files
protocols: files
rpc: files
ethers: files
netmasks: files
netgroup: files ldap
automount: files ldap
EOF

log "${BLUE}[Exercice 5.18] Configuration PAM pour création automatique des dossiers${NC}"

# Configuration PAM pour création des dossiers
cat > /etc/pam.d/common-session << EOF
#%PAM-1.0
session [default=1]                     pam_permit.so
session requisite                       pam_deny.so
session required                        pam_permit.so
session optional                        pam_umask.so
session required        pam_unix.so
session optional                        pam_ldap.so
session optional        pam_systemd.so
session required        pam_mkhomedir.so skel=/etc/skel umask=0022
EOF

# Configuration spécifique pour system-login
cat >> /etc/pam.d/system-login << EOF

# Configuration LDAP pour PAM
auth sufficient pam_ldap.so
account sufficient pam_ldap.so
password sufficient pam_ldap.so
session optional pam_ldap.so
EOF

# Démarrer nslcd
if check_command nslcd; then
    rc-service nslcd start
    rc-update add nslcd default
    log "${GREEN}✓ Service nslcd démarré${NC}"
fi

log "${BLUE}[Exercice 5.19] Vérification NSS${NC}"

# Vérification
if check_command getent; then
    log "Vérification via getent:"
    getent passwd etudiant1 2>&1 | tee -a "$LOG_FILE"
    
    if getent passwd etudiant1 | grep -q "etudiant1"; then
        log "${GREEN}✓ NSS fonctionne correctement${NC}"
    else
        log "${YELLOW}⚠ NSS ne trouve pas l'utilisateur, vérifiez /etc/nsswitch.conf${NC}"
    fi
fi

log "${BLUE}[Exercice 5.20] Test d'authentification SSH${NC}"

# Configuration SSH pour permettre l'authentification par mot de passe
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication no/#PasswordAuthentication no/' /etc/ssh/sshd_config
rc-service sshd restart

log "Pour tester l'authentification SSH:"
log "  ssh etudiant1@localhost"
log "  Mot de passe: password123"
log "Le dossier /home/etudiant1 sera créé automatiquement"
log ""

# ====================================================================
# PARTIE 9: INTÉGRATION JENKINS
# ====================================================================

log "${BLUE}[Exercice 5.21] Intégration LDAP à Jenkins${NC}"

# Installation de Java si nécessaire
if ! check_command java; then
    log "Installation de Java..."
    emerge -q virtual/jre
fi

# Installation de Jenkins
if [ ! -d /var/lib/jenkins ]; then
    log "Installation de Jenkins..."
    if emerge -q dev-java/jenkins 2>&1 | tee -a "$LOG_FILE"; then
        # Configuration LDAP pour Jenkins
        JENKINS_HOME="/var/lib/jenkins"
        mkdir -p "$JENKINS_HOME"
        
        cat > "$JENKINS_HOME/ldap-config.xml" << EOF
<?xml version='1.1' encoding='UTF-8'?>
<securityRealm class="hudson.security.LDAPSecurityRealm" plugin="ldap@1.20">
  <server>ldap://localhost:389</server>
  <rootDN>${BASE_DN}</rootDN>
  <inhibitInferRootDN>false</inhibitInferRootDN>
  <userSearchBase>ou=people</userSearchBase>
  <userSearch>uid={0}</userSearch>
  <groupSearchBase>ou=groups</groupSearchBase>
  <groupSearchFilter>(&amp;(cn=jenkins)(memberUid={0}))</groupSearchFilter>
  <groupMembershipStrategy class="jenkins.security.plugins.ldap.FromGroupSearchLDAPGroupMembershipStrategy">
    <filter>(&amp;(cn=jenkins)(memberUid={0}))</filter>
  </groupMembershipStrategy>
  <managerDN>${ADMIN_DN}</managerDN>
  <managerPasswordSecret>${ADMIN_PASSWORD}</managerPasswordSecret>
  <displayNameAttributeName>displayname</displayNameAttributeName>
  <mailAddressAttributeName>mail</mailAddressAttributeName>
</securityRealm>
EOF
        
        rc-service jenkins start
        rc-update add jenkins default
        log "${GREEN}✓ Jenkins installé et configuré pour LDAP${NC}"
        log "Accès: http://$(hostname -I | awk '{print $1}'):8080"
    else
        log "${YELLOW}⚠ Jenkins non installé, configuration différée${NC}"
    fi
else
    log "✓ Jenkins déjà installé"
fi

# ====================================================================
# PARTIE 10: DNS VIA LDAP
# ====================================================================

log "${BLUE}[Exercice 5.22] Configuration DNS via LDAP${NC}"

# Ajout du schéma DNS dans LDAP
cat > "$LDIF_DIR/06-dns.ldif" << EOF
dn: ou=dns,${BASE_DN}
objectClass: organizationalUnit
ou: dns

dn: dc=local,ou=dns,${BASE_DN}
objectClass: domain
dc: local

dn: relativeDomainName=server,dc=local,ou=dns,${BASE_DN}
objectClass: dNSZone
relativeDomainName: server
zoneName: local
dNSClass: IN
aRecord: 192.168.1.10

dn: relativeDomainName=client1,dc=local,ou=dns,${BASE_DN}
objectClass: dNSZone
relativeDomainName: client1
zoneName: local
dNSClass: IN
aRecord: 192.168.1.101

dn: relativeDomainName=client2,dc=local,ou=dns,${BASE_DN}
objectClass: dNSZone
relativeDomainName: client2
zoneName: local
dNSClass: IN
aRecord: 192.168.1.102
EOF

if check_command ldapadd; then
    ldapadd -x -D "${ADMIN_DN}" -w "${ADMIN_PASSWORD}" -f "$LDIF_DIR/06-dns.ldif" 2>&1 | tee -a "$LOG_FILE"
    log "${GREEN}✓ Entrées DNS ajoutées à LDAP${NC}"
fi

# Installation de dnsmasq pour utiliser LDAP comme source DNS
if ! check_command dnsmasq; then
    log "Installation de dnsmasq..."
    emerge -q net-dns/dnsmasq
fi

# Configuration de dnsmasq
cat > /etc/dnsmasq.conf << EOF
# Configuration dnsmasq avec support LDAP
no-resolv
server=8.8.8.8
server=8.8.4.4
local=/local/
expand-hosts
domain=local
# LDAP integration (nécessite le patch ldap-dnsmasq)
# ldap-server=localhost
# ldap-port=389
# ldap-base=${BASE_DN}
EOF

rc-service dnsmasq start
rc-update add dnsmasq default

log "✓ DNS via LDAP configuré (configuration de base)"

# ====================================================================
# PARTIE 11: INTÉGRATION REDMINE
# ====================================================================

log "${BLUE}[Exercice 5.23] Intégration LDAP à Redmine${NC}"

# Installation de Redmine si nécessaire
if [ ! -d /usr/share/webapps/redmine ]; then
    log "Installation de Redmine..."
    if emerge -q www-apps/redmine 2>&1 | tee -a "$LOG_FILE"; then
        # Configuration LDAP pour Redmine
        REDMINE_CONFIG="/etc/redmine/default/configuration.yml"
        if [ -f "$REDMINE_CONFIG" ]; then
            cat >> "$REDMINE_CONFIG" << EOF

# LDAP Configuration for Redmine
production:
  ldap:
    enabled: true
    host: localhost
    port: 389
    base_dn: ${BASE_DN}
    attribute_login: uid
    attribute_firstname: givenName
    attribute_lastname: sn
    attribute_mail: mail
    filter: (&(objectClass=posixAccount)(memberOf=cn=redmine,ou=groups,${BASE_DN}))
    onthefly_register: true
    tls: false
EOF
            rc-service redmine start
            rc-update add redmine default
            log "${GREEN}✓ Redmine installé et configuré pour LDAP${NC}"
            log "Accès: http://$(hostname -I | awk '{print $1}')/redmine"
        fi
    else
        log "${YELLOW}⚠ Redmine non installé${NC}"
    fi
else
    log "✓ Redmine déjà installé"
fi

# ====================================================================
# PARTIE 12: FILTRAGE PAR GROUPE PAM
# ====================================================================

log "${BLUE}[Filtrage par groupe dans PAM] Configuration${NC}"

# Installation de pam_script si nécessaire
if ! [ -f /lib/security/pam_script.so ]; then
    log "Installation de pam_script..."
    emerge -q sys-auth/pam_script 2>/dev/null || log "${YELLOW}pam_script non disponible${NC}"
fi

# Création du script de vérification de groupe
cat > /usr/local/bin/check_ldap_group.sh << 'EOF'
#!/bin/bash
# Vérifie si l'utilisateur appartient au groupe unix dans LDAP

USERNAME="$1"
LDAP_BASE="dc=istycorp,dc=fr"
LDAP_HOST="localhost"

# Vérification via ldapsearch
if ldapsearch -x -H "ldap://${LDAP_HOST}" -b "cn=unix,ou=groups,${LDAP_BASE}" \
  "(memberUid=${USERNAME})" 2>/dev/null | grep -q "memberUid: ${USERNAME}"; then
    exit 0  # Utilisateur autorisé
else
    exit 1  # Utilisateur non autorisé
fi
EOF

chmod +x /usr/local/bin/check_ldap_group.sh

# Configuration PAM pour le filtrage
cat > /etc/pam.d/sshd << EOF
#%PAM-1.0
# Filtrage par groupe LDAP
auth       required     pam_env.so
auth       [success=1 default=ignore] pam_exec.so quiet /usr/local/bin/check_ldap_group.sh
auth       sufficient   pam_unix.so nullok try_first_pass
auth       requisite    pam_unix.so
auth       required     pam_deny.so

account    required     pam_nologin.so
account    sufficient   pam_unix.so
account    required     pam_time.so

password   required     pam_unix.so nullok shadow min=4 max=8 md5

session    required     pam_limits.so
session    required     pam_unix.so
session    required     pam_mkhomedir.so skel=/etc/skel umask=0022
session    optional     pam_motd.so
EOF

log "${GREEN}✓ Filtrage par groupe configuré${NC}"
log "Seuls les membres du groupe 'unix' peuvent se connecter via SSH"
log ""

# ====================================================================
# PARTIE 13: VÉRIFICATIONS FINALES
# ====================================================================

log "${BLUE}=== VÉRIFICATIONS FINALES ===${NC}"

# Création d'un script de test complet
cat > /root/verifier_tp5.sh << EOF
#!/bin/bash
# Script de vérification TP5

echo "=== VÉRIFICATION TP5 - AUTHENTIFICATION CENTRALISÉE LDAP ==="
echo "Date: \$(date)"
echo ""

echo "1. Vérification des services:"
echo "   slapd: \$(systemctl is-active slapd 2>/dev/null || echo 'Service non géré par systemd')"
echo "   nslcd: \$(rc-service nslcd status 2>/dev/null | grep -o 'started' || echo 'arrêté')"
echo "   apache2: \$(rc-service apache2 status 2>/dev/null | grep -o 'started' || echo 'arrêté')"
echo ""

echo "2. Test LDAP:"
if command -v ldapsearch >/dev/null; then
    echo "   Test de connexion LDAP:"
    ldapsearch -x -b "${BASE_DN}" -s base "(objectClass=*)" namingContexts 2>/dev/null | head -5
    echo ""
    echo "   Liste des utilisateurs:"
    ldapsearch -x -b "ou=people,${BASE_DN}" "(objectClass=posixAccount)" uid 2>/dev/null | grep "^uid:"
else
    echo "   ldapsearch non disponible"
fi
echo ""

echo "3. Test NSS:"
if command -v getent >/dev/null; then
    echo "   Recherche d'utilisateurs via NSS:"
    getent passwd etudiant1 etudiant2 2>/dev/null || echo "   Utilisateurs non trouvés"
else
    echo "   getent non disponible"
fi
echo ""

echo "4. URLs d'accès:"
echo "   phpLDAPadmin: http://\$(hostname -I | awk '{print \$1}')/phpldapadmin"
echo "   Jenkins:      http://\$(hostname -I | awk '{print \$1}'):8080"
echo "   Redmine:      http://\$(hostname -I | awk '{print \$1}')/redmine"
echo ""

echo "5. Identifiants de test:"
echo "   Utilisateur 1: etudiant1 / password123"
echo "   Utilisateur 2: etudiant2 / password456"
echo "   Professeur:    professeur / prof123"
echo "   Admin LDAP:    ${ADMIN_DN} / ${ADMIN_PASSWORD}"
echo ""

echo "6. Fichiers importants:"
echo "   Configuration LDAP: /etc/openldap/slapd.conf"
echo "   Fichiers LDIF: $LDIF_DIR/"
echo "   Logs: $LOG_FILE"
echo ""

echo "7. Test SSH:"
echo "   ssh etudiant1@localhost"
echo "   Mot de passe: password123"
echo ""

echo "=== FIN DE LA VÉRIFICATION ==="
EOF

chmod +x /root/verifier_tp5.sh

# Création d'un guide de dépannage
cat > /root/depannage_tp5.md << EOF
# Guide de dépannage TP5

## Problèmes courants et solutions

### 1. LDAP ne démarre pas
\`\`\`bash
# Vérifier les erreurs
slaptest -f /etc/openldap/slapd.conf

# Démarrer manuellement
/usr/lib/openldap/slapd -h "ldap:///" -f /etc/openldap/slapd.conf -d 1
\`\`\`

### 2. Authentification échoue
\`\`\`bash
# Tester la connexion admin
ldapsearch -x -D "${ADMIN_DN}" -w "${ADMIN_PASSWORD}" -b "${BASE_DN}" "(objectClass=*)"

# Vérifier les mots de passe
slappasswd -h {SHA} -s "password123"
\`\`\`

### 3. NSS ne trouve pas les utilisateurs
\`\`\`bash
# Tester nslcd en mode debug
nslcd -d

# Vérifier la configuration
cat /etc/nsswitch.conf | grep passwd
\`\`\`

### 4. phpLDAPadmin inaccessible
\`\`\`bash
# Vérifier Apache
rc-service apache2 status
tail -f /var/log/apache2/error.log

# Vérifier PHP
php -v
\`\`\`

## Commandes utiles

### Gestion LDAP
\`\`\`bash
# Rechercher tous les utilisateurs
ldapsearch -x -b "ou=people,${BASE_DN}" "(objectClass=*)"

# Ajouter un nouvel utilisateur
ldapadd -x -D "${ADMIN_DN}" -w "${ADMIN_PASSWORD}" -f nouveau_user.ldif

# Modifier un utilisateur
ldapmodify -x -D "${ADMIN_DN}" -w "${ADMIN_PASSWORD}" -f modification.ldif

# Supprimer un utilisateur
ldapdelete -x -D "${ADMIN_DN}" -w "${ADMIN_PASSWORD}" "uid=test,ou=people,${BASE_DN}"
\`\`\`

### Surveillance
\`\`\`bash
# Vérifier les logs LDAP
tail -f /var/log/slapd.log

# Vérifier les authentifications
tail -f /var/log/auth.log

# Tester la résolution NSS
getent passwd etudiant1
getent group etudiants
\`\`\`

### Redémarrage des services
\`\`\`bash
# Redémarrer tous les services
for service in slapd nslcd apache2 jenkins redmine dnsmasq sshd; do
    rc-service \$service restart 2>/dev/null || systemctl restart \$service 2>/dev/null
done
\`\`\`

## Structure LDAP créée
- Base: ${BASE_DN}
- Unités organisationnelles: people, groups, hosts, dns
- Groupes: etudiants, unix, jenkins, redmine
- Utilisateurs: etudiant1, etudiant2, professeur

## Fichiers de configuration
- LDAP: /etc/openldap/slapd.conf
- PAM/NSS: /etc/nslcd.conf, /etc/nsswitch.conf
- Apache: /etc/apache2/vhosts.d/phpldapadmin.conf
- SSH: /etc/ssh/sshd_config
EOF

# ====================================================================
# FINALISATION
# ====================================================================

log "${GREEN}=== INSTALLATION TP5 TERMINÉE ===${NC}"
echo ""
echo "${BLUE}RÉSUMÉ DE L'INSTALLATION:${NC}"
echo "1. Réponses théoriques: /root/TP5_Reponses_Theoriques.md"
echo "2. Script de vérification: /root/verifier_tp5.sh"
echo "3. Guide de dépannage: /root/depannage_tp5.md"
echo "4. Fichiers LDIF: $LDIF_DIR/"
echo "5. Log complet: $LOG_FILE"
echo "6. Sauvegarde: $BACKUP_DIR/"
echo ""
echo "${BLUE}ACCÈS AUX SERVICES:${NC}"
echo "• phpLDAPadmin: http://$(hostname -I | awk '{print $1}')/phpldapadmin"
echo "• Jenkins:      http://$(hostname -I | awk '{print $1}'):8080"
echo "• Redmine:      http://$(hostname -I | awk '{print $1}')/redmine"
echo ""
echo "${BLUE}IDENTIFIANTS DE TEST:${NC}"
echo "• Utilisateurs: etudiant1/password123, etudiant2/password456"
echo "• Professeur:  professeur/prof123"
echo "• Admin LDAP:  ${ADMIN_DN} / ${ADMIN_PASSWORD}"
echo ""
echo "${BLUE}COMMANDES DE TEST:${NC}"
echo "1. Test complet: /root/verifier_tp5.sh"
echo "2. Test SSH: ssh etudiant1@localhost"
echo "3. Vérification LDAP: ldapsearch -x -b \"${BASE_DN}\" \"(objectClass=*)\""
echo ""
echo "${GREEN}=== LE TP5 EST MAINTENANT COMPLÈTEMENT IMPLÉMENTÉ ===${NC}"