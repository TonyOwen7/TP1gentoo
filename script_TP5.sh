#!/bin/bash

# TP5 - Authentification centralisée LDAP - Script Gentoo corrigé
# À exécuter en tant que root

set -e

echo "=== Installation LDAP sur Gentoo ==="

# Variables
LDAP_DOMAIN="istycorp.fr"
LDAP_BASE_DN="dc=istycorp,dc=fr"
LDAP_ADMIN_DN="cn=admin,${LDAP_BASE_DN}"
LDAP_ADMIN_PASSWORD="adminsecret"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

check_error() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}Erreur: $1${NC}"
        exit 1
    fi
}

echo "=== Étape 1: Configuration des USE flags pour OpenLDAP ==="

# Ajouter les USE flags nécessaires
cat >> /etc/portage/package.use/openldap << EOF
# OpenLDAP avec serveur slapd
net-nds/openldap minimal server perl syslog ssl tcpd cleartext -crypt -iodbc -overlays
# Pour phpLDAPadmin
dev-php/* apache2 mysqli pdo session simplexml xml xmlrpc
EOF

# Mettre à jour le monde
echo "Mise à jour des paquets..."
emerge --update --deep --newuse @world
check_error "Mise à jour du système"

echo "=== Étape 2: Installation d'OpenLDAP ==="

# Installation avec les bonnes options
echo "net-nds/openldap server" >> /etc/portage/package.use
emerge -q net-nds/openldap
check_error "Installation d'OpenLDAP"

# Activer le serveur slapd au démarrage
rc-update add slapd default

echo "=== Étape 3: Configuration d'OpenLDAP ==="

# Arrêter le service pour configuration
/etc/init.d/slapd stop 2>/dev/null || true

# Créer le répertoire de configuration s'il n'existe pas
mkdir -p /etc/openldap/slapd.d

# Créer la configuration de base
cat > /etc/openldap/slapd.conf << EOF
# Configuration de base pour slapd
include /etc/openldap/schema/core.schema
include /etc/openldap/schema/cosine.schema
include /etc/openldap/schema/nis.schema
include /etc/openldap/schema/inetorgperson.schema

pidfile /var/run/openldap/slapd.pid
argsfile /var/run/openldap/slapd.args

modulepath /usr/lib64/openldap
moduleload back_mdb.so

database mdb
suffix "${LDAP_BASE_DN}"
rootdn "${LDAP_ADMIN_DN}"
rootpw $(slappasswd -s "${LDAP_ADMIN_PASSWORD}")

directory /var/lib/openldap-data
maxsize 1073741824

index objectClass eq
index uid eq,sub
index cn eq,sub
index sn eq,sub
index mail eq,sub
EOF

# Créer le répertoire de données
mkdir -p /var/lib/openldap-data
chown ldap:ldap /var/lib/openldap-data
chmod 700 /var/lib/openldap-data

# Vérifier la configuration
slaptest -f /etc/openldap/slapd.conf -F /etc/openldap/slapd.d/
check_error "Test de configuration slapd"

# Démarrer le service
/etc/init.d/slapd start
sleep 3
check_error "Démarrage de slapd"

echo "=== Étape 4: Ajout de la structure de base ==="

# Créer le fichier LDIF pour la structure
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
userPassword: $(slappasswd -s "${LDAP_ADMIN_PASSWORD}")
EOF

# Ajouter la structure
ldapadd -x -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PASSWORD}" -f /tmp/base.ldif
check_error "Ajout de la structure de base"

echo "=== Étape 5: Ajout des unités organisationnelles ==="

cat > /tmp/ou.ldif << EOF
dn: ou=people,${LDAP_BASE_DN}
objectClass: organizationalUnit
ou: people

dn: ou=groups,${LDAP_BASE_DN}
objectClass: organizationalUnit
ou: groups
EOF

ldapadd -x -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PASSWORD}" -f /tmp/ou.ldif
check_error "Création des OU"

echo "=== Étape 6: Installation des outils LDAP ==="
emerge -q net-nds/openldap-client
check_error "Installation des outils client"

echo "=== Étape 7: Installation de nss-pam-ldapd ==="

# Configuration des USE flags pour nss-pam-ldapd
echo "sys-auth/nss-pam-ldapd sasl" >> /etc/portage/package.use
emerge -q sys-auth/nss-pam-ldapd
check_error "Installation de nss-pam-ldapd"

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

# Démarrer nslcd
rc-service nslcd start
rc-update add nslcd default

echo "=== Étape 8: Configuration de nsswitch ==="
sed -i 's/^passwd:.*/passwd: files ldap/g' /etc/nsswitch.conf
sed -i 's/^group:.*/group: files ldap/g' /etc/nsswitch.conf
sed -i 's/^shadow:.*/shadow: files ldap/g' /etc/nsswitch.conf

echo "=== Étape 9: Installation de phpLDAPadmin ==="

# Installation d'Apache et PHP d'abord
emerge -q www-servers/apache dev-lang/php
rc-update add apache2 default
/etc/init.d/apache2 start

# Installation de phpLDAPadmin
echo "dev-php/phpldapadmin apache2" >> /etc/portage/package.use
emerge -q dev-php/phpldapadmin
check_error "Installation de phpLDAPadmin"

# Configuration de phpLDAPadmin
cp /usr/share/phpldapadmin/config/config.php.example /etc/phpldapadmin/config.php

# Modifier la configuration
sed -i "s/\$servers->setValue('server','host','127.0.0.1');/\$servers->setValue('server','host','127.0.0.1');/" /etc/phpldapadmin/config.php
sed -i "s/\$servers->setValue('server','base',array(''));/\$servers->setValue('server','base',array('${LDAP_BASE_DN}'));/" /etc/phpldapadmin/config.php
sed -i "s/\$servers->setValue('login','bind_id','');/\$servers->setValue('login','bind_id','${LDAP_ADMIN_DN}');/" /etc/phpldapadmin/config.php

# Configuration Apache
cat > /etc/apache2/vhosts.d/phpldapadmin.conf << EOF
<VirtualHost *:80>
    ServerName ldap.localhost
    DocumentRoot /usr/share/phpldapadmin/htdocs
    
    <Directory /usr/share/phpldapadmin/htdocs>
        Require all granted
        AllowOverride All
    </Directory>
    
    ErrorLog /var/log/apache2/phpldapadmin_error.log
    CustomLog /var/log/apache2/phpldapadmin_access.log combined
</VirtualHost>
EOF

# Redémarrer Apache
rc-service apache2 restart

echo "=== Étape 10: Création d'un utilisateur test ==="

USER_PASSWORD="test123"
USER_PASSWORD_HASH=$(slappasswd -s "${USER_PASSWORD}")

cat > /tmp/testuser.ldif << EOF
dn: uid=testuser,ou=people,${LDAP_BASE_DN}
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: shadowAccount
uid: testuser
cn: Utilisateur Test
uidNumber: 1000
gidNumber: 1000
homeDirectory: /home/testuser
loginShell: /bin/bash
gecos: Utilisateur Test
userPassword: ${USER_PASSWORD_HASH}
EOF

ldapadd -x -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PASSWORD}" -f /tmp/testuser.ldif
check_error "Création de l'utilisateur test"

echo "=== Étape 11: Création d'un groupe test ==="

cat > /tmp/testgroup.ldif << EOF
dn: cn=users,ou=groups,${LDAP_BASE_DN}
objectClass: top
objectClass: posixGroup
cn: users
gidNumber: 1000
memberUid: testuser
EOF

ldapadd -x -D "${LDAP_ADMIN_DN}" -w "${LDAP_ADMIN_PASSWORD}" -f /tmp/testgroup.ldif
check_error "Création du groupe test"

echo "=== Étape 12: Test de la connexion ==="

# Test avec recherche
echo "Test de recherche LDAP:"
ldapsearch -x -b "${LDAP_BASE_DN}" "(objectclass=*)"

# Test d'authentification
echo -e "\nTest d'authentification de l'utilisateur:"
ldapwhoami -x -D "uid=testuser,ou=people,${LDAP_BASE_DN}" -w "${USER_PASSWORD}"

echo "=== Étape 13: Configuration PAM pour création automatique des home ==="

# Installation de pam_mkhomedir
emerge -q sys-auth/pambase

# Ajouter la ligne dans system-login
if ! grep -q "pam_mkhomedir" /etc/pam.d/system-login; then
    sed -i '/^session.*pam_limits.so/a session    optional   pam_mkhomedir.so skel=/etc/skel umask=0022' /etc/pam.d/system-login
fi

echo "=== Nettoyage ==="
rm -f /tmp/*.ldif

echo -e "${GREEN}=== Installation terminée avec succès! ===${NC}"
echo ""
echo "Informations importantes:"
echo "1. Serveur LDAP: localhost:389"
echo "2. Admin DN: ${LDAP_ADMIN_DN}"
echo "3. Mot de passe admin: ${LDAP_ADMIN_PASSWORD}"
echo "4. Utilisateur test: uid=testuser,ou=people,${LDAP_BASE_DN}"
echo "5. Mot de passe utilisateur: ${USER_PASSWORD}"
echo "6. phpLDAPadmin: http://localhost/phpldapadmin"
echo ""
echo "Commandes utiles:"
echo "- Arrêter LDAP: /etc/init.d/slapd stop"
echo "- Démarrer LDAP: /etc/init.d/slapd start"
echo "- Vérifier utilisateur: getent passwd testuser"
echo "- Recherche LDAP: ldapsearch -x -b '${LDAP_BASE_DN}'"