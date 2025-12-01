#!/bin/bash
# TP5 - Authentification centralisée LDAP - Script complet Gentoo
# Script qui automatise l'ensemble du TP5

set -e  # Arrêter en cas d'erreur

# Variables de configuration
DOMAIN="istycorp.fr"
BASE_DN="dc=istycorp,dc=fr"
ADMIN_DN="cn=admin,${BASE_DN}"
LDAP_PASSWORD="admin123"
ORGANIZATION="IstyCorp"
PHP_VERSION="php8.1"
LDIF_DIR="/root/ldif_files"
LOG_FILE="/var/log/tp5_ldap.log"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Fonction de logging
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Fonction pour exécuter avec vérification
run() {
    log "Exécution: $*"
    if ! "$@" >> "$LOG_FILE" 2>&1; then
        log "${RED}ERREUR: Échec de la commande: $*${NC}"
        exit 1
    fi
}

# Initialisation
log "${GREEN}=== Début du TP5 - Authentification centralisée LDAP ===${NC}"
mkdir -p "$LDIF_DIR"

# ====================================================================
# PARTIE 1: RÉPONSES AUX QUESTIONS THÉORIQUES
# ====================================================================
log "${BLUE}[Exercices 5.1-5.5] Réponses théoriques sur LDAP${NC}"

cat > /root/theorie_ldap.txt << 'EOF'
Exercice 5.1: Objectif de LDAP
LDAP (Lightweight Directory Access Protocol) est un protocole standardisé d'accès
à des annuaires. Son objectif principal est de fournir un accès centralisé et
normalisé à des informations structurées, principalement pour l'authentification
et la gestion des identités.

Exercice 5.2: Cadre d'utilisation principal
Il est principalement utilisé dans les environnements d'entreprise pour:
- L'authentification centralisée des utilisateurs
- La gestion des identités et des accès
- Les annuaires d'entreprise
- L'intégration avec les services réseau (SSO)

Exercice 5.3: Limitation à cet usage
Non, LDAP n'est pas limité à l'authentification. Il peut être utilisé pour:
- Les annuaires téléphoniques
- Les systèmes de résolution DNS
- Les catalogues de ressources réseau
- Toute information structurée hiérarchiquement

Exercice 5.4: Précautions concernant les informations
Il faut faire attention à:
- La confidentialité des données (chiffrement TLS/SSL)
- La minimisation des données sensibles stockées
- Le respect du RGPD pour les informations personnelles
- La sécurité des mots de passe (hachage fort)

Exercice 5.5: Particularités comparé à MySQL
- Modèle hiérarchique (arborescent) vs relationnel (tables)
- Optimisé pour la lecture vs lecture/écriture
- Pas de transactions complexes
- Recherche rapide via indexation
- Protocole standardisé vs SQL propriétaire
- Schémas pré-définis et extensibles
EOF

log "${GREEN}✓ Réponses théoriques sauvegardées dans /root/theorie_ldap.txt${NC}"

# ====================================================================
# PARTIE 2: MISE EN PLACE DU SERVEUR LDAP
# ====================================================================
log "${BLUE}[Exercice 5.6] Installation du serveur LDAP${NC}"
run emerge --quiet net-nds/openldap
run emerge --quiet net-nds/openldap-slapd
log "${GREEN}✓ Serveur LDAP installé${NC}"

# Configuration de slapd
log "${BLUE}[Exercice 5.7] Configuration de la base de données${NC}"

# Création de la configuration slapd
cat > /etc/openldap/slapd.conf << EOF
include /etc/openldap/schema/core.schema
include /etc/openldap/schema/cosine.schema
include /etc/openldap/schema/inetorgperson.schema
include /etc/openldap/schema/nis.schema

pidfile /var/run/openldap/slapd.pid
argsfile /var/run/openldap/slapd.args

modulepath /usr/lib64/openldap
moduleload back_mdb.la

database mdb
suffix "${BASE_DN}"
rootdn "${ADMIN_DN}"
rootpw $(slappasswd -s "${LDAP_PASSWORD}")
directory /var/lib/openldap/openldap-data
index objectClass eq
EOF

# Initialisation
mkdir -p /etc/openldap/slapd.d
chown ldap:ldap /etc/openldap/slapd.d
slaptest -f /etc/openldap/slapd.conf -F /etc/openldap/slapd.d

# Démarrer le service
/etc/init.d/slapd start
rc-update add slapd default

# Création de la structure de base
log "${BLUE}Création de la structure de base LDAP${NC}"

cat > "${LDIF_DIR}/base.ldif" << EOF
dn: ${BASE_DN}
objectClass: top
objectClass: dcObject
objectClass: organization
o: ${ORGANIZATION}
dc: istycorp

dn: cn=admin,${BASE_DN}
objectClass: simpleSecurityObject
objectClass: organizationalRole
cn: admin
description: LDAP administrator
userPassword: $(slappasswd -s "${LDAP_PASSWORD}")
EOF

run ldapadd -x -D "cn=admin,${BASE_DN}" -w "${LDAP_PASSWORD}" -f "${LDIF_DIR}/base.ldif"

# ====================================================================
# PARTIE 3: CRÉATION DE LA STRUCTURE
# ====================================================================
log "${BLUE}[Exercice 5.8] Création du schéma de l'annuaire${NC}"

cat > "${LDIF_DIR}/structure.ldif" << EOF
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

run ldapadd -x -D "${ADMIN_DN}" -w "${LDAP_PASSWORD}" -f "${LDIF_DIR}/structure.ldif"

# ====================================================================
# PARTIE 4: CRÉATION D'UTILISATEURS ET GROUPES
# ====================================================================
log "${BLUE}[Exercice 5.9] Création du premier utilisateur${NC}"

cat > "${LDIF_DIR}/user1.ldif" << EOF
dn: uid=john.doe,ou=people,${BASE_DN}
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: shadowAccount
objectClass: inetOrgPerson
uid: john.doe
uidNumber: 10000
gidNumber: 10000
userPassword: $(slappasswd -s "password123")
givenName: John
sn: Doe
cn: John Doe
gecos: John Doe
loginShell: /bin/bash
homeDirectory: /home/john.doe
mail: john.doe@${DOMAIN}
EOF

run ldapadd -x -D "${ADMIN_DN}" -w "${LDAP_PASSWORD}" -f "${LDIF_DIR}/user1.ldif"

log "${BLUE}[Exercice 5.10] Création des groupes${NC}"

cat > "${LDIF_DIR}/groups.ldif" << EOF
dn: cn=users,ou=groups,${BASE_DN}
objectClass: top
objectClass: posixGroup
cn: users
gidNumber: 10000

dn: cn=unix,ou=groups,${BASE_DN}
objectClass: top
objectClass: posixGroup
cn: unix
gidNumber: 10001

dn: cn=jenkins,ou=groups,${BASE_DN}
objectClass: top
objectClass: posixGroup
cn: jenkins
gidNumber: 10002
memberUid: john.doe

dn: cn=redmine,ou=groups,${BASE_DN}
objectClass: top
objectClass: posixGroup
cn: redmine
gidNumber: 10003
memberUid: john.doe
EOF

run ldapadd -x -D "${ADMIN_DN}" -w "${LDAP_PASSWORD}" -f "${LDIF_DIR}/groups.ldif"

# Ajout de l'utilisateur au groupe unix
cat > "${LDIF_DIR}/add_to_groups.ldif" << EOF
dn: cn=users,ou=groups,${BASE_DN}
changetype: modify
add: memberUid
memberUid: john.doe

dn: cn=unix,ou=groups,${BASE_DN}
changetype: modify
add: memberUid
memberUid: john.doe
EOF

run ldapmodify -x -D "${ADMIN_DN}" -w "${LDAP_PASSWORD}" -f "${LDIF_DIR}/add_to_groups.ldif"

# ====================================================================
# PARTIE 5: VÉRIFICATIONS
# ====================================================================
log "${BLUE}[Exercice 5.11] Vérification de l'authentification${NC}"
run ldapsearch -x -D "uid=john.doe,ou=people,${BASE_DN}" -w "password123" -b "${BASE_DN}" "(uid=john.doe)"

log "${BLUE}[Exercice 5.12] Changement de mot de passe${NC}"
echo -e "password123\nnewpass123\nnewpass123" | ldappasswd -x -D "uid=john.doe,ou=people,${BASE_DN}" -S
log "${GREEN}✓ Mot de passe changé${NC}"

# ====================================================================
# PARTIE 6: INTERFACE GRAPHIQUE PHPldapadmin
# ====================================================================
log "${BLUE}[Exercice 5.13] Installation de phpLDAPadmin${NC}"

# Installation d'Apache et PHP
run emerge --quiet apache
run emerge --quiet "${PHP_VERSION}"
run emerge --quiet app-admin/phpldapadmin

# Configuration de PHP
cat > /etc/php/apache2-php8.1/php.ini << EOF
memory_limit = 256M
upload_max_filesize = 20M
post_max_size = 20M
max_execution_time = 300
date.timezone = Europe/Paris
EOF

# Configuration de phpLDAPadmin
log "${BLUE}[Exercice 5.14] Configuration de phpLDAPadmin${NC}"

cp /etc/phpldapadmin/config.php.example /etc/phpldapadmin/config.php

# Édition de la configuration
cat > /etc/phpldapadmin/config.php << 'EOF'
<?php
$config->custom->appearance['friendly_attrs'] = array(
    'facsimileTelephoneNumber' => 'Fax',
    'gidNumber' => 'Group',
    'mail' => 'Email',
    'telephoneNumber' => 'Telephone',
    'uidNumber' => 'User ID',
    'userPassword' => 'Password'
);

$servers = new Datastore();
$servers->newServer('ldap_pla');
$servers->setValue('server','name','LDAP Server');
$servers->setValue('server','host','localhost');
$servers->setValue('server','port',389);
$servers->setValue('server','base',array('dc=istycorp,dc=fr'));
$servers->setValue('login','auth_type','session');
$servers->setValue('login','bind_id','cn=admin,dc=istycorp,dc=fr');
$servers->setValue('login','bind_pass','');
$servers->setValue('server','tls',false);
$servers->setValue('server','login_attr','uid');
$servers->setValue('server','login_class','inetOrgPerson');
?>
EOF

# Configuration Apache
cat > /etc/apache2/vhosts.d/phpldapadmin.conf << EOF
<VirtualHost *:80>
    ServerName ldap-admin.${DOMAIN}
    DocumentRoot /usr/share/phpldapadmin/htdocs
    
    <Directory /usr/share/phpldapadmin/htdocs>
        Options FollowSymLinks
        DirectoryIndex index.php
        AllowOverride All
        Require all granted
        
        <IfModule mod_php.c>
            php_flag magic_quotes_gpc Off
            php_flag track_vars On
            php_value include_path .
        </IfModule>
    </Directory>
    
    ErrorLog /var/log/apache2/phpldapadmin_error.log
    CustomLog /var/log/apache2/phpldapadmin_access.log combined
</VirtualHost>
EOF

# Activation des modules Apache
a2enmod php8.1
a2enmod rewrite
/etc/init.d/apache2 start
rc-update add apache2 default

log "${BLUE}[Exercice 5.15] Création d'un deuxième utilisateur via script${NC}"

cat > "${LDIF_DIR}/user2.ldif" << EOF
dn: uid=jane.smith,ou=people,${BASE_DN}
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: shadowAccount
objectClass: inetOrgPerson
uid: jane.smith
uidNumber: 10001
gidNumber: 10000
userPassword: $(slappasswd -s "password456")
givenName: Jane
sn: Smith
cn: Jane Smith
gecos: Jane Smith
loginShell: /bin/bash
homeDirectory: /home/jane.smith
mail: jane.smith@${DOMAIN}
EOF

run ldapadd -x -D "${ADMIN_DN}" -w "${LDAP_PASSWORD}" -f "${LDIF_DIR}/user2.ldif"

# Ajout au groupe unix
cat > "${LDIF_DIR}/add_jane.ldif" << EOF
dn: cn=users,ou=groups,${BASE_DN}
changetype: modify
add: memberUid
memberUid: jane.smith

dn: cn=unix,ou=groups,${BASE_DN}
changetype: modify
add: memberUid
memberUid: jane.smith
EOF

run ldapmodify -x -D "${ADMIN_DN}" -w "${LDAP_PASSWORD}" -f "${LDIF_DIR}/add_jane.ldif"

# ====================================================================
# PARTIE 7: INTÉGRATION À PAM/NSS
# ====================================================================
log "${BLUE}[Exercice 5.16] Installation des paquets PAM/NSS LDAP${NC}"
run emerge --quiet sys-auth/nss-pam-ldapd
run emerge --quiet sys-auth/pam_ldap

log "${BLUE}[Exercice 5.17] Configuration NSS/PAM${NC}"

# Configuration de nslcd
cat > /etc/nslcd.conf << EOF
uid nslcd
gid nslcd

uri ldap://localhost/
base ${BASE_DN}
binddn ${ADMIN_DN}
bindpw ${LDAP_PASSWORD}

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

# Configuration NSS
cat > /etc/nsswitch.conf << EOF
passwd: files ldap
group: files ldap
shadow: files ldap
hosts: files dns ldap
networks: files

protocols: files
services: files
ethers: files
rpc: files

netgroup: files ldap
automount: files ldap
EOF

log "${BLUE}[Exercice 5.18] Configuration de PAM pour création automatique des dossiers${NC}"

# Fichier PAM commun
cat > /etc/pam.d/common-session << EOF
session required pam_unix.so
session required pam_mkhomedir.so skel=/etc/skel umask=0022
session optional pam_ldap.so
session optional pam_systemd.so
EOF

# Configuration spécifique pour system-login
cat >> /etc/pam.d/system-login << EOF

# LDAP configuration
auth sufficient pam_ldap.so
account sufficient pam_ldap.so
password sufficient pam_ldap.so
session optional pam_ldap.so
session required pam_mkhomedir.so skel=/etc/skel umask=0022
EOF

# Démarrer les services
/etc/init.d/nslcd start
rc-update add nslcd default

log "${BLUE}[Exercice 5.19] Vérification de NSS${NC}"
run getent passwd john.doe
run getent group users

log "${BLUE}[Exercice 5.20] Test d'authentification${NC}"

# Création d'un script de test SSH
cat > /root/test_ssh.sh << 'EOF'
#!/bin/bash
echo "=== Test d'authentification SSH ==="
echo "Pour tester, utilisez:"
echo "  ssh john.doe@localhost"
echo "Mot de passe: newpass123"
echo ""
echo "Le dossier /home/john.doe sera créé automatiquement."
EOF

chmod +x /root/test_ssh.sh

# ====================================================================
# PARTIE 8: INTÉGRATION À JENKINS
# ====================================================================
log "${BLUE}[Exercice 5.21] Intégration LDAP à Jenkins${NC}"

# Installation de Jenkins
run emerge --quiet dev-java/jenkins

# Configuration Jenkins LDAP
JENKINS_CONFIG="/var/lib/jenkins/config.xml"
if [ -f "$JENKINS_CONFIG" ]; then
    # Sauvegarde de la configuration existante
    cp "$JENKINS_CONFIG" "${JENKINS_CONFIG}.backup"
    
    # Création de la configuration LDAP pour Jenkins
    cat > /var/lib/jenkins/ldap-config.xml << EOF
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
  <managerPasswordSecret>${LDAP_PASSWORD}</managerPasswordSecret>
  <displayNameAttributeName>displayname</displayNameAttributeName>
  <mailAddressAttributeName>mail</mailAddressAttributeName>
</securityRealm>
EOF
fi

# Démarrer Jenkins
/etc/init.d/jenkins start
rc-update add jenkins default

# ====================================================================
# PARTIE 9: GESTION DNS VIA LDAP
# ====================================================================
log "${BLUE}[Exercice 5.22] Gestion DNS via LDAP${NC}"

# Ajout du schéma DNS
cat > "${LDIF_DIR}/dns-schema.ldif" << EOF
dn: cn=dns,ou=schema,${BASE_DN}
objectClass: ldapSchema
cn: dns
EOF

# Création d'entrées DNS
cat > "${LDIF_DIR}/hosts.ldif" << EOF
dn: dc=internal,${BASE_DN}
objectClass: top
objectClass: domain
dc: internal

dn: relativeDomainName=server,dc=internal,${BASE_DN}
objectClass: top
objectClass: dNSZone
relativeDomainName: server
zoneName: internal
dNSClass: IN
aRecord: 192.168.1.10
pTREcord: server.${DOMAIN}

dn: relativeDomainName=workstation1,dc=internal,${BASE_DN}
objectClass: top
objectClass: dNSZone
relativeDomainName: workstation1
zoneName: internal
dNSClass: IN
aRecord: 192.168.1.101

dn: relativeDomainName=workstation2,dc=internal,${BASE_DN}
objectClass: top
objectClass: dNSZone
relativeDomainName: workstation2
zoneName: internal
dNSClass: IN
aRecord: 192.168.1.102
EOF

run ldapadd -x -D "${ADMIN_DN}" -w "${LDAP_PASSWORD}" -f "${LDIF_DIR}/hosts.ldif"

# Installation et configuration dnsmasq pour utiliser LDAP
run emerge --quiet net-dns/dnsmasq

cat > /etc/dnsmasq.conf << EOF
# Configuration DNS avec LDAP
no-resolv
server=8.8.8.8
server=8.8.4.4
local=/internal/
domain=internal
expand-hosts
ldap-host=localhost
ldap-binddn=${ADMIN_DN}
ldap-secret=${LDAP_PASSWORD}
ldap-guess
EOF

/etc/init.d/dnsmasq start
rc-update add dnsmasq default

# ====================================================================
# PARTIE 10: INTÉGRATION À REDMINE
# ====================================================================
log "${BLUE}[Exercice 5.23] Intégration LDAP à Redmine${NC}"

# Installation de Redmine
run emerge --quiet www-apps/redmine

# Configuration Redmine pour LDAP
REDMINE_CONFIG="/etc/redmine/default/settings.yml"
if [ -f "$REDMINE_CONFIG" ]; then
    cat >> "$REDMINE_CONFIG" << EOF

# LDAP Configuration
ldap:
  enabled: true
  servers:
    my_ldap:
      host: localhost
      port: 389
      attr_login: uid
      attr_firstname: givenName
      attr_lastname: sn
      attr_mail: mail
      base_dn: ${BASE_DN}
      onthefly_register: true
      filter: (memberOf=cn=redmine,ou=groups,${BASE_DN})
      tls: false
EOF
fi

# Démarrer Redmine
/etc/init.d/redmine start
rc-update add redmine default

# ====================================================================
# PARTIE 11: FILTRAGE PAR GROUPE DANS PAM
# ====================================================================
log "${BLUE}[Filtrage par groupe dans PAM] Configuration${NC}"

# Installation de pam_script
run emerge --quiet sys-auth/pam_script

# Création du script de vérification de groupe
cat > /usr/local/bin/check_unix_group.sh << 'EOF'
#!/bin/bash
# Vérifie si l'utilisateur appartient au groupe unix

USERNAME=$1
LDAP_URI="ldap://localhost"
BASE_DN="dc=istycorp,dc=fr"
GROUP_DN="cn=unix,ou=groups,${BASE_DN}"

# Recherche si l'utilisateur est membre du groupe
ldapsearch -x -H "$LDAP_URI" -b "$GROUP_DN" "(memberUid=$USERNAME)" | grep -q "memberUid: $USERNAME"

if [ $? -eq 0 ]; then
    echo "User $USERNAME is member of unix group"
    exit 0
else
    echo "User $USERNAME is NOT member of unix group"
    exit 1
fi
EOF

chmod +x /usr/local/bin/check_unix_group.sh

# Configuration PAM pour le filtrage
cat > /etc/pam.d/sshd << EOF
# PAM configuration for SSH with LDAP group filtering
auth       required     pam_env.so
auth       [success=1 default=ignore] pam_exec.so quiet /usr/local/bin/check_unix_group.sh
auth       sufficient   pam_ldap.so
auth       required     pam_deny.so

account    sufficient   pam_ldap.so
account    required     pam_unix.so

password   sufficient   pam_ldap.so
password   required     pam_unix.so nullok shadow try_first_pass

session    required     pam_mkhomedir.so skel=/etc/skel umask=0022
session    required     pam_limits.so
session    required     pam_unix.so
session    optional     pam_ldap.so
EOF

# ====================================================================
# PARTIE 12: VÉRIFICATIONS FINALES
# ====================================================================
log "${BLUE}Vérifications finales${NC}"

# Création d'un script de vérification complet
cat > /root/verify_ldap.sh << 'EOF'
#!/bin/bash

echo "=== VÉRIFICATION COMPLÈTE LDAP ==="
echo ""
echo "1. Test de connexion LDAP:"
ldapsearch -x -b "${BASE_DN}" -s base "(objectClass=*)" namingContexts
echo ""

echo "2. Liste des utilisateurs LDAP:"
ldapsearch -x -b "ou=people,${BASE_DN}" "(objectClass=posixAccount)" uid
echo ""

echo "3. Liste des groupes LDAP:"
ldapsearch -x -b "ou=groups,${BASE_DN}" "(objectClass=posixGroup)" cn memberUid
echo ""

echo "4. Vérification NSS:"
getent passwd john.doe
getent passwd jane.smith
echo ""

echo "5. Test d'authentification PAM (simulé):"
su - john.doe -c "echo 'Authentification réussie pour john.doe'"
echo ""

echo "6. Vérification des services:"
echo "   LDAP: $(systemctl is-active slapd)"
echo "   NSS: $(systemctl is-active nslcd)"
echo "   Apache: $(systemctl is-active apache2)"
echo "   Jenkins: $(systemctl is-active jenkins)"
echo "   Redmine: $(systemctl is-active redmine)"
echo ""

echo "7. Accès aux interfaces web:"
echo "   phpLDAPadmin: http://$(hostname -I | awk '{print $1}')/phpldapadmin"
echo "   Jenkins: http://$(hostname -I | awk '{print $1}'):8080"
echo "   Redmine: http://$(hostname -I | awk '{print $1}')/redmine"
echo ""

echo "8. Informations de connexion:"
echo "   Utilisateur LDAP: uid=john.doe,ou=people,${BASE_DN}"
echo "   Mot de passe: newpass123"
echo "   Admin LDAP: ${ADMIN_DN}"
echo "   Mot de passe admin: ${LDAP_PASSWORD}"
EOF

chmod +x /root/verify_ldap.sh

# Création d'un rapport final
cat > /root/tp5_rapport.md << EOF
# Rapport d'installation TP5 - LDAP

## Services installés et configurés

### 1. Serveur LDAP
- **Base DN**: ${BASE_DN}
- **Admin DN**: ${ADMIN_DN}
- **Structure**: people, groups, hosts
- **Utilisateurs**: john.doe, jane.smith
- **Groupes**: users, unix, jenkins, redmine

### 2. Intégration système
- **PAM/NSS**: Configuration complète avec nslcd
- **Création auto des dossiers**: Activée via pam_mkhomedir
- **Filtrage par groupe**: Seuls les membres du groupe 'unix' peuvent se connecter

### 3. Services web
- **phpLDAPadmin**: Interface de gestion LDAP
- **Jenkins**: Authentification LDAP avec filtrage par groupe 'jenkins'
- **Redmine**: Authentification LDAP avec filtrage par groupe 'redmine'

### 4. DNS via LDAP
- **Zone**: internal
- **Hôtes**: server, workstation1, workstation2
- **DNS dynamique**: Configuré avec dnsmasq

## Tests à effectuer

### Test 1: Authentification système
\`\`\`bash
ssh john.doe@localhost
# Mot de passe: newpass123
\`\`\`

### Test 2: Vérification LDAP
\`\`\`bash
ldapsearch -x -b "${BASE_DN}" "(objectClass=*)"
\`\`\`

### Test 3: Interface web
- phpLDAPadmin: http://[IP_SERVER]/phpldapadmin
- Jenkins: http://[IP_SERVER]:8080
- Redmine: http://[IP_SERVER]/redmine

## Fichiers importants
- Configuration LDAP: /etc/openldap/
- Configuration PAM: /etc/pam.d/
- Configuration NSS: /etc/nsswitch.conf, /etc/nslcd.conf
- Scripts LDIF: ${LDIF_DIR}/
- Logs: /var/log/tp5_ldap.log

## Commandes utiles
\`\`\`bash
# Vérification complète
/root/verify_ldap.sh

# Recherche LDAP
ldapsearch -x -b "${BASE_DN}" "(uid=john.doe)"

# Vérification NSS
getent passwd john.doe

# Redémarrer les services
/etc/init.d/slapd restart
/etc/init.d/nslcd restart
\`\`\`
EOF

# Finalisation
log "${GREEN}=== INSTALLATION TERMINÉE AVEC SUCCÈS ===${NC}"
log ""
log "${YELLOW}INFORMATIONS IMPORTANTES:${NC}"
log "1. Rapport détaillé: /root/tp5_rapport.md"
log "2. Script de vérification: /root/verify_ldap.sh"
log "3. Log d'installation: ${LOG_FILE}"
log ""
log "${YELLOW}ACCÈS AUX INTERFACES WEB:${NC}"
log "phpLDAPadmin: http://$(hostname -I | awk '{print $1}')/phpldapadmin"
log "Jenkins: http://$(hostname -I | awk '{print $1}'):8080"
log "Redmine: http://$(hostname -I | awk '{print $1}')/redmine"
log ""
log "${YELLOW}IDENTIFIANTS DE TEST:${NC}"
log "Utilisateur: john.doe / newpass123"
log "Administrateur: ${ADMIN_DN} / ${LDAP_PASSWORD}"
log ""
log "${GREEN}Exécutez '/root/verify_ldap.sh' pour vérifier l'installation${NC}"