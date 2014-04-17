#!/usr/bin/env bash

# Config
PROJECTNAME="richardtapecom"

ENVIRONMENT="development" # "development" or "production" # not used just yet
SERVERNAME="$PROJECTNAME.dev" #localhost dev url
DATBASENAME="$PROJECTNAME" # the database name to create
DOCUMENTPUBLICROOT="/vagrant/$PROJECTNAME/public" #where is the public root
HTDOCSPUBLICROOT="/vagrant/$PROJECTNAME/public/htdocs" #where is the htdocs to be served from
DOCUMENTROOT="/vagrant/$PROJECTNAME" #what is the main doc root

ROOTPASSWORD="root"

USER="rich"
USERPASSWORD="rich"

EMAIL="richard@iamfriendly.com"
THEMENAME="incipio-composer"


# update all of the package references before installing anything
echo ">>> Running apt-get update..."
apt-get update --assume-yes



#######################
# Install base packages
#######################

echo ">>> Installing Base Packages"

# unzip, git, grep, vim, tmux, curl, wget
sudo apt-get install -y unzip subversion git-core ack-grep vim tmux curl wget build-essential python-software-properties



################
# Install nginx
################

echo ">>> Installing nginx"

sudo apt-get install -y --force-yes nginx

# Force nginx to start on server up
sudo update-rc.d nginx defaults

# Configure Nginx
cat > /etc/nginx/sites-available/$SERVERNAME << EOF
server {
	root $HTDOCSPUBLICROOT;
	index index.php index.html index.htm;

	# Make site accessible from http://set-ip-address.xip.io
	server_name $SERVERNAME;

	access_log /var/log/nginx/${SERVERNAME}-access.log;
	error_log  /var/log/nginx/${SERVERNAME}-error.log error;

	charset utf-8;

	location / {
		index index.php index.html;
		try_files \$uri \$uri/ /index.php?\$args;
	}

	gzip off;

	# Add trailing slash to */wp-admin requests.
	rewrite /wp-admin$ \$scheme://\$host\$uri/ permanent;

	# this prevents hidden files (beginning with a period) from being served
	location ~ /\. {
		access_log off;
		log_not_found off;
		deny all;
	}

	# Pass uploaded files to wp-includes/ms-files.php.
   rewrite /files/$ /index.php last;

	if (\$uri !~ wp-content/plugins) {
		rewrite /files/(.+)$ /wp-includes/ms-files.php?file=\$1 last;
	}

	# remove need for /wp/
	if (!-e \$request_filename) {
		rewrite ^(/[^/]+)?(/wp-.*) /wp\$2 last;
		rewrite ^(/[^/]+)?(/.*\.php)$ /wp\$2 last;
	}

	location = /favicon.ico { log_not_found off; access_log off; }
	location = /robots.txt  { access_log off; log_not_found off; }

	error_page 404 /index.php;

	# pass the PHP scripts to php5-fpm
	location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        # With php5-fpm:
        fastcgi_pass unix:/var/run/php5-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
	}

	# Deny .htaccess file access
	location ~ /\.ht {
		deny all;
	}
}
EOF


# Adjust nginx config
echo ">>> Adjust nginx config to add upstream php"
sudo sed -i "s|include /etc/nginx/sites-enabled/*;|include /etc/nginx/sites-enabled/*;upstream php {server unix:/var/run/php5-fpm.sock;}|" /etc/nginx/nginx.conf


# Create directory
if [ ! -d $DOCUMENTPUBLICROOT ]; then
	echo ">>> Make document public root folder"
	mkdir -p $DOCUMENTPUBLICROOT
fi

if [ ! -d $HTDOCSPUBLICROOT ]; then
	echo ">>> Make htdocs public root folder"
	mkdir -p $HTDOCSPUBLICROOT
fi

# Enabling virtual hosts
ln -s /etc/nginx/sites-available/$SERVERNAME /etc/nginx/sites-enabled/$SERVERNAME

# Remove default
rm /etc/nginx/sites-enabled/default



###############
# Install MySQL
###############

echo ">>> Installing MySQL"

# Ignore all prompt questions
export DEBIAN_FRONTEND=noninteractive

# Install MySQL without password prompt
# Set username and password to 'root'
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password $ROOTPASSWORD"
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $ROOTPASSWORD"

# Install MySQL Server
sudo apt-get install -y mysql-server

QS1="CREATE USER '$USER'@'localhost' IDENTIFIED BY '$USERPASSWORD';"
QS2="GRANT ALL ON *.* TO '$USER'@'localhost';"
QS3="DROP DATABASE test;DROP USER ''@'localhost';"
QS4="FLUSH PRIVILEGES;"
QSSQL="${QS1}${QS2}${QS3}${QS4}"

sudo mysql -uroot -p$ROOTPASSWORD -e "$QSSQL"



#############
# Install PHP
#############

echo ">>> Installing PHP"

# In FPM mode
sudo apt-get install -y php5-cli php5-fpm php5-mysql php5-pgsql php5-sqlite php5-curl php5-gd php5-gmp php5-mcrypt php5-xdebug php5-memcached php5-imagick php5-intl

echo ">>> Making changes to PHP Config"

# PHP config for nginx modifications
sudo sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php5/fpm/php.ini
sudo sed -i "s|listen = 127.0.0.1:9000|listen = /var/run/php5-fpm.sock|" /etc/php5/fpm/pool.d/www.conf

# Error logs
sudo sed -i "s/log_errors = .*/log_errors = On/" /etc/php5/fpm/php.ini
sudo sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php5/fpm/php.ini
sudo sed -i "s/display_errors = .*/display_errors = On/" /etc/php5/fpm/php.ini
sudo sed -i "s/display_startup_errors = .*/display_startup_errors = On/" /etc/php5/fpm/php.ini
sudo sed -i "s/html_errors = .*/html_errors = On/" /etc/php5/fpm/php.ini

echo ">>> Restarting PHP and nginx"

# Restart PHP and nginx
sudo service php5-fpm restart
sudo service nginx restart



##################
# Install Composer
##################


echo ">>> Installing Composer"
sudo curl -sS https://getcomposer.org/installer | php
sudo chmod +x composer.phar
sudo mv composer.phar /usr/local/bin/composer

COMPOSER_HOME=/usr/local/src/composer composer -q global require --no-update phpunit/phpunit:4.0.*
COMPOSER_HOME=/usr/local/src/composer composer -q global require --no-update phpunit/php-invoker:1.1.*
COMPOSER_HOME=/usr/local/src/composer composer -q global require --no-update mockery/mockery:0.8.*
COMPOSER_HOME=/usr/local/src/composer composer -q global require --no-update d11wtq/boris:v1.0.2
COMPOSER_HOME=/usr/local/src/composer composer -q global config bin-dir /usr/local/bin
COMPOSER_HOME=/usr/local/src/composer composer global update


################
# Install wp-cli
################

echo ">>> Installing wp-cli"

curl -L https://raw.github.com/wp-cli/builds/gh-pages/phar/wp-cli.phar > wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/bin/wp


################################
# Install WordPress via composer
################################

ssh -o "StrictHostKeyChecking no" git@github.com

# First clone our starter repo
echo ">>> Fetching start project"

sudo git clone git://github.com/richardtape/wp-vagrant-composer.git

sudo mv wp-vagrant-composer/composer.json $DOCUMENTROOT
sudo mv wp-vagrant-composer/index.php $HTDOCSPUBLICROOT

cd $DOCUMENTROOT

sudo composer install

Q1="CREATE DATABASE IF NOT EXISTS $DATBASENAME;"
Q2="GRANT ALL ON $DATBASENAME.* TO $USER@localhost IDENTIFIED BY '$USERPASSWORD';"
Q3="FLUSH PRIVILEGES;"
SQL="${Q1}${Q2}${Q3}"

echo ">>> Add WordPress database"
sudo mysql -uroot -p$ROOTPASSWORD -e "$SQL"

echo ">>> Set up WordPress"

cd $DOCUMENTPUBLICROOT
cd htdocs/wp

echo ">>> Creating wp-config file"
wp core config --url="$SERVERNAME"  --dbname="$DATBASENAME" --dbuser="$USER" --dbpass="$USERPASSWORD" --allow-root --extra-php <<PHP
define( 'WP_DEBUG', true );
if ( file_exists( dirname( __FILE__ ) . '/vendor/autoload.php' ) ){
	require_once( dirname( __FILE__ ) . '/vendor/autoload.php' );
}
define( 'WP_CONTENT_DIR', dirname( __FILE__ ) . '/wp-content' );
define( 'WP_CONTENT_URL', 'http://' . \$_SERVER['HTTP_HOST'] . '/wp-content' );
PHP

echo ">>> Move wp-config file to htdocs"
sudo mv wp-config.php $HTDOCSPUBLICROOT

echo ">>> Set up core WordPress install"
wp core install --url="$SERVERNAME"  --title="WordPress" --admin_user="$USER" --admin_password="$USERPASSWORD" --admin_email="$EMAIL" --allow-root

echo ">>> Activate theme"
wp theme activate $THEMENAME --allow-root

echo ">>> Joy of Joys!"