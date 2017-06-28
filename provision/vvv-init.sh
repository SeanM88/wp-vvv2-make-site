#!/usr/bin/env bash
# Provision WordPress Stable

# 1. - Collect our config options from vvv-custom.yml
DOMAIN=$(get_primary_host "${VVV_SITE_NAME}.dev")
DOMAINS=$(get_hosts "${DOMAIN}")
SITE_REPO=$(get_config_value 'site_repo' false)
SITE_TITLE=$(get_config_value 'site_title' "${VVV_SITE_NAME}")
DOC_ROOT_DIR=$(get_config_value 'doc_root_dir' 'public_html')
DOC_ROOT_DIR="${DOC_ROOT_DIR//\/}"
DOC_ROOT="${VVV_PATH_TO_SITE}/${DOC_ROOT_DIR}"
DB_NAME=$(get_config_value 'db_name' "${VVV_SITE_NAME}_db")
DB_NAME=${DB_NAME//[\\\/\.\<\>\:\"\'\|\?\!\*-]/}
# Place a sql database dump file in a
DB_FILE=$(get_config_value 'db_file' "${DOC_ROOT}/db-dumps/${DB_NAME}.sql")
#DB_BACKUPS="/srv/database/backups"
IMG_PROXY=$(get_config_value 'img_proxy' false)
WP_VERSION=$(get_config_value 'wp_version' 'latest')
WP_TYPE=$(get_config_value 'wp_type' 'single')
SITE_PROVISION="${VVV_PATH_TO_SITE}/provision"

# 2. - Make a database, if we don't already have one
echo -e "\nCreating database '${DB_NAME}' (if it's not already there)"
mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME}"
mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO wp@localhost IDENTIFIED BY 'wp';"
echo -e "\n DB operations done.\n\n"

# 3. - Nginx Logs
mkdir -p ${VVV_PATH_TO_SITE}/log
touch ${VVV_PATH_TO_SITE}/log/error.log
touch ${VVV_PATH_TO_SITE}/log/access.log

# 4. - Setup our site's doc_root directory (/public_html/) with optional site repo import
if [[ false = "${SITE_REPO}" ]]; then
  # 4.1 - If we're not using the site_repo option don't bother looking for one
  if [[ ! -d "${DOC_ROOT}" ]]; then
    mkdir -p "${DOC_ROOT}"
    mkdir "${DOC_ROOT}/db-dumps"
  fi
else
  # 4.2 - If we don't have existing local repo, clone it into DOC_ROOT (/public_html)
  if [[ ! -d "${DOC_ROOT}/.git" ]]; then
    # Delete any existing DOC_ROOT directory so we can clone repo into it
    echo -e "\nRemoving '${DOC_ROOT}' and its contents"
    rm -rf "${DOC_ROOT}"
    # Clone site_repo into new DOC_ROOT directory
    echo -e "\nCloning '${SITE_REPO}' into fresh '${DOC_ROOT}'"
    #git clone ${SITE_REPO} ${DOC_ROOT}
    # No try/catch in bash but close enough
    (git clone "${SITE_REPO}" "${DOC_ROOT}" && echo "Successfully imported '${SITE_REPO}'") || echo 'ERROR: Could not clone target URL, check site_repo setting in vvv-custom.yml for any mistakes.'
    # If we have a sql dump file, copy it to the /database/backups directory for import
    #if [[ -f "${DB_FILE}" ]]; then
    #  cp "${DB_FILE}" "${DB_BACKUPS}/${DB_NAME}.sql"
    #fi
  fi
fi

# 5. - Download latest stable version of WordPress (if we don't already have it)
if [[ ! -f "${DOC_ROOT}/wp-load.php" ]]; then
    echo "Downloading WordPress..."
	noroot wp core download --version="${WP_VERSION}"
fi
# 6. - Create and setup our site's wp-config.php file if we don't have it
if [[ ! -f "${DOC_ROOT}/wp-config.php" ]]; then
  echo "Configuring WordPress Stable..."
  noroot wp core config --dbname="${DB_NAME}" --dbuser=wp --dbpass=wp --quiet --extra-php <<PHP
define( 'WP_DEBUG', true );
PHP
fi
# 7. - Install WordPress if necessary
if ! $(noroot wp core is-installed); then
  echo "Installing WordPress Stable..."
  # 7.1 - Setup subdomain or multisite type install if selected
  if [ "${WP_TYPE}" = "subdomain" ]; then
    INSTALL_COMMAND="multisite-install --subdomains"
  elif [ "${WP_TYPE}" = "subdirectory" ]; then
    INSTALL_COMMAND="multisite-install"
  else
    INSTALL_COMMAND="install"
  fi
  # 7.2 - Run actual WordPress install command with WP-CLI
  noroot wp core ${INSTALL_COMMAND} --url="${DOMAIN}" --quiet --title="${SITE_TITLE}" --admin_name=admin --admin_email="admin@local.dev" --admin_password="password"

  # 7.3 - Database import - if we have provided a sql dump file, try to import it into database
  if [[ -f "${DB_FILE}" ]]; then

    # 7.3.1 - If we're importing a DB, drop any existing and import new one in place

    # -- Using WP-CLI commands --
    echo -e "\nRemoving '${DB_NAME}' (if it exists) and recreating it empty for DB import"
    noroot wp db reset --yes
    echo -e "\nImporting '${DB_FILE}' into ${DB_NAME}"
    noroot wp db import "${DB_FILE}"
    echo -e "\nReplacing all references to '${VVV_SITE_NAME}.com' with '${DOMAIN}' if possible"
    noroot wp search-replace "${VVV_SITE_NAME}.com" "${DOMAIN}"
    
    # -- Using bash mysql commands (to do)--
    #echo -e "\nRemoving '${DB_NAME}' (if it exists) and recreating it empty for DB import"
    #mysql -u root --password=root -e "DROP DATABASE IF EXISTS ${DB_NAME}"
    #mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME}"
    #echo -e "\nImporting '${DB_FILE}' into ${DB_NAME}"
    #mysql -u root --password=root -e "${DB_NAME} < ${DB_FILE}"

    echo -e "\n DB operations done.\n\n"
  fi

else
  # 7.4 - If we already have WordPress installed, just see if update is needed.
  echo "Updating WordPress Stable..."
  cd ${DOC_ROOT}
  noroot wp core update --version="${WP_VERSION}"
fi

# 8. - if 'img_proxy' option is set in vvv-custom.yml, add handler to vvv-nginx.conf
if [[ false != "${IMG_PROXY}" ]]; then
  cp -f "${SITE_PROVISION}/vvv-nginx.conf.img-proxy.tmpl" "${SITE_PROVISION}/vvv-nginx.conf"
  sed -i "s#{{DOMAINS_HERE}}#${DOMAINS}#" "${SITE_PROVISION}/vvv-nginx.conf"
  # Strip IMG_PROXY url to only domain (no http:// or trailing slash)
  IMG_PROXY=${IMG_PROXY#*//}
  IMG_PROXY=${IMG_PROXY%%/*}
  echo -e "\nSetting up live site: '${IMG_PROXY}' as image proxy for local dev site."
  # add config handler for live site's domain
  sed -i "s#{{LIVE_URL}}#${IMG_PROXY}#" "${SITE_PROVISION}/vvv-nginx.conf"
else
  cp -f "${SITE_PROVISION}/vvv-nginx.conf.tmpl" "${SITE_PROVISION}/vvv-nginx.conf"
  sed -i "s#{{DOMAINS_HERE}}#${DOMAINS}#" "${SITE_PROVISION}/vvv-nginx.conf"
fi
