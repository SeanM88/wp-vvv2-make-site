#!/usr/bin/env bash
# Provision WordPress Stable

# Collect our config options from vvv-custom.yml
DOMAIN=$(get_primary_host "${VVV_SITE_NAME}.dev")
DOMAINS=$(get_hosts "${DOMAIN}")
SITE_REPO=$(get_config_value 'site_repo' false)
SITE_TITLE=$(get_config_value 'site_title' "${VVV_SITE_NAME}")
DB_NAME=$(get_config_value 'db_name' "${VVV_SITE_NAME}_db")
DB_NAME=${DB_NAME//[\\\/\.\<\>\:\"\'\|\?\!\*-]/}
# Place a sql database dump file in a
DB_FILE="${DOC_ROOT}/db-dumps/${DB_NAME}.sql"
DB_BACKUPS="/srv/database/backups"
IMG_PROXY=$(get_config_value 'img_proxy' false)
WP_VERSION=$(get_config_value 'wp_version' 'latest')
WP_TYPE=$(get_config_value 'wp_type' 'single')
DOC_ROOT="${VVV_PATH_TO_SITE}/public_html"
SITE_PROVISION="${VVV_PATH_TO_SITE}/provision"

# Make a database, if we don't already have one
echo -e "\nCreating database '${DB_NAME}' (if it's not already there)"
mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME}"
mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO wp@localhost IDENTIFIED BY 'wp';"
echo -e "\n DB operations done.\n\n"

# Nginx Logs
mkdir -p ${VVV_PATH_TO_SITE}/log
touch ${VVV_PATH_TO_SITE}/log/error.log
touch ${VVV_PATH_TO_SITE}/log/access.log

# Setup our site's doc_root directory (/public_html/) with optional site repo import
# If we're not using the site_repo option don't bother looking for one
if [[ false = "${SITE_REPO}" ]]; then
  if [[ ! -d "${DOC_ROOT}" ]]; then
    mkdir -p "${DOC_ROOT}"
    mkdir "${DOC_ROOT}/db-dumps"
  fi
# If we don't have existing local repo, clone it into DOC_ROOT (/public_html)
else
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
    if [[ -f "${DB_FILE}" ]]; then
      cp "${DB_FILE}" "${DB_BACKUPS}/${DB_NAME}.sql"
    fi
  fi
fi

# Install and configure the latest stable version of WordPress
if [[ ! -f "${DOC_ROOT}/wp-load.php" ]]; then
    echo "Downloading WordPress..."
	noroot wp core download --version="${WP_VERSION}"
fi

if [[ ! -f "${DOC_ROOT}/wp-config.php" ]]; then
  echo "Configuring WordPress Stable..."
  noroot wp core config --dbname="${DB_NAME}" --dbuser=wp --dbpass=wp --quiet --extra-php <<PHP
define( 'WP_DEBUG', true );
PHP
fi

if ! $(noroot wp core is-installed); then
  echo "Installing WordPress Stable..."

  if [ "${WP_TYPE}" = "subdomain" ]; then
    INSTALL_COMMAND="multisite-install --subdomains"
  elif [ "${WP_TYPE}" = "subdirectory" ]; then
    INSTALL_COMMAND="multisite-install"
  else
    INSTALL_COMMAND="install"
  fi

  noroot wp core ${INSTALL_COMMAND} --url="${DOMAIN}" --quiet --title="${SITE_TITLE}" --admin_name=admin --admin_email="admin@local.dev" --admin_password="password"

  # if we have a sql dump file try to import it into database
  if [[ -f "${DB_FILE}" ]]; then
    noroot wp db import "${DB_FILE}"
    noroot wp search-replace "${VVV_SITE_NAME}.com" "${DOMAIN}"
  fi
else
  echo "Updating WordPress Stable..."
  cd ${VVV_PATH_TO_SITE}/public_html
  noroot wp core update --version="${WP_VERSION}"
fi


# if img_proxy is set in vvv-custom.yml, add handler to vvv-nginx.conf
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
