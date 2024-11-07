#!/usr/bin/env bash

set -e
set -u
set -o pipefail


###
### Globals
###

# The following global variables are available by our Dockerfile itself:
#   MY_USER
#   MY_GROUP
#   MY_UID
#   MY_GID

# Path to scripts to source
CONFIG_DIR="/docker-entrypoint.d"

# php.ini directory
PHP_INI_DIR="/usr/local/etc/php"

# php-fpm conf.d directory
PHP_FPM_DIR="/usr/local/etc/php-fpm.d"

# This file holds error and access log definitions
PHP_FPM_CONF_LOGFILE="${PHP_FPM_DIR}/zzz-entrypoint-logfiles.conf"
PHP_INI_CONF_LOGFILE="${PHP_INI_DIR}/conf.d/zzz-entrypoint-logfiles.ini"

# PHP-FPM log dir
FPM_LOG_DIR="/var/log/php"

# This is the log file for any mail related functions
PHP_MAIL_LOG="${FPM_LOG_DIR}/mail.log"

# Custom ini dir (to be copied to actual ini dir)
PHP_CUST_INI_DIR="/etc/php-custom.d"

# Custom PHP-FPM dir (to be copied to actual FPM conf dir)
PHP_CUST_FPM_DIR="/etc/php-fpm-custom.d"


###
### Source libs
###
init="$( find "${CONFIG_DIR}" -name '*.sh' -type f | sort -u )"
for f in ${init}; do
	# shellcheck disable=SC1090
	. "${f}"
done



#############################################################
## Entry Point
#############################################################

###
### Set Debug level
###
DEBUG_LEVEL="$( env_get "DEBUG_ENTRYPOINT" "0" )"
log "info" "Debug level: ${DEBUG_LEVEL}" "${DEBUG_LEVEL}"


###
### Change uid/gid
###
set_uid "NEW_UID" "${MY_USER}"  "/home/${MY_USER}" "${DEBUG_LEVEL}"
set_gid "NEW_GID" "${MY_GROUP}" "/home/${MY_USER}" "${DEBUG_LEVEL}"


###
### Set timezone
###
set_timezone "TIMEZONE" "${PHP_INI_DIR}/conf.d" "${DEBUG_LEVEL}"


###
### PHP-FPM 5.2 and PHP-FPM 5.3 Env variables fix
###
if php -v 2>/dev/null | grep -Eoq '^PHP[[:space:]]5\.(2|3)'; then
	set_env_php_fpm "/usr/local/etc/php-fpm.d/env.conf"
fi


###
### Set Logging
###
set_docker_logs \
	"DOCKER_LOGS" \
	"${FPM_LOG_DIR}" \
	"${PHP_FPM_CONF_LOGFILE}" \
	"${PHP_INI_CONF_LOGFILE}" \
	"${MY_USER}" \
	"${MY_GROUP}" \
	"${DEBUG_LEVEL}"


###
### Setup postfix
###
if is_docker_logs_enabled "DOCKER_LOGS" >/dev/null; then
	# PHP mail function should log to stderr
	set_postfix "ENABLE_MAIL" "${MY_USER}" "${MY_GROUP}" "${PHP_INI_DIR}/conf.d" "/proc/self/fd/2" "1" "${DEBUG_LEVEL}"
else
	# PHP mail function should log to file
	set_postfix "ENABLE_MAIL" "${MY_USER}" "${MY_GROUP}" "${PHP_INI_DIR}/conf.d" "${PHP_MAIL_LOG}" "0" "${DEBUG_LEVEL}"
fi


###
### Copy custom *.ini files
###
copy_ini_files "${PHP_CUST_INI_DIR}" "${PHP_INI_DIR}/conf.d" "${DEBUG_LEVEL}"


###
### Copy custom PHP-FPM *.conf files
###
copy_fpm_files "${PHP_CUST_FPM_DIR}" "${PHP_FPM_DIR}" "${DEBUG_LEVEL}"


###
### Enable PHP Modules
###
enable_modules "ENABLE_MODULES" "${DEBUG_LEVEL}"


###
### Disable PHP Modules
###
disable_modules "DISABLE_MODULES" "${DEBUG_LEVEL}"


###
### Run custom user supplied scripts
###
execute_custom_scripts "/startup.1.d" "${DEBUG_LEVEL}"
execute_custom_scripts "/startup.2.d" "${DEBUG_LEVEL}"


###
### Startup
###
log "info" "Starting $( php-fpm -v 2>&1 | head -1 )" "${DEBUG_LEVEL}"
exec "${@}"
