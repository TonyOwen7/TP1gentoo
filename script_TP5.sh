#!/bin/bash

# TP5 - Authentification centralisée LDAP - Script d'automatisation Gentoo
# À exécuter en tant que root

set -e  # Arrêter en cas d'erreur

echo "=== Début du TP5 - Authentification centralisée LDAP ==="

# Variables de configuration
LDAP_DOMAIN="istycorp.fr"
LDAP_BASE_DN="dc=istycorp,dc=fr"
LDAP_ADMIN_DN="cn=admin,${LDAP_BASE_DN}"
LDAP_USER_PASSWORD="secret"  # À changer en production
LDAP_ADMIN_PASSWORD="adminsecret"  # À changer en production
USER_LOGIN="user1"
USER_UID="1000"
USER_GID="1000"
USER_FULL_NAME="Utilisateur Test"
USER_HOME="/home/${USER_LOGIN}"

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Fonction de vérification des erreurs
check_error() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}Erreur lors de l'exécution de: $1${NC}"
        exit 1
    fi
}

echo "=== Exercice 5.6 - Installation du serveur LDAP ==="
emerge -q net-nds/openldap net-nds/openldap-slapd
check_error "Installation d'OpenLDAP"

rc-update add slapd default
/etc/init.d/slapd start
check_error "Démarrage de slapd"

echo "=== Exercice 5.7 - Configuration de la base de données ==="

# Création du fichier de configuration slapd.ldif
cat > /tmp/slapd.ldif << EOF
dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: ${LDAP_BASE_DN}

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: ${LDAP_ADMIN_DN}

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: $(slappasswd -s ${LDAP_ADMIN_PASSWORD})

dn: cn=config
changetype: modify
add: olcPasswordHash
olcPasswordHash: {SSHA}
EOF

ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/slapd.ldif
check_error "Configuration de la base de données"

# Ajout du module memberof
cat > /tmp/memberof.ldif << EOF
dn: cn=module,cn=config
cn: module
objectClass: olcModuleList
olcModuleLoad: memberof.la
olcModulePath: /usr/lib64/openldap

dn: olcOverlay={0}memberof,olcDatabase={2}hdb,cn=config
objectClass: olcConfig
objectClass: olcMemberOf
objectClass: olcOverlayConfig
objectClass: top
olcOverlay: memberof
olcMemberOfDangling: ignore
olcMemberOfRefInt: TRUE
olcMemberOfGroupOC: groupOfNames
olcMemberOfMemberAD: member
olcMemberOfMemberOfAD: memberOf
EOF

ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/memberof.ldif
check_error "Ajout du module memberof"

# Ajout de la structure de base
cat > /tmp/base.ldif << EOF
dn: ${LDAP_BASE_DN}
objectClass: top
objectClass: dcObject
objectClass: organization
o: ${LDAP_DOMAIN}
dc: istycorp

dn: ${LDAP_ADMIN_DN}
objectClass: simpleSecurityObject
objectClass: organizationalRole
cn: admin
description: LDAP Administrator
userPassword: $(slappasswd -s ${LDAP_ADMIN_PASSWORD})
EOF

ldapadd -x -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PASSWORD}" -f /tmp/base.ldif
check_error "Création de la structure de base"

echo "=== Exercice 5.8 - Création de la structure people et groups ==="

cat > /tmp/structure.ldif << EOF
dn: ou=people,${LDAP_BASE_DN}
objectClass: organizationalUnit
ou: people

dn: ou=groups,${LDAP_BASE_DN}
objectClass: organizationalUnit
ou: groups
EOF

ldapadd -x -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PASSWORD}" -f /tmp/structure.ldif
check_error "Création de la structure people/groups"

echo "=== Exercice 5.9 - Ajout d'un utilisateur ==="

USER_PASSWORD_HASH=$(slappasswd -s ${LDAP_USER_PASSWORD})

cat > /tmp/user.ldif << EOF
dn: uid=${USER_LOGIN},ou=people,${LDAP_BASE_DN}
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: shadowAccount
uid: ${USER_LOGIN}
cn: ${USER_FULL_NAME}
uidNumber: ${USER_UID}
gidNumber: ${USER_GID}
homeDirectory: ${USER_HOME}
loginShell: /bin/bash
gecos: ${USER_FULL_NAME}
userPassword: ${USER_PASSWORD_HASH}
shadowLastChange: 0
shadowMax: 0
shadowWarning: 0
EOF

ldapadd -x -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PASSWORD}" -f /tmp/user.ldif
check_error "Ajout de l'utilisateur"

echo "=== Exercice 5.10 - Ajout d'un groupe ==="

cat > /tmp/group.ldif << EOF
dn: cn=users,ou=groups,${LDAP_BASE_DN}
objectClass: top
objectClass: posixGroup
cn: users
gidNumber: ${USER_GID}
memberUid: ${USER_LOGIN}
EOF

ldapadd -x -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PASSWORD}" -f /tmp/group.ldif
check_error "Ajout du groupe"

echo "=== Exercice 5.11 - Vérification de l'authentification ==="
ldapsearch -x -D "uid=${USER_LOGIN},ou=people,${LDAP_BASE_DN}" -w "${LDAP_USER_PASSWORD}" -b "uid=${USER_LOGIN},ou=people,${LDAP_BASE_DN}"
check_error "Vérification de l'authentification"

echo "=== Exercice 5.13 - Installation de phpLDAPadmin ==="
emerge -q app-admin/phpldapadmin
check_error "Installation de phpLDAPadmin"

# Configuration de phpLDAPadmin
cat > /etc/phpldapadmin/config.php << EOF
<?php
\$servers = new Datastore();
\$servers->newServer('ldap_pla');
\$servers->setValue('server','name','LDAP Server');
\$servers->setValue('server','host','127.0.0.1');
\$servers->setValue('server','port',389);
\$servers->setValue('server','base',array('${LDAP_BASE_DN}'));
\$servers->setValue('login','auth_type','session');
\$servers->setValue('login','bind_id','${LDAP_ADMIN_DN}');
\$servers->setValue('server','tls',false);
\$servers->setValue('server','login_class','person');
\$servers->setValue('auto_number','min',array('uidNumber'=>10000,'gidNumber'=>10000));
?>
EOF

# Configuration d'Apache pour phpLDAPadmin
cat > /etc/apache2/vhosts.d/phpldapadmin.conf << EOF
<VirtualHost *:80>
    ServerName ldap.${LDAP_DOMAIN}
    DocumentRoot /usr/share/phpldapadmin/htdocs
    
    <Directory /usr/share/phpldapadmin/htdocs>
        Require all granted
        AllowOverride All
    </Directory>
    
    ErrorLog /var/log/apache2/phpldapadmin_error.log
    CustomLog /var/log/apache2/phpldapadmin_access.log combined
</VirtualHost>
EOF

rc-service apache2 restart

echo "=== Exercice 5.16 - Installation des paquets PAM/NSS LDAP ==="
emerge -q sys-auth/nss-pam-ldapd sys-auth/pam_ldap
check_error "Installation de nss-pam-ldapd et pam_ldap"

echo "=== Exercice 5.17 - Configuration de PAM/NSS ==="

# Configuration de nslcd
cat > /etc/nslcd.conf << EOF
uid nslcd
gid nslcd

uri ldap://127.0.0.1/
base ${LDAP_BASE_DN}
binddn ${LDAP_ADMIN_DN}
bindpw ${LDAP_ADMIN_PASSWORD}

ssl no
tls_cacertdir /etc/ssl/certs

map passwd homeDirectory "/home/\$uid"
map passwd loginShell "/bin/bash"

scope sub
EOF

# Configuration de nsswitch
sed -i 's/^passwd:.*/passwd: files ldap/g' /etc/nsswitch.conf
sed -i 's/^group:.*/group: files ldap/g' /etc/nsswitch.conf
sed -i 's/^shadow:.*/shadow: files ldap/g' /etc/nsswitch.conf

rc-service nslcd start
rc-update add nslcd default

echo "=== Exercice 5.18 - Configuration de PAM pour création auto des home ==="

# Installation du module PAM nécessaire
emerge -q sys-auth/pambase

# Configuration de common-session
cat >> /etc/pam.d/system-login << EOF
session optional pam_mkhomedir.so skel=/etc/skel umask=0022
EOF

echo "=== Exercice 5.19 - Vérification avec getent ==="
getent passwd ${USER_LOGIN}

echo "=== Exercice 5.20 - Vérification de l'authentification SSH ==="

# Configuration SSH pour utiliser PAM
sed -i 's/^#UsePAM yes/UsePAM yes/g' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/g' /etc/ssh/sshd_config
rc-service sshd restart

echo "=== Exercice 5.21 - Intégration Jenkins (manuel) ==="
echo "Pour Jenkins, allez dans:"
echo "1. Gestion Jenkins > Configuration de la sécurité"
echo "2. Activer 'Security Realm' > 'LDAP'"
echo "3. Configurer:"
echo "   Serveur: ldap://localhost:389"
echo "   root DN: ${LDAP_BASE_DN}"
echo "   User search base: ou=people"
echo "   Group search base: ou=groups"

echo "=== Exercice 5.22 - Gestion DNS via LDAP ==="

# Installation du schéma DNS LDAP
emerge -q net-nds/openldap-servers-schema

cat > /tmp/dns.ldif << EOF
dn: ou=hosts,${LDAP_BASE_DN}
objectClass: organizationalUnit
ou: hosts
EOF

ldapadd -x -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PASSWORD}" -f /tmp/dns.ldif

echo "=== Exercice 5.23 - Intégration Redmine (manuel) ==="
echo "Pour Redmine, installez le plugin 'redmine_ldap_sync':"
echo "1. Dans Administration > Plugins"
echo "2. Configurer LDAP dans Administration > LDAP authentication"
echo "3. Ajouter un nouveau serveur LDAP avec les paramètres:"
echo "   Host: localhost"
echo "   Port: 389"
echo "   Base DN: ${LDAP_BASE_DN}"
echo "   Login attribute: uid"

echo "=== Nettoyage ==="
rm -f /tmp/*.ldif

echo -e "${GREEN}=== Installation LDAP terminée avec succès! ===${NC}"
echo ""
echo "Informations importantes:"
echo "1. URL phpLDAPadmin: http://ldap.istycorp.fr"
echo "2. Admin DN: ${LDAP_ADMIN_DN}"
echo "3. Mot de passe admin: ${LDAP_ADMIN_PASSWORD}"
echo "4. Utilisateur test: ${USER_LOGIN}"
echo "5. Mot de passe utilisateur: ${LDAP_USER_PASSWORD}"
echo ""
echo "Pensez à changer les mots de passe en production!"