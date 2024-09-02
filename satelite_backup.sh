#!/bin/bash

# Variables
BACKUP_DIR="/var/satellite_backups"
FULL_BACKUP_DIR="$BACKUP_DIR/full"
INCREMENTAL_BACKUP_DIR="$BACKUP_DIR/incremental"
DATE="$(date +%Y%m%d)"
LAST_FULL_BACKUP_DIR="$(find "${FULL_BACKUP_DIR}" -type d -printf '%T+ %p\n' | sort -r | head -1 | cut -d' ' -f2)"
FULL_BACKUP_DAY=0  # Set the day of the week for full backup (0=Sunday, 6=Saturday)
RETENTION_DAYS=30  # Number of days to keep backups

# Create backup directories if they don't exist
mkdir -p "${FULL_BACKUP_DIR}"
mkdir -p "${INCREMENTAL_BACKUP_DIR}"

# Function to delete old backups
delete_old_backups() {
    echo "Deleting backups older than ${RETENTION_DAYS} days..."
    # Find and delete old full backups, excluding the most recent one
    find "${FULL_BACKUP_DIR}" -type d -mtime +${RETENTION_DAYS} ! -name "$(basename "${LAST_FULL_BACKUP_DIR}")" -print0 | while IFS= read -r -d '' full_backup; do
        # Delete the full backup
        rm -rf "${full_backup}"
        echo "Deleted full backup: ${full_backup}"

        # Find and delete associated incremental backups
        find "${INCREMENTAL_BACKUP_DIR}" -type f -newermt "$(date -r "${full_backup}" +%Y-%m-%d)" -print0 | while IFS= read -r -d '' incremental_backup; do
            rm -f "${incremental_backup}"
            echo "Deleted incremental backup: ${incremental_backup}"
        done
    done
    # Find and delete old incremental backups that are not linked to any full backup
    find "${INCREMENTAL_BACKUP_DIR}" -type f -mtime +${RETENTION_DAYS} -exec rm -f {} \;
    echo "Old backups deleted."
}

# Function for full backup
full_backup() {
    echo "Starting full backup..."
    satellite-maintain backup offline --assumeyes "${FULL_BACKUP_DIR}"
    echo "Full backup completed: ${FULL_BACKUP_DIR}"
}

# Function for incremental backup
incremental_backup() {
    echo "Starting incremental backup..."
    if [ -d "${LAST_FULL_BACKUP_DIR}" ] && [ -f "${LAST_FULL_BACKUP_DIR}/.postgres.snar" ]; then
        satellite-maintain backup offline --assumeyes --incremental "${LAST_FULL_BACKUP_DIR}" "${INCREMENTAL_BACKUP_DIR}"
        echo "Incremental backup completed: ${INCREMENTAL_BACKUP_DIR}"
    else
        echo "Previous full backup directory or .postgres.snar file not found. Creating a full backup instead."
        full_backup
    fi
}

# Determine the current day of the week (0=Sunday, 6=Saturday)
CURRENT_DAY_OF_WEEK="$(date +%w)"

# Delete old backups
delete_old_backups

# Check if a full backup exists
if [ -z "${LAST_FULL_BACKUP_DIR}" ]; then
    echo "No full backup found. Creating a full backup..."
    full_backup
else
    # Run full backup on the specified day of the week
    if [ "${CURRENT_DAY_OF_WEEK}" -eq "${FULL_BACKUP_DAY}" ]; then
        full_backup
    else
        incremental_backup
    fi
fi