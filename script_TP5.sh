#!/bin/bash
# TP5 - Authentification centralisée LDAP - Script d'installation Gentoo
# Auteur: Script généré pour le TP5
# Note: Certaines parties nécessitent une configuration manuelle

set -e  # Arrêter le script en cas d'erreur

# Variables configurables
DOMAIN="istycorp.fr"
BASE_DN="dc=istycorp,dc=fr"
ADMIN_DN="cn=admin,${BASE_DN}"
LDAP_PASSWORD="admin_password"  # À changer!
LDIF_DIR="/tmp/ldif_files"
PHP_VERSION="php8.1"  # Ajuster selon la version installée

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Début de l'installation LDAP ===${NC}"

# 1. Installation des paquets requis
echo -e "${YELLOW}[Exercice 5.6] Installation des paquets LDAP...${NC}"
emerge -q net-nds/openldap net-nds/openldap-slapd
echo -e "${GREEN}✓ openldap installé${NC}"

# 2. Configuration de slapd
echo -e "${YELLOW}[Exercice 5.7] Configuration de la base de données...${NC}"

# Création du répertoire de configuration
mkdir -p /etc/openldap/slapd.d
chown ldap:ldap /etc/openldap/slapd.d

# Configuration basique de slapd
cat > /etc/openldap/slapd.conf << EOF
include /etc/openldap/schema/core.schema
include /etc/openldap/schema/cosine.schema
include /etc/openldap/schema/inetorgperson.schema
include /etc/openldap/schema/nis.schema

pidfile /var/run/openldap/slapd.pid
argsfile /var/run/openldap/slapd.args

modulepath /usr/lib64/openldap/openldap
moduleload back_mdb.la

database mdb
suffix "${BASE_DN}"
rootdn "${ADMIN_DN}"
rootpw $(slappasswd -s ${LDAP_PASSWORD})
directory /var/lib/openldap/openldap-data
index objectClass eq
EOF

# Initialisation de la base de données
slaptest -f /etc/openldap/slapd.conf -F /etc/openldap/slapd.d
chown -R ldap:ldap /etc/openldap/slapd.d

# Démarrer le service
rc-service slapd start
rc-update add slapd default

# 3. Création de la structure LDAP
echo -e "${YELLOW}[Exercice 5.8] Création de la structure de l'annuaire...${NC}"

mkdir -p ${LDIF_DIR}

# Fichier LDIF pour la structure
cat > ${LDIF_DIR}/structure.ldif << EOF
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
EOF

# Chargement de la structure
ldapadd -x -D "${ADMIN_DN}" -w "${LDAP_PASSWORD}" -f ${LDIF_DIR}/structure.ldif

# 4. Création d'un utilisateur
echo -e "${YELLOW}[Exercice 5.9] Création d'un utilisateur de test...${NC}"

cat > ${LDIF_DIR}/user.ldif << EOF
dn: uid=john.doe,ou=people,${BASE_DN}
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: shadowAccount
uid: john.doe
uidNumber: 10000
gidNumber: 10000
userPassword: $(slappasswd -s "password123")
gecos: John Doe
loginShell: /bin/bash
homeDirectory: /home/john.doe
EOF

ldapadd -x -D "${ADMIN_DN}" -w "${LDAP_PASSWORD}" -f ${LDIF_DIR}/user.ldif

# 5. Création d'un groupe
echo -e "${YELLOW}[Exercice 5.10] Création d'un groupe...${NC}"

cat > ${LDIF_DIR}/group.ldif << EOF
dn: cn=users,ou=groups,${BASE_DN}
objectClass: top
objectClass: posixGroup
cn: users
memberUid: john.doe
gidNumber: 10000
EOF

ldapadd -x -D "${ADMIN_DN}" -w "${LDAP_PASSWORD}" -f ${LDIF_DIR}/group.ldif

# 6. Vérification
echo -e "${YELLOW}[Exercice 5.11] Vérification de l'authentification...${NC}"
ldapsearch -x -D "uid=john.doe,ou=people,${BASE_DN}" -w "password123" \
  -b "uid=john.doe,ou=people,${BASE_DN}"

# 7. Installation de phpLDAPadmin
echo -e "${YELLOW}[Exercice 5.13] Installation de phpLDAPadmin...${NC}"
emerge -q app-admin/phpldapadmin

# Configuration de phpLDAPadmin
echo -e "${YELLOW}[Exercice 5.14] Configuration de phpLDAPadmin...${NC}"
cp /etc/phpldapadmin/config.php.example /etc/phpldapadmin/config.php

# Modification de la configuration
sed -i "s/'base' => '.*'/'base' => '${BASE_DN}'/" /etc/phpldapadmin/config.php
sed -i "s/'bind_id' => '.*'/'bind_id' => '${ADMIN_DN}'/" /etc/phpldapadmin/config.php

# Configuration Apache
cat > /etc/apache2/vhosts.d/phpldapadmin.conf << EOF
<VirtualHost *:80>
    ServerName ldap-admin.${DOMAIN}
    DocumentRoot /usr/share/phpldapadmin/htdocs
    
    <Directory /usr/share/phpldapadmin/htdocs>
        Require all granted
        AllowOverride All
    </Directory>
    
    ErrorLog /var/log/apache2/phpldapadmin_error.log
    CustomLog /var/log/apache2/phpldapadmin_access.log combined
</VirtualHost>
EOF

# Activation des modules Apache
a2enmod rewrite
rc-service apache2 restart

# 8. Intégration PAM/NSS
echo -e "${YELLOW}[Exercice 5.16] Installation de PAM/NSS LDAP...${NC}"
emerge -q sys-auth/nss-pam-ldapd

# Configuration de nslcd
echo -e "${YELLOW}[Exercice 5.17] Configuration de nslcd...${NC}"
cat > /etc/nslcd.conf << EOF
uid nslcd
gid nslcd

uri ldap://localhost/
base ${BASE_DN}
binddn ${ADMIN_DN}
bindpw ${LDAP_PASSWORD}

ssl no
tls_reqcert never

# Mappings pour POSIX
pagesize 1000
referrals off
idle_timelimit 1000

# Filtres
filter passwd (objectClass=posixAccount)
filter shadow (objectClass=shadowAccount)
filter group  (objectClass=posixGroup)

map    passwd homeDirectory "/home/\$uid"
map    passwd gecos         "\$cn"
EOF

# Configuration NSS
echo "passwd: files ldap" > /etc/nsswitch.conf
echo "group: files ldap" >> /etc/nsswitch.conf
echo "shadow: files ldap" >> /etc/nsswitch.conf

# Configuration PAM
echo -e "${YELLOW}[Exercice 5.18] Configuration de PAM...${NC}"
cat >> /etc/pam.d/system-login << EOF
session optional pam_mkhomedir.so skel=/etc/skel umask=0022
EOF

# Démarrer les services
rc-service nslcd start
rc-update add nslcd default

# 9. Vérification NSS
echo -e "${YELLOW}[Exercice 5.19] Vérification de NSS...${NC}"
getent passwd john.doe || echo "Utilisateur non trouvé via NSS"

# 10. Installation des dépendances pour l'intégration services
echo -e "${YELLOW}[Exercice 5.21/5.23] Préparation pour intégration services...${NC}"

# Pour Jenkins
emerge -q dev-java/jenkins
rc-service jenkins start
rc-update add jenkins default

# Pour Redmine (si non déjà installé)
# emerge -q www-apps/redmine

# 11. Configuration DNS (optionnel)
echo -e "${YELLOW}[Exercice 5.22] Configuration DNS via LDAP...${NC}"
cat > ${LDIF_DIR}/dns.ldif << EOF
dn: ou=hosts,${BASE_DN}
objectClass: organizationalUnit
ou: hosts

dn: cn=server,ou=hosts,${BASE_DN}
objectClass: top
objectClass: device
objectClass: ipHost
cn: server
ipHostNumber: 192.168.1.10
EOF

ldapadd -x -D "${ADMIN_DN}" -w "${LDAP_PASSWORD}" -f ${LDIF_DIR}/dns.ldif

# 12. Création d'un script de test
cat > /root/test_ldap.sh << 'EOF'
#!/bin/bash
echo "=== Test d'intégration LDAP ==="
echo "1. Recherche LDAP:"
ldapsearch -x -b "dc=istycorp,dc=fr" "(objectClass=*)"
echo ""
echo "2. Vérification NSS:"
getent passwd | grep john.doe || echo "Utilisateur non trouvé"
echo ""
echo "3. Test d'authentification (changer le mot de passe d'abord):"
echo "   ldappasswd -x -D 'uid=john.doe,ou=people,dc=istycorp,dc=fr' -W -S"
EOF

chmod +x /root/test_ldap.sh

# 13. Instructions finales
echo -e "${GREEN}=== Installation terminée ===${NC}"
echo ""
echo -e "${YELLOW}Prochaines étapes manuelles:${NC}"
echo "1. Modifier le mot de passe admin: ${ADMIN_DN}"
echo "2. Accéder à phpLDAPadmin: http://$(hostname -I | awk '{print $1}')/phpldapadmin"
echo "3. Configurer Jenkins pour utiliser LDAP:"
echo "   - Aller dans 'Manage Jenkins' > 'Configure Global Security'"
echo "   - Activer 'LDAP' et configurer le serveur"
echo "4. Configurer Redmine pour utiliser LDAP:"
echo "   - Administration > LDAP authentication"
echo "5. Pour le filtrage par groupe PAM (Exercice 5.23+):"
echo "   - Voir /etc/security/group.conf et /etc/pam.d/common-auth"
echo ""
echo -e "${GREEN}Script de test disponible: /root/test_ldap.sh${NC}"
echo -e "${GREEN}Fichiers LDIF dans: ${LDIF_DIR}${NC}"

# Nettoyage
rm -rf ${LDIF_DIR}