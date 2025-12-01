#!/bin/bash

# ============================================
# TP 4 - Services SSH/Apache/MySQL/NFS/Tomcat
# Script pour Gentoo avec OpenRC
# ============================================

# Variables
SERVER_IP="192.168.1.100"
MYSQL_ROOT_PASSWORD="SecurePassword123"
WORDPRESS_DB_PASSWORD="WordpressPass123"
PORTAGE_PROFILE="/etc/portage/make.profile"
USE_FLAGS_FILE="/etc/portage/package.use"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Fonctions
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Exécutez en root!"
        exit 1
    fi
}

update_system() {
    print_info "Mise à jour de Portage..."
    emerge --sync
    
    print_info "Mise à jour du système..."
    emerge -avuDN @world
}

# ============================================
# Configuration USE Flags
# ============================================

configure_use_flags() {
    print_info "Configuration des USE flags..."
    
    # Création des répertoires si nécessaire
    mkdir -p /etc/portage/package.use
    mkdir -p /etc/portage/package.accept_keywords
    
    # USE flags globales
    cat >> /etc/portage/make.conf << 'EOF'
# Flags ajoutées par TP4
USE="ssl sslv3 tlsv1 tlsv1_1 tlsv1_2 mysql mysqli nfs nfsv4 nfsv41 server"
EOF
    
    # USE flags par paquet
    cat > /etc/portage/package.use/tp4-services << 'EOF'
# Apache
www-servers/apache apache2_modules_proxy_ajp apache2_modules_proxy_http apache2_modules_ssl
# PHP
dev-lang/php apache2 mysqli mysqlnd pdo soap sockets ssl xml xmlrpc zip
# MySQL
dev-db/mysql server
# Tomcat
www-servers/tomcat webapps
# SSH
net-misc/openssh server
# NFS
net-fs/nfs-utils nfsv4 nfsv41
net-fs/nfs-utils-lib nfsv4 nfsv41
# Java
virtual/jre
virtual/jdk
# Autres
app-admin/fail2ban python
www-apps/wordpress mysql
EOF
    
    # Acceptation des mots-clés si nécessaire
    cat > /etc/portage/package.accept_keywords/tp4-services << 'EOF'
# Accepter ~amd64 pour les paquets nécessaires
www-servers/tomcat
www-apps/jenkins-bin
EOF
}

# ============================================
# Service SSH (Exercices 4.1-4.7)
# ============================================

install_ssh() {
    print_info "Installation d'OpenSSH..."
    emerge -av net-misc/openssh
    
    # Configuration SSH
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    
    print_info "Configuration de SSH..."
    sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    
    # Création utilisateur isty si inexistant
    if ! id "isty" &>/dev/null; then
        print_warning "Création de l'utilisateur 'isty'..."
        useradd -m -G wheel -s /bin/bash isty
        passwd isty
    fi
    
    # Configuration du répertoire .ssh
    mkdir -p /home/isty/.ssh
    chmod 700 /home/isty/.ssh
    chown isty:isty /home/isty/.ssh
    
    print_warning "Ajoutez votre clé publique dans /home/isty/.ssh/authorized_keys"
    print_warning "Commande: ssh-copy-id isty@${SERVER_IP}"
    
    # Installation de fail2ban
    print_info "Installation de fail2ban..."
    emerge -av app-admin/fail2ban
    
    # Configuration fail2ban
    cat > /etc/fail2ban/jail.local << 'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 600
EOF
    
    # Démarrage des services
    print_info "Démarrage des services..."
    rc-update add sshd default
    rc-service sshd start
    
    rc-update add fail2ban default
    rc-service fail2ban start
    
    print_info "SSH installé et configuré"
    print_warning "Testez fail2ban avec: fail2ban-client status sshd"
}

# ============================================
# Apache/PHP/MySQL (Exercices 4.8-4.14)
# ============================================

install_apache_php_mysql() {
    print_info "Installation d'Apache..."
    emerge -av www-servers/apache
    
    print_info "Installation de PHP..."
    emerge -av dev-lang/php
    
    # Configuration PHP pour Apache
    cp /etc/php/apache2-php8.3/php.ini /etc/php/apache2-php8.3/php.ini.backup
    echo "extension=mysqli.so" >> /etc/php/apache2-php8.3/php.ini
    echo "extension=pdo_mysql.so" >> /etc/php/apache2-php8.3/php.ini
    
    print_info "Installation de MySQL/MariaDB..."
    emerge -av dev-db/mysql
    
    # Initialisation MySQL
    print_info "Initialisation de MySQL..."
    mysql_install_db --user=mysql
    
    # Démarrage MySQL
    rc-update add mysql default
    rc-service mysql start
    
    # Sécurisation MySQL
    print_info "Sécurisation de MySQL..."
    mysql_secure_installation << EOF
y
${MYSQL_ROOT_PASSWORD}
${MYSQL_ROOT_PASSWORD}
y
y
y
y
EOF
    
    # Configuration Apache
    print_info "Configuration d'Apache..."
    
    # Activation des modules
    a2enmod proxy
    a2enmod proxy_ajp
    a2enmod proxy_http
    a2enmod ssl
    a2enmod rewrite
    
    # Création répertoire web
    mkdir -p /var/www/localhost/htdocs
    
    # Configuration VirtualHost
    cat > /etc/apache2/vhosts.d/00_default.conf << 'EOF'
<VirtualHost *:80>
    ServerAdmin admin@istycorp.fr
    DocumentRoot "/var/www/localhost/htdocs"
    ServerName server.istycorp.fr
    
    <Directory "/var/www/localhost/htdocs">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog /var/log/apache2/error.log
    CustomLog /var/log/apache2/access.log combined
</VirtualHost>

<VirtualHost *:443>
    ServerAdmin admin@istycorp.fr
    DocumentRoot "/var/www/localhost/htdocs"
    ServerName server.istycorp.fr
    
    SSLEngine on
    SSLCertificateFile /etc/ssl/apache2/server.crt
    SSLCertificateKeyFile /etc/ssl/apache2/server.key
    
    <Directory "/var/www/localhost/htdocs">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog /var/log/apache2/ssl_error.log
    CustomLog /var/log/apache2/ssl_access.log combined
</VirtualHost>
EOF
    
    # Génération certificat SSL auto-signé
    print_info "Génération certificat SSL..."
    mkdir -p /etc/ssl/apache2
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/apache2/server.key \
        -out /etc/ssl/apache2/server.crt \
        -subj "/C=FR/ST=Paris/L=Paris/O=IstyCorp/CN=server.istycorp.fr"
    
    # Démarrage Apache
    rc-update add apache2 default
    rc-service apache2 start
    
    # Test PHP
    cat > /var/www/localhost/htdocs/info.php << 'EOF'
<?php
phpinfo();
?>
EOF
    
    print_info "Apache/PHP/MySQL installés"
    print_info "Test PHP: http://${SERVER_IP}/info.php"
    print_warning "Certificat SSL auto-signé généré - Les navigateurs afficheront un avertissement"
}

# ============================================
# WordPress (Exercice 4.12)
# ============================================

install_wordpress() {
    print_info "Installation de WordPress..."
    
    # Installation via Portage
    emerge -av www-apps/wordpress
    
    # Création base de données
    mysql -u root -p${MYSQL_ROOT_PASSWORD} << EOF
CREATE DATABASE wordpress DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'wordpress'@'localhost' IDENTIFIED BY '${WORDPRESS_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wordpress'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    # Configuration WordPress
    cp /usr/share/webapps/wordpress/wp-config-sample.php /usr/share/webapps/wordpress/wp-config.php
    
    # Mise à jour des credentials
    sed -i "s/database_name_here/wordpress/" /usr/share/webapps/wordpress/wp-config.php
    sed -i "s/username_here/wordpress/" /usr/share/webapps/wordpress/wp-config.php
    sed -i "s/password_here/${WORDPRESS_DB_PASSWORD}/" /usr/share/webapps/wordpress/wp-config.php
    sed -i "s/localhost/localhost/" /usr/share/webapps/wordpress/wp-config.php
    
    # Génération des clés de sécurité
    for i in {1..8}; do
        salt=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=[]{}|;:,.<>?' | fold -w 64 | head -n 1)
        sed -i "0,/put your unique phrase here/s//${salt}/" /usr/share/webapps/wordpress/wp-config.php
    done
    
    # Lien symbolique vers htdocs
    ln -sf /usr/share/webapps/wordpress /var/www/localhost/htdocs/wordpress
    
    # Permissions
    chown -R apache:apache /usr/share/webapps/wordpress
    chmod -R 755 /usr/share/webapps/wordpress
    
    print_info "WordPress installé"
    print_info "Accédez à: http://${SERVER_IP}/wordpress pour terminer l'installation"
}

# ============================================
# Serveur NFS (Exercices 4.15-4.16)
# ============================================

install_nfs() {
    print_info "Installation du serveur NFS..."
    
    emerge -av net-fs/nfs-utils
    
    # Configuration NFS
    cat > /etc/exports << 'EOF'
# Partage des home directories
/home 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
# Partage pour les données
/srv/nfs 192.168.1.0/24(rw,sync,no_subtree_check)
EOF
    
    # Création répertoire partagé
    mkdir -p /srv/nfs
    chmod 777 /srv/nfs
    
    # Démarrage services NFS
    rc-update add nfs default
    rc-update add rpcbind default
    rc-update add nfsmount default
    
    rc-service rpcbind start
    rc-service nfs start
    
    # Export des répertoires
    exportfs -a
    
    print_info "NFS installé et configuré"
    print_warning "Attention sécurité:"
    print_warning "- no_root_squash permet à root client d'accéder aux fichiers"
    print_warning "- Limitez les adresses IP dans /etc/exports"
    print_warning "- Utilisez des listes de contrôle d'accès si nécessaire"
}

# ============================================
# Tomcat et Jenkins (Exercices 4.17-4.19)
# ============================================

install_jenkins() {
    print_info "Installation de Java..."
    emerge -av virtual/jre virtual/jdk
    
    print_info "Installation de Tomcat..."
    emerge -av www-servers/tomcat
    
    # Création répertoire Jenkins
    mkdir -p /var/jenkins
    chown tomcat:tomcat /var/jenkins
    chmod 755 /var/jenkins
    
    # Téléchargement Jenkins
    print_info "Téléchargement de Jenkins..."
    wget -O /var/lib/tomcat-9/webapps/jenkins.war https://get.jenkins.io/war-stable/latest/jenkins.war
    chown tomcat:tomcat /var/lib/tomcat-9/webapps/jenkins.war
    
    # Configuration Tomcat pour AJP
    cat >> /etc/tomcat-9/server.xml << 'EOF'
<!-- Connexeur AJP pour Apache -->
<Connector protocol="AJP/1.3"
           address="::1"
           port="8009"
           redirectPort="8443"
           secretRequired="false" />
EOF
    
    # Configuration Apache comme reverse proxy
    cat > /etc/apache2/vhosts.d/10-jenkins.conf << 'EOF'
<VirtualHost *:80>
    ServerName jenkins.istycorp.fr
    
    ProxyPreserveHost On
    ProxyPass /jenkins http://localhost:8080/jenkins
    ProxyPassReverse /jenkins http://localhost:8080/jenkins
    
    <Location /jenkins>
        Require all granted
    </Location>
    
    ErrorLog /var/log/apache2/jenkins_error.log
    CustomLog /var/log/apache2/jenkins_access.log combined
</VirtualHost>
EOF
    
    # Démarrage Tomcat
    rc-update add tomcat-9 default
    rc-service tomcat-9 start
    
    # Redémarrage Apache
    rc-service apache2 restart
    
    print_info "Jenkins installé"
    print_info "Accès direct: http://${SERVER_IP}:8080/jenkins"
    print_info "Via Apache: http://${SERVER_IP}/jenkins"
    print_warning "Attendez 1-2 minutes pour le déploiement initial de Jenkins"
}

# ============================================
# phpMyAdmin (Exercice 4.11)
# ============================================

install_phpmyadmin() {
    print_info "Installation de phpMyAdmin..."
    emerge -av dev-db/phpmyadmin
    
    # Lien symbolique
    ln -sf /usr/share/phpmyadmin /var/www/localhost/htdocs/phpmyadmin
    
    # Configuration
    cp /etc/phpmyadmin/config.inc.php /etc/phpmyadmin/config.inc.php.backup
    
    # Ajout de la configuration de contrôle d'accès
    cat >> /etc/phpmyadmin/config.inc.php << 'EOF'
// Contrôle d'accès
$cfg['Servers'][$i]['AllowNoPassword'] = false;
$cfg['Servers'][$i]['auth_type'] = 'cookie';
$cfg['Servers'][$i]['host'] = 'localhost';
$cfg['Servers'][$i]['connect_type'] = 'tcp';
$cfg['Servers'][$i]['compress'] = false;
$cfg['Servers'][$i]['extension'] = 'mysqli';
EOF
    
    print_info "phpMyAdmin installé"
    print_info "Accès: http://${SERVER_IP}/phpmyadmin"
    print_warning "Utilisez les identifiants MySQL pour vous connecter"
}

# ============================================
# Génération règles iptables
# ============================================

generate_iptables_rules() {
    print_info "Génération des règles iptables..."
    
    cat > /root/configure_firewall.sh << 'EOF'
#!/bin/bash
# Script de configuration firewall pour le routeur

# Interfaces (à adapter)
WAN="eth0"
LAN="eth1"
SERVER_IP="192.168.1.100"

# Nettoyage des règles existantes
iptables -F
iptables -t nat -F
iptables -X
iptables -t nat -X

# Politiques par défaut
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# NAT pour le réseau interne
iptables -t nat -A POSTROUTING -o ${WAN} -j MASQUERADE

# Redirections de ports vers le serveur
# SSH
iptables -t nat -A PREROUTING -p tcp --dport 22 -i ${WAN} -j DNAT --to ${SERVER_IP}:22
iptables -A FORWARD -p tcp --dport 22 -d ${SERVER_IP} -j ACCEPT

# HTTP
iptables -t nat -A PREROUTING -p tcp --dport 80 -i ${WAN} -j DNAT --to ${SERVER_IP}:80
iptables -A FORWARD -p tcp --dport 80 -d ${SERVER_IP} -j ACCEPT

# HTTPS
iptables -t nat -A PREROUTING -p tcp --dport 443 -i ${WAN} -j DNAT --to ${SERVER_IP}:443
iptables -A FORWARD -p tcp --dport 443 -d ${SERVER_IP} -j ACCEPT

# Jenkins via Apache
iptables -t nat -A PREROUTING -p tcp --dport 8080 -i ${WAN} -j DNAT --to ${SERVER_IP}:8080
iptables -A FORWARD -p tcp --dport 8080 -d ${SERVER_IP} -j ACCEPT

# NFS (si nécessaire depuis l'extérieur)
iptables -t nat -A PREROUTING -p tcp --dport 2049 -i ${WAN} -j DNAT --to ${SERVER_IP}:2049
iptables -A FORWARD -p tcp --dport 2049 -d ${SERVER_IP} -j ACCEPT

# Règles pour le réseau local
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -i ${LAN} -j ACCEPT
iptables -A FORWARD -i ${LAN} -o ${WAN} -j ACCEPT
iptables -A FORWARD -i ${WAN} -o ${LAN} -m state --state ESTABLISHED,RELATED -j ACCEPT

# Sauvegarde des règles
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

print_info "Règles iptables générées dans /root/configure_firewall.sh"
print_warning "Adaptez les interfaces et exécutez sur le routeur"
EOF
    
    chmod +x /root/configure_firewall.sh
    print_info "Script firewall généré: /root/configure_firewall.sh"
}

# ============================================
# Services bonus
# ============================================

install_bonus() {
    print_info "Installation des services bonus..."
    
    # Roundcube
    print_info "Installation de Roundcube..."
    emerge -av mail-client/roundcube
    
    # Configuration Roundcube
    mysql -u root -p${MYSQL_ROOT_PASSWORD} << EOF
CREATE DATABASE roundcube DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'roundcube'@'localhost' IDENTIFIED BY 'RoundcubePass123';
GRANT ALL PRIVILEGES ON roundcube.* TO 'roundcube'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    # Import du schéma
    mysql -u roundcube -pRoundcubePass123 roundcube < /usr/share/webapps/roundcube/SQL/mysql.initial.sql
    
    # Lien symbolique
    ln -sf /usr/share/webapps/roundcube /var/www/localhost/htdocs/roundcube
    
    # Redmine
    print_info "Installation de Redmine..."
    emerge -av www-apps/redmine
    
    # Configuration Redmine
    mysql -u root -p${MYSQL_ROOT_PASSWORD} << EOF
CREATE DATABASE redmine CHARACTER SET utf8mb4;
CREATE USER 'redmine'@'localhost' IDENTIFIED BY 'RedminePass123';
GRANT ALL PRIVILEGES ON redmine.* TO 'redmine'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    # Lien symbolique
    ln -sf /usr/share/webapps/redmine/public /var/www/localhost/htdocs/redmine
    
    print_info "Services bonus installés"
    print_info "- Roundcube: http://${SERVER_IP}/roundcube"
    print_info "- Redmine: http://${SERVER_IP}/redmine"
}

# ============================================
# Menu principal
# ============================================

main_menu() {
    clear
    echo "========================================="
    echo "  TP4 - Services Server (Gentoo/OpenRC)"
    echo "========================================="
    echo
    echo "1. Installation complète (recommandé)"
    echo "2. Configuration USE flags seulement"
    echo "3. Installation SSH + fail2ban"
    echo "4. Installation LAMP (Apache/PHP/MySQL)"
    echo "5. Installation WordPress"
    echo "6. Installation NFS"
    echo "7. Installation Jenkins/Tomcat"
    echo "8. Installation phpMyAdmin"
    echo "9. Générer règles firewall"
    echo "10. Services bonus (Roundcube/Redmine)"
    echo "11. Quitter"
    echo
    read -p "Choix [1-11]: " choice
    
    case $choice in
        1)
            print_warning "Installation complète - Peut prendre plusieurs heures!"
            update_system
            configure_use_flags
            install_ssh
            install_apache_php_mysql
            install_wordpress
            install_phpmyadmin
            install_nfs
            install_jenkins
            generate_iptables_rules
            ;;
        2)
            configure_use_flags
            ;;
        3)
            update_system
            configure_use_flags
            install_ssh
            ;;
        4)
            update_system
            configure_use_flags
            install_apache_php_mysql
            ;;
        5)
            update_system
            install_wordpress
            ;;
        6)
            update_system
            configure_use_flags
            install_nfs
            ;;
        7)
            update_system
            configure_use_flags
            install_jenkins
            ;;
        8)
            update_system
            install_phpmyadmin
            ;;
        9)
            generate_iptables_rules
            ;;
        10)
            update_system
            install_bonus
            ;;
        11)
            print_info "Au revoir!"
            exit 0
            ;;
        *)
            print_error "Choix invalide"
            sleep 2
            main_menu
            ;;
    esac
    
    echo
    print_info "=== RÉSUMÉ DE L'INSTALLATION ==="
    print_info "Services installés:"
    print_info "- SSH: Port 22 (clés uniquement, root désactivé)"
    print_info "- Apache: Ports 80/443 avec SSL auto-signé"
    print_info "- PHP: 8.3 avec extensions MySQL"
    print_info "- MySQL: Root password défini"
    print_info "- WordPress: /wordpress"
    print_info "- phpMyAdmin: /phpmyadmin"
    print_info "- NFS: /home et /srv/nfs partagés"
    print_info "- Jenkins: Port 8080 et via Apache"
    print_info "- Fail2ban: Protection SSH activée"
    echo
    print_warning "ÉTAPES MANUELLES REQUISES:"
    print_warning "1. Ajoutez votre clé SSH dans /home/isty/.ssh/authorized_keys"
    print_warning "2. Configurez le firewall sur le routeur"
    print_warning "3. Terminez l'installation WordPress via le navigateur"
    print_warning "4. Configurez Jenkins via le navigateur"
    echo
    print_info "Logs à surveiller:"
    print_info "- SSH: /var/log/auth.log"
    print_info "- Apache: /var/log/apache2/"
    print_info "- MySQL: /var/log/mysql/"
    print_info "- Fail2ban: /var/log/fail2ban.log"
}

# ============================================
# Point d'entrée
# ============================================

check_root

# Vérification que nous sommes sur Gentoo
if [ ! -f /etc/gentoo-release ] && [ ! -d /etc/portage ]; then
    print_error "Ce script est conçu pour Gentoo!"
    exit 1
fi

main_menu