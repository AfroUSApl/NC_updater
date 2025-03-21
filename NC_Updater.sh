#!/bin/sh

# NC_Updater will run with these options:
#   -trash      to clear the trash for all users
#   -scan       to rescan files and folders for all users
#   -update     to update installation
#   -force      to download and update Nextcloud from the latest release

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

# NC version and date for log
echo "" >> /NC_update.log
echo "______________________________________________" >> /NC_update.log
echo "${NEXTCLOUD_VERSION} $(date)" >> /NC_update.log
echo "‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾" >> /NC_update.log

# NC Version and date for output
echo -e "${BLUE}______________________________________________${NC}"
echo -e "${GREEN}${NEXTCLOUD_VERSION} $(date)${NC}"
echo -e "${BLUE}‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾${NC}"

# Options-only tasks
if [ "$OPTION" = "-trash" ]; then
    echo -e "${BLUE}Cleaning trashbin...${NC}"
    sudo -u www php /usr/local/www/nextcloud/occ trashbin:cleanup --all-users >> /NC_update.log
    echo -e "${GREEN}Trashbin cleanup completed.${NC}"
    exit 0
elif [ "$OPTION" = "-scan" ]; then
    echo -e "${BLUE}Scanning files...${NC}"
    sudo -u www php /usr/local/www/nextcloud/occ files:scan --all >> /NC_update.log
    sudo -u www php /usr/local/www/nextcloud/occ files:scan-app-data >> /NC_update.log
    echo -e "${GREEN}File scan completed.${NC}"
    exit 0
elif [ "$OPTION" = "-update" ]; then
    echo -e "${BLUE}Running post update task...${NC}"
    echo ""
    echo "occ maintenance:repair --include-expensive..."
    sudo -u www php /usr/local/www/nextcloud/occ maintenance:repair --include-expensive
    echo "occ db:add-missing-indices..."
    sudo -u www php /usr/local/www/nextcloud/occ db:add-missing-indices
    echo -e "${GREEN}post update task finished.${NC}"
    exit 0
elif [ "$OPTION" = "" ]; then
    echo -e "${BLUE}Try to run NC-Updater.sh with one of these options:${NC}"
    echo -e "${YELLOW}-trash	${GREEN}Trashbin cleanup for all users${NC}"
    echo -e "${YELLOW}-scan	${GREEN}Scan files for all users (occ files:scan --all)${NC}"
    echo -e "${YELLOW}-force	${GREEN}Force reinstallation even if Nextcloud is in the latest version${NC}"
    echo -e "${YELLOW}-update	${GREEN}to update installation of Nextcloud${NC}"
    exit 0
fi

# Check for update
UPDATE_CHECK=$(sudo -u www php /usr/local/www/nextcloud/occ upgrade | grep -c "Nextcloud is already latest version")

if [ "$UPDATE_CHECK" -gt 0 ] && [ "$OPTION" != "-force" ] && [ "$OPTION" != "-update" ]; then
    echo -e "${YELLOW}Nextcloud is already at the latest version. Exiting.${NC}"
    exit 0
fi

# Force download and update Nextcloud
if [ "$OPTION" = "-force" ]; then
    echo -e "${BLUE}Downloading latest Nextcloud release...${NC}" >> /NC_update.log
    fetch -o /tmp https://download.nextcloud.com/server/releases/latest.zip >> /NC_update.log
    echo -e "${BLUE}Extracting Nextcloud files...${NC}" >> /NC_update.log
    tar xjf /tmp/latest.zip -C /usr/local/www/ >> /NC_update.log
    echo -e "${BLUE}Fixing file permissions...${NC}" >> /NC_update.log
    chown -R www:www /usr/local/www/nextcloud/ >> /NC_update.log
    echo -e "${GREEN}Nextcloud update files extracted.${NC}" >> /NC_update.log
fi

# Start with update tasks and fixes for NC
find /usr/local/etc -type f -name "php.ini" -exec sed -i '' '/^[^;]*output_buffering/s/^/;/' {} +
if grep -q "^output_buffering=" /usr/local/www/nextcloud/.user.ini; then
    sudo -u www sed -i '' "s/^output_buffering=.*/output_buffering=0/" /usr/local/www/nextcloud/.user.ini
else
    echo "output_buffering=0" | sudo -u www tee -a /usr/local/www/nextcloud/.user.ini > /dev/null
fi

sudo -u www php /usr/local/www/nextcloud/occ app:enable admin_audit
sudo -u www php /usr/local/www/nextcloud/occ app:enable files_pdfviewer
sudo -u www php /usr/local/www/nextcloud/occ maintenance:mode --on

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
