## wp-vvv2-make-site Settings Reference

This file contains a list of settings and configuration details that may be useful as a quick reference.

### VVV Sites - Default Credentials

| **Credential** | **Username** | **Password** |
|----------------|--------------|--------------|
| Database       | wp           | wp           |
| WP Admin       | admin        | password     |
| MySQL          | root         | root         |
| Ubuntu root    | root         | vagrant      |

Also see: [**Default Credentials**](https://varyingvagrantvagrants.org/docs/en-US/default-credentials/) on VVV GitHub page

### vvv-custom.yml All Options

See full [VVV config file docs](https://varyingvagrantvagrants.org/docs/en-US/vvv-config/) for more info on these options.

```yaml
---
sites:
  # This example entry 'mycoolsite' displays all possible custom options (option_name: default_value)
  mycoolsite:
    repo: https://github.com/SeanM88/wp-vvv2-make-site.git
    vm_dir: /srv/www/mycoolsite
    local_dir: www/mycoolsite
    branch: master
    skip_provisioning: false
    allow_customfile: false
    nginx_upstream: php71
    hosts:
      - mycoolsite.dev
    custom:
      site_repo: false
      site_title: mycoolsite
      doc_root_dir: public_html # defaults to 'public_html' but 'htdocs' is also common, no slashes
      db_name: mycoolsite_db
      db_file: db-dumps/mycoolsite_db.sql # takes a relative file path inside the docroot directory
      img_proxy: false # img_proxy takes a live site's domain e.g mycoolsite.com (no http:// or trailing /)
      wp_version: latest
      wp_type: single

vm_config:
  memory: 1024
  cores: 1

utility-sources:
  core: https://github.com/Varying-Vagrant-Vagrants/vvv-utilities.git

utilities:
  core:
    - memcached-admin
    - opcache-status
    - phpmyadmin
    - webgrind
    - php71
```
