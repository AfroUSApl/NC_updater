#!/bin/sh

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script argument
OPTION="$1"

# Log update check
NEXTCLOUD_VERSION=$(sudo -u www php /usr/local/www/nextcloud/occ -V)

#nohup sh -c '"${NEXTCLOUD_VERSION} $(date)"' >> /NC_update.log 2>&1 &

#NC version and date for log
echo "" >> /NC_update.log
echo "______________________________________________" >> /NC_update.log
echo "${NEXTCLOUD_VERSION} $(date)" >> /NC_update.log
echo "‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾" >> /NC_update.log

#NC Version and date for output
echo -e "${BLUE}______________________________________________${NC}"
echo -e "${GREEN}${NEXTCLOUD_VERSION} $(date)${NC}"
echo -e "${BLUE}‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾${NC}"

#options only tasks
if [ "$OPTION" = "-trash" ]; then
    echo -e "${BLUE}Cleaning trashbin...${NC}"
    sudo -u www php /usr/local/www/nextcloud/occ trashbin:cleanup --all-users >> /NC_update.log
    nohup sh -c 'echo -e "Trashbin cleanup completed."' >> /NC_update.log 2>&1 &
    echo -e "${GREEN}Trashbin cleanup completed.${NC}"
    exit 0
elif [ "$OPTION" = "-scan" ]; then
    echo -e "${BLUE}Scanning files...${NC}"
    sudo -u www php /usr/local/www/nextcloud/occ files:scan --all >> /NC_update.log
    sudo -u www php /usr/local/www/nextcloud/occ files:scan-app-data >> /NC_update.log
    nohup sh -c 'echo -e "File scan completed."' >> /NC_update.log 2>&1 &
    echo -e "${GREEN}File scan completed.${NC}"
    exit 0
fi

#check for update
UPDATE_CHECK=$(sudo -u www php /usr/local/www/nextcloud/occ upgrade | grep -c "Nextcloud is already latest version")

if [ "$UPDATE_CHECK" -gt 0 ] && [ "$OPTION" != "-force" ]; then
    echo -e "${YELLOW}Nextcloud is already at the latest version. Exiting.${NC}"
    nohup sh -c 'echo -e "Nextcloud is already at the latest version. Exiting."' >> /NC_update.log 2>&1 &
    exit 0
fi

#start with update tasks and fixes for NC
find /usr/local/etc -type f -name "php.ini" -exec sed -i '' '/^[^;]*output_buffering/s/^/;/' {} +
if grep -q "^output_buffering=" /usr/local/www/nextcloud/.user.ini; then
    sudo -u www sed -i '' "s/^output_buffering=.*/output_buffering=0/" /usr/local/www/nextcloud/.user.ini
else
    echo "output_buffering=0" | sudo -u www tee -a /usr/local/www/nextcloud/.user.ini > /dev/null
fi

sudo -u www php /usr/local/www/nextcloud/occ app:enable admin_audit
sudo -u www php /usr/local/www/nextcloud/occ app:enable files_pdfviewer
sudo -u www php /usr/local/www/nextcloud/occ maintenance:mode --on
echo "" >> /NC_update.log

echo -e "${BLUE}Updating file permissions...${NC}"
nohup sh -c 'chown -R www:www /usr/local/www/nextcloud' &
nohup sh -c 'chmod -R 770 /mnt/files' &
nohup sh -c 'find /usr/local/www/nextcloud/ -type d -exec chmod 750 {} \;' &
nohup sh -c 'find /usr/local/www/nextcloud/ -type f -exec chmod 640 {} \;' &

echo -e "${GREEN}Running Nextcloud upgrade...${NC}"
sudo -u www php /usr/local/www/nextcloud/occ maintenance:mode --off
sudo -u www php /usr/local/www/nextcloud/occ upgrade
sudo -u www php /usr/local/www/nextcloud/occ db:add-missing-indices >> /NC_update.log
sudo -u www php /usr/local/www/nextcloud/occ db:add-missing-primary-keys >> /NC_update.log
sudo -u www php /usr/local/www/nextcloud/occ db:convert-filecache-bigint >> /NC_update.log

echo -e "${BLUE}Restarting services...${NC}"
service mysql-server restart
service redis restart
service php_fpm restart
service caddy restart

nohup sh -c 'service mysql-server status' >> /NC_update.log 2>&1 &
nohup sh -c 'service redis status' >> /NC_update.log 2>&1 &
nohup sh -c 'service php_fpm status' >> /NC_update.log 2>&1 &
nohup sh -c 'service caddy status' >> /NC_update.log 2>&1 &
nohup sh -c 'sudo -u www php /usr/local/www/nextcloud/occ files:scan --all' >> /NC_update.log 2>&1 &
nohup sh -c 'sudo -u www php /usr/local/www/nextcloud/occ files:scan-app-data' >> /NC_update.log 2>&1 &

sudo -u www php /usr/local/www/nextcloud/occ update:check >> /NC_update.log
sudo -u www php /usr/local/www/nextcloud/occ app:update --all >> /NC_update.log
sudo -u www php /usr/local/www/nextcloud/occ trashbin:cleanup --all-users >> /NC_update.log

echo -e "${GREEN}Update completed successfully.${NC}"
exit 0

