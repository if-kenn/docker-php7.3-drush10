FROM alpine:3.10
MAINTAINER IF Fulcrum "fulcrum@ifsight.net"

ENV BUILDDATE 202101070402

ADD healthcheck.sh /healthcheck.sh

RUN STARTTIME=$(date "+%s")                                                                    && \
ALPINE_VER=3.10                                                                                && \
PHPV0=7                                                                                        && \
PHPV1=3                                                                                        && \
echo "################## [$(date)] Setup PHP $PHPV0.$PHPV1 Preflight vars ##################"  && \
PHPCHGURL=https://www.php.net/ChangeLog-$PHPV0.php                                             && \
PGKDIR=/home/abuild/packages                                                                   && \
PKGS1="ctype|curl|dom|fpm|ftp|gd|gettext|imap|iconv|json|ldap|mbstring"                        && \
PKGS2="mcrypt|memcached|mysqlnd|mysqli|opcache|openssl|pdo|pdo_mysql|pdo_pgsql"                && \
PKGS3="pgsql|redis|simplexml|soap|sockets|tokenizer|xml|xmlreader|xmlwriter|xdebug|zip"        && \
PKGS="$PKGS1|$PKGS2|$PKGS3"                                                                    && \
BLACKFURL=https://blackfire.io/api/v1/releases/probe/php/alpine/amd64/$PHPV0$PHPV1             && \
NEW_RELIC_URL=https://download.newrelic.com/php_agent/release                                  && \
echo "################## [$(date)] Add Curl ##################"                                && \
apk add --no-cache curl                                                                        && \
echo "################## [$(date)] Get PHP $PHPV0.$PHPV1 point upgrade ##################"     && \
PHPV2=$(curl -s $PHPCHGURL|grep -Eo "$PHPV0\.$PHPV1\.\d+"|cut -d\. -f3|sort -n|tail -1)        && \
PHPVER=$PHPV0.$PHPV1.$PHPV2                                                                    && \
echo "################## [$(date)] PHP Version $PHPVER ##################"                     && \
echo "################## [$(date)] Add Packages ##################"                            && \
apk update --no-cache && apk upgrade --no-cache                                                && \
apk add --no-cache curl-dev fcgi mysql-client postfix                                          && \
apk add --no-cache --repository http://dl-cdn.alpinelinux.org/alpine/edge/community gnu-libiconv && \
apk add --no-cache --virtual gen-deps alpine-sdk autoconf binutils libbz2 libpcre16 libpcre32     \
  libpcrecpp m4 pcre-dev pcre2 pcre2-dev perl                                                  && \
echo "################## [$(date)] Setup PHP $PHPVER build environment ##################"     && \
adduser -D abuild -G abuild -s /bin/sh                                                         && \
mkdir -p /var/cache/distfiles                                                                  && \
chmod a+w /var/cache/distfiles                                                                 && \
echo "abuild ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/abuild                                  && \
su - abuild -c "git clone -v --depth 1 --single-branch --branch $ALPINE_VER-stable https://github.com/alpinelinux/aports.git aports"                 && \
su - abuild -c "cd aports && git checkout $ALPINE_VER-stable"                                  && \
su - abuild -c "cd aports && git pull"                                                         && \
su - abuild -c "cd aports/community/php$PHPV0 && abuild -r deps"                               && \
su - abuild -c "git config --global user.name \"IF Fulcrum\""                                  && \
su - abuild -c "git config --global user.email \"fulcrum@ifsight.net\""                        && \
su - abuild -c "echo ''|abuild-keygen -a -i"                                                   && \
echo&&\
echo&&\
echo "################## [$(date)] Use Alpine's bump command (ignore failed error) #######"    && \
su - abuild -c "cd aports/community/php$PHPV0 && abump -k php$PHPV0-$PHPVER || :"              && \
echo "################## [$(date)] Install initial and dev PHP packages ##################"    && \
apk add --allow-untrusted $(find $PGKDIR|egrep "php$PHPV0-((common|session)-)?$PHPV0")         && \
apk add --allow-untrusted --no-cache --virtual php-deps                                           \
  $(find $PGKDIR|egrep "php$PHPV0-(dev|phar)-$PHPV0")                                          && \
#apk add --no-cache --repository http://dl-cdn.alpinelinux.org/alpine/edge/community php7-pecl-igbinary
echo "################## [$(date)] Build ancillary PHP packages ##################"            && \
su - abuild -c "cd aports/community/php$PHPV0-pecl-igbinary  && abuild checksum && abuild -r"  && \
su - abuild -c "cd aports/community/php$PHPV0-pecl-mcrypt    && abuild checksum && abuild -r"  && \
su - abuild -c "cd aports/community/php$PHPV0-pecl-memcached && abuild checksum && abuild -r"  && \
su - abuild -c "cd aports/community/php$PHPV0-pecl-redis     && abuild checksum && abuild -r"  && \
su - abuild -c "cd aports/community/php$PHPV0-pecl-xdebug    && abuild checksum && abuild -r"  && \
echo "################## [$(date)] Install PHP packages ##################"                    && \
apk add --allow-untrusted $(find $PGKDIR|egrep "php$PHPV0-(pecl-)?($PKGS)-.*.apk")             && \
echo "################## [$(date)] Setup Fulcrum Env ##################"                       && \
adduser -h /var/www/html -s /sbin/nologin -D -H -u 1971 php                                    && \
chown -R postfix  /var/spool/postfix                                                           && \
chgrp -R postdrop /var/spool/postfix/public /var/spool/postfix/maildrop                        && \
chown -R root     /var/spool/postfix/pid                                                       && \
chown    root     /var/spool/postfix                                                           && \
echo smtputf8_enable = no >> /etc/postfix/main.cf                                              && \
echo "################## [$(date)] Install Blackfire ##################"                       && \
curl -A "Docker" -o /blackfire-probe.tar.gz -D - -L -s $BLACKFURL                              && \
tar zxpf /blackfire-probe.tar.gz -C /                                                          && \
mv /blackfire-*.so $(php -r "echo ini_get('extension_dir');")/blackfire.so                     && \
printf "extension=blackfire.so\nblackfire.agent_socket=tcp://blackfire:8707\n"                  | \
    tee /etc/php$PHPV0/conf.d/90-blackfire.ini                                                 && \
echo "################## [$(date)] Install New Relic ##################"                       && \
NEW_RELIC_FILE=$(curl --silent $NEW_RELIC_URL/ |grep musl|cut -f2 -d\"|cut -f4 -d\/)           && \
curl --silent $NEW_RELIC_URL/$NEW_RELIC_FILE | tar zxvf - -C /tmp                              && \
export NR_INSTALL_USE_CP_NOT_LN=1                                                              && \
export NR_INSTALL_SILENT=1                                                                     && \
/tmp/newrelic-php5-*/newrelic-install install                                                  && \
rm -rf /tmp/newrelic-php5-* /tmp/nrinstall* /etc/php7/conf.d/newrelic.ini                      && \
echo "Removing newrelic.ini so it is not used by default, should be mounted"                   && \
echo "################## [$(date)] Install Composer ##################"                        && \
cd /usr/local                                                                                  && \
curl -sS https://getcomposer.org/installer|php                                                 && \
/bin/mv composer.phar bin/composer                                                             && \
echo "################## [$(date)] Install Drush ##################"                           && \
deluser php                                                                                    && \
adduser -h /phphome -s /bin/sh -D -H -u 1971 php                                               && \
mkdir -p /usr/share/drush/commands /phphome drush10                                            && \
chown php.php /phphome drush10                                                                 && \
su - php -c "cd /usr/local/drush10 && composer require                                            \
  'drush/drush:10.*' 'composer/semver:^1.0' 'pear/archive_tar:^1.4.9' 'psr/log:^1.0'              \
  'symfony/console:~2.7|^3' 'symfony/debug:~2.8|~3.0' 'symfony/event-dispatcher:~2.7|^3'          \
  'symfony/filesystem:^2.7 || ^3.4' 'symfony/finder:~2.7|^3' 'symfony/http-foundation:~3.4.35'    \
  'symfony/process:~2.7|^3' 'symfony/var-dumper:~2.7|^3' 'symfony/yaml:~2.3|^3'                   \
  'twig/twig:^1.38.2'"                                                                         && \
ln -s /usr/local/drush10/vendor/drush/drush/drush /usr/local/bin/drush                         && \


echo "################## [$(date)] Reset php user for fulcrum ##################"              && \
deluser php                                                                                    && \
adduser -h /var/www/html -s /bin/sh -D -H -u 1971 php                                          && \
echo "################## [$(date)] Clean up container/put on a diet ##################"        && \
find /bin /lib /sbin /usr/bin /usr/lib /usr/sbin -type f -exec strip -v {} \;                  && \
apk del php-deps gen-deps                                                                      && \
deluser --remove-home abuild                                                                   && \
cd /usr/bin                                                                                    && \
rm -vrf /blackfire* /var/cache/apk/* /var/cache/distfiles/* /phphome /usr/local/bin/composer      \
    mysql_waitpid mysqlimport mysqlshow mysqladmin mysqlcheck mysqldump myisam_ftdump          && \
echo "################## [$(date)] Done ##################"                                    && \
echo "################## Elapsed: $(expr $(date "+%s") - $STARTTIME) seconds ##################"

USER php

ENV COLUMNS 100
ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so php-fpm7

HEALTHCHECK --interval=30s --timeout=60s --retries=3 CMD /healthcheck.sh

WORKDIR /var/www/html

ENTRYPOINT ["/usr/sbin/php-fpm7"]

CMD ["--nodaemonize"]
