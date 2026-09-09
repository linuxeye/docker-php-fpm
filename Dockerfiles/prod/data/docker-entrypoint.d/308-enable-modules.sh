#!/usr/bin/env bash

set -e
set -u
set -o pipefail


############################################################
# Functions
############################################################

###
### Enable PHP Modules
###

enable_modules() {
	local mod_varname="$1"
	local debug="$2"
	local cfg_path="/usr/local/etc/php/conf.d"
	local mod_path="${PHP_EXTENSION_DIR:-$(php-config --extension-dir 2>/dev/null || php -i | grep ^extension_dir | awk -F '=>' '{print $2}' | xargs)}"

	if ! env_set "${mod_varname}"; then
		log "info" "\$${mod_varname} not set. Not enabling any PHP modules." "${debug}"
		return 0
	fi

	local mods
	mods="$(env_get "${mod_varname}")"
	if [ -z "${mods}" ]; then
		log "info" "\$${mod_varname} set, but empty. Not enabling any PHP modules." "${debug}"
		return 0
	fi

	log "info" "Enabling the following PHP modules: ${mods}" "${debug}"

	IFS=',' read -r -a mod_array <<< "${mods}"
	for mod in "${mod_array[@]}"; do
		mod="${mod#"${mod%%[![:space:]]*}"}"
		mod="${mod%"${mod##*[![:space:]]}"}"
		{
			if [ -f "${mod_path}/${mod}.so" ]; then
				run "docker-php-ext-enable ${mod} || true" "${debug}"
				log "info" "Enabled PHP module: ${mod}" "${debug}"
			else
				log "warn" "PHP module '${mod}' not found at ${mod_path}" "${debug}"
			fi
		} &
	done

	wait
	log "info" "All PHP modules processed." "${debug}"
}
