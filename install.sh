#!/usr/bin/sh

redmine_ver="3.2.0"
wwwroot="/var/www/html"

verbose_flg=0
redminedir="redmine"
uname="root"
upass=""
password=""

while getopts D:p:P:u:v OPT
do
    case $OPT in
        D) redminedir=$OPTARG
           ;;
        p) upass=$OPTARG
           ;;
        P) password=$OPTARG
           ;;
        u) uname=$OPTARG
           ;;
        v) verbose_flg=1
           ;;
    esac
done

vecho()
{
    if [ $verbose_flg -eq 1 ]
    then
        echo $1
    fi
    return 0
}

vecho "Download Redmine..."
wget "http://www.redmine.org/releases/redmine-${redmine_ver}.tar.gz" -O "${wwwroot}/redmine.tar.gz"


if [ $? -eq 0 ]
then
    vecho "Redmine is downloaded."
    vecho "Expand downloaded tar.gz..."
    if [ $verbose_flg -eq 1 ]
    then
        tar zxvf "${wwwroot}/redmine.tar.gz" -C "${wwwroot}"
    else
        tar zxf "${wwwroot}/redmine.tar.gz" -C "${wwwroot}"
    fi
fi

if [ $? -eq 0 ]
then
    vecho "Expand is successfully done."
    vecho "Rename redmine directory..."
    mv ${wwwroot}/redmine-${redmine_ver}/ ${wwwroot}/${redminedir}/
fi

if [ $? -eq 0 ]
then
    vecho "Renamed."
    vecho "Create database..."
    mysql -u root --password="${password}" -e "create database if not exists redmine_${uname} character set utf8;"
    if [ $? -eq 0 ]
    then
        mysql -u root --password="${password}" -e "grant all on redmine_${uname}.* to '${uname}'@'localhost' identified by '${upass}';"
    fi
fi

if [ $? -eq 0 ]
then
    vecho "Database creation is done."
    vecho "Config redmine database..."
    vecho "Change directory into redmine..."
    cd redmine
    cat <<EOF > config/database.yml
production:
  adapter: mysql2
  database: redmine_${uname}
  host: localhost
  usernae: ${uname}
EOF
    if [ $upass != "" ]
    then
        cat password: ${upass} >> config/database.yml
    fi
    cat <<EOF >> config/database.yml
  encoding: utf8
EOF
    state=$?
fi

if [ $state -eq 0 ]
then
    vecho "Configuration is done."
    vecho "Install bundler from gem..."
    gem install bundler
    state=$?
fi

if [ $state -eq 0 ]
then
    vecho "Bundler is successfully installed."
    vecho "Resolve dependency with bundler..."
    bundle install --without development test postgresql sqlite
    state=$?
fi

if [ $state -eq 0 ]
then
    vecho "Dependency resolved."
    vecho "Generate session-store secret key..."
    rake generate_secret_token
    state=$?
fi

if [ $state -eq 0 ]
then
    vecho "Key is generated."
    vecho "Create table..."
    RAILS_ENV=production rake db:migrate
    state=$?
fi

if [ $state -eq 0 ]
then
    vecho "Table is created."
    vecho "Sign in Default data..."
    RAILS_ENV=production rake redmine:load_default_data
    expect -re "Select language:"
    send "ja\n"
    state=$?
fi

if [ $state -eq 0 ]
then
    vecho "Default data is loaded."
    chown -R ${uname}:${uname} files log tmp public/plugin_assets
    state=$?
    if [ $state -eq 0 ]
    then
        chmod -R 755 files log tmp public/plugin_assets
        state=$?
    fi
fi

if [ $state -eq 0 ]
then
    vecho "Redmine Installation is done."
    vecho "Install Passenger..."
    gem install passenger --no-rdoc --no-ri
    passenger-install-apache2-module --auto
    state=$?
fi

if [ $state -eq 0 ]
then
    vecho "Passenger installation is done."
    vecho "Setting apache..."
    cat <<EOF > /etc/httpd/conf.d/redmine.conf
<Directory "/var/www/http/redmine/public">
Require all granted
</Directory>
EOF
    passenger-install-apache2-module --snippet >> /etc/httpd/conf.d/redmine.conf
fi

if [ $state -eq 0 ]
then
    vecho "Apache setting is done."
    chown -R apache:apache /etc/www/http/redmine
    ln -s /var/etc/www/http/redmine/public /ver/www/html/redmine
    cat "RackBaseURI /redmine" >> /etc/httpd/conf.d/redmine.conf
    service httpd configtest
    state=$?
fi

if [ $state -eq 0 ]
then
    service httpd graceful
fi
