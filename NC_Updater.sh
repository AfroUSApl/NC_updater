#!/bin/sh

set -e

# NC_Updater will run with these options:
#   -trash	to clear the trash for all users
#   -scan	to rescan files and folders for all users
#   -update	to update Nextcloud without backup
#   -backup	to update Nextcloud with backup
#   -force	to download and force update to the latest version

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

OPTION="$1"
LOGFILE="/NC_update.log"
NEXTCLOUD_DIR="/usr/local/www/nextcloud"
BACKUP_DIR="/mnt/backups"
DATE_STR=$(date +%F_%H-%M-%S)

# Check requirements
id www >/dev/null 2>&1 || { echo "User 'www' not found. Exiting."; exit 1; }
if [ ! -f "$NEXTCLOUD_DIR/occ" ]; then
    echo "Nextcloud OCC not found. Is Nextcloud installed correctly?"
    exit 1
fi

# Log rotation
MAXSIZE=1048576
if [ -f "$LOGFILE" ] && [ $(stat -f%z "$LOGFILE") -gt $MAXSIZE ]; then
    mv "$LOGFILE" "${LOGFILE}.bak"
    touch "$LOGFILE"
fi

NEXTCLOUD_VERSION=$(sudo -u www php $NEXTCLOUD_DIR/occ -V)

# Log version and date
{
  echo ""
  echo "______________________________________________"
  echo "$NEXTCLOUD_VERSION $(date)"
  echo "‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾"
} >> "$LOGFILE"

echo -e "${BLUE}______________________________________________${NC}"
echo -e "${GREEN}${NEXTCLOUD_VERSION} $(date)${NC}"
echo -e "${BLUE}‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾${NC}"

# Options-only tasks
case "$OPTION" in
  -trash)
    echo -e "${BLUE}Cleaning trashbin...${NC}"
    sudo -u www php $NEXTCLOUD_DIR/occ trashbin:cleanup --all-users >> "$LOGFILE"
    echo -e "${GREEN}Trashbin cleanup completed.${NC}"
    exit 0
    ;;
  -scan)
    echo -e "${BLUE}Scanning files...${NC}"
    sudo -u www php $NEXTCLOUD_DIR/occ files:scan --all | tee -a "$LOGFILE"
    sudo -u www php $NEXTCLOUD_DIR/occ files:scan-app-data | tee -a "$LOGFILE"
    echo -e "${GREEN}File scan completed.${NC}"
    exit 0
    ;;
  -update)
    echo -e "${BLUE}Running post update task (no backup)...${NC}"
    ;;
  -backup)
    echo -e "${BLUE}Creating backup before update...${NC}"
    mkdir -p "$BACKUP_DIR"
    rsync -a --delete "$NEXTCLOUD_DIR" "$BACKUP_DIR/nextcloud_backup_$DATE_STR"/
    echo -e "${GREEN}Backup created in $BACKUP_DIR/nextcloud_backup_$DATE_STR${NC}"
    ;;
  -force)
    echo -e "${BLUE}Downloading latest Nextcloud release...${NC}" >> "$LOGFILE"
    fetch -o /tmp/latest.zip https://download.nextcloud.com/server/releases/latest.zip >> "$LOGFILE"
    echo -e "${BLUE}Extracting Nextcloud files...${NC}" >> "$LOGFILE"
    tar -xf /tmp/latest.zip -C /usr/local/www/ >> "$LOGFILE"
    echo -e "${BLUE}Fixing file permissions...${NC}" >> "$LOGFILE"
    chown -R www:www "$NEXTCLOUD_DIR" >> "$LOGFILE"
    echo -e "${GREEN}Nextcloud update files extracted.${NC}" >> "$LOGFILE"
    ;;
  ""|-h|--help)
    echo -e "${BLUE}Usage: NC_Updater.sh [option]${NC}"
    echo -e "${YELLOW}-trash${NC}           Clean trashbin for all users"
    echo -e "${YELLOW}-scan${NC}            Rescan all user files"
    echo -e "${YELLOW}-update${NC}          Update Nextcloud (no backup)"
    echo -e "${YELLOW}-update_backup${NC}   Update Nextcloud with backup"
    echo -e "${YELLOW}-force${NC}           Force download and update"
    exit 0
    ;;
  *)
    echo -e "${RED}Unknown option: $OPTION${NC}"
    exit 1
    ;;
esac

# Run update tasks
find /usr/local/etc -type f -name "php.ini" -exec sed -i '' '/^[^;]*output_buffering/s/^/;/' {} +
if grep -q "^output_buffering=" $NEXTCLOUD_DIR/.user.ini; then
    sudo -u www sed -i '' "s/^output_buffering=.*/output_buffering=0/" $NEXTCLOUD_DIR/.user.ini
else
    echo "output_buffering=0" | sudo -u www tee -a $NEXTCLOUD_DIR/.user.ini > /dev/null
fi

sudo -u www php $NEXTCLOUD_DIR/occ app:enable admin_audit
sudo -u www php $NEXTCLOUD_DIR/occ app:enable files_pdfviewer
sudo -u www php $NEXTCLOUD_DIR/occ maintenance:mode --on

echo -e "${BLUE}Updating file permissions...${NC}"
nohup sh -c "chown -R www:www $NEXTCLOUD_DIR" &
nohup sh -c "chmod -R 770 /mnt/files" &
nohup sh -c "find $NEXTCLOUD_DIR -type d -exec chmod 750 {} \;" &
nohup sh -c "find $NEXTCLOUD_DIR -type f -exec chmod 640 {} \;" &

echo -e "${GREEN}Running Nextcloud upgrade...${NC}"
sudo -u www php $NEXTCLOUD_DIR/occ maintenance:mode --off
sudo -u www php $NEXTCLOUD_DIR/occ upgrade
sudo -u www php $NEXTCLOUD_DIR/occ db:add-missing-indices >> "$LOGFILE"
sudo -u www php $NEXTCLOUD_DIR/occ db:add-missing-primary-keys >> "$LOGFILE"
sudo -u www php $NEXTCLOUD_DIR/occ db:convert-filecache-bigint >> "$LOGFILE"

# Restart services
echo -e "${BLUE}Restarting services...${NC}"
service mysql-server restart
service redis restart
service php_fpm restart
service caddy restart

nohup sh -c 'service mysql-server status' >> "$LOGFILE" 2>&1 &
nohup sh -c 'service redis status' >> "$LOGFILE" 2>&1 &
nohup sh -c 'service php_fpm status' >> "$LOGFILE" 2>&1 &
nohup sh -c 'service caddy status' >> "$LOGFILE" 2>&1 &
nohup sh -c "sudo -u www php $NEXTCLOUD_DIR/occ files:scan --all" >> "$LOGFILE" 2>&1 &
nohup sh -c "sudo -u www php $NEXTCLOUD_DIR/occ files:scan-app-data" >> "$LOGFILE" 2>&1 &

sudo -u www php $NEXTCLOUD_DIR/occ update:check >> "$LOGFILE"
sudo -u www php $NEXTCLOUD_DIR/occ app:update --all >> "$LOGFILE"
sudo -u www php $NEXTCLOUD_DIR/occ trashbin:cleanup --all-users >> "$LOGFILE"

echo -e "${GREEN}Update completed successfully.${NC}"
exit 0
