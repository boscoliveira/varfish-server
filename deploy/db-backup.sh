#!/bin/bash
# Database backup script for VarFish
# Can backup both local Docker PostgreSQL and external databases

set -e

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/home/ubuntu/db-backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
S3_BACKUP_BUCKET="${S3_BACKUP_BUCKET:-}"
TIMESTAMP=$(date +'%Y%m%d_%H%M%S')

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

# Create backup directory
mkdir -p $BACKUP_DIR

# Function to backup PostgreSQL
backup_postgres() {
    log "Starting PostgreSQL backup..."
    
    BACKUP_FILE="$BACKUP_DIR/varfish_db_${TIMESTAMP}.sql.gz"
    
    if [[ "$DATABASE_URL" =~ ^postgresql://([^:]+):([^@]+)@([^:/]+):?([0-9]*)/(.+)$ ]]; then
        DB_USER="${BASH_REMATCH[1]}"
        DB_PASS="${BASH_REMATCH[2]}"
        DB_HOST="${BASH_REMATCH[3]}"
        DB_PORT="${BASH_REMATCH[4]:-5432}"
        DB_NAME="${BASH_REMATCH[5]}"
        
        # Check if it's a Docker container or external database
        if [[ "$DB_HOST" == "postgres" ]] || [[ "$DB_HOST" == "localhost" ]]; then
            # Local Docker PostgreSQL
            log "Backing up local Docker PostgreSQL..."
            docker exec varfish-postgres pg_dump -U "$DB_USER" -d "$DB_NAME" | gzip > "$BACKUP_FILE"
        else
            # External PostgreSQL
            log "Backing up external PostgreSQL at $DB_HOST..."
            PGPASSWORD="$DB_PASS" pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" | gzip > "$BACKUP_FILE"
        fi
        
        log "Database backup completed: $BACKUP_FILE"
        echo "$BACKUP_FILE"
    else
        error "Could not parse DATABASE_URL"
    fi
}

# Function to backup Redis
backup_redis() {
    log "Starting Redis backup..."
    
    REDIS_BACKUP_FILE="$BACKUP_DIR/varfish_redis_${TIMESTAMP}.rdb"
    
    if [[ "$CELERY_BROKER_URL" =~ ^redis://([^:/]+):?([0-9]*) ]]; then
        REDIS_HOST="${BASH_REMATCH[1]}"
        REDIS_PORT="${BASH_REMATCH[2]:-6379}"
        
        if [[ "$REDIS_HOST" == "redis" ]] || [[ "$REDIS_HOST" == "localhost" ]]; then
            # Local Docker Redis
            log "Backing up local Docker Redis..."
            docker exec varfish-redis redis-cli BGSAVE
            sleep 5
            docker cp varfish-redis:/data/dump.rdb "$REDIS_BACKUP_FILE"
        else
            # External Redis (if accessible)
            log "Redis backup for external instances should be handled by the provider"
        fi
        
        if [ -f "$REDIS_BACKUP_FILE" ]; then
            log "Redis backup completed: $REDIS_BACKUP_FILE"
        fi
    fi
}

# Function to backup media files
backup_media() {
    log "Backing up media files..."
    
    MEDIA_BACKUP_FILE="$BACKUP_DIR/varfish_media_${TIMESTAMP}.tar.gz"
    
    if [ -d "/var/lib/docker/volumes/varfish-server_media_files/_data" ]; then
        tar -czf "$MEDIA_BACKUP_FILE" -C /var/lib/docker/volumes/varfish-server_media_files/_data .
        log "Media files backup completed: $MEDIA_BACKUP_FILE"
    else
        log "No media files volume found, skipping media backup"
    fi
}

# Upload to S3 if configured
upload_to_s3() {
    if [ ! -z "$S3_BACKUP_BUCKET" ] && [ ! -z "$AWS_ACCESS_KEY_ID" ]; then
        log "Uploading backups to S3..."
        
        for file in $BACKUP_DIR/varfish_*_${TIMESTAMP}*; do
            if [ -f "$file" ]; then
                aws s3 cp "$file" "s3://$S3_BACKUP_BUCKET/backups/$(basename $file)"
                log "Uploaded $(basename $file) to S3"
            fi
        done
    fi
}

# Clean old backups
cleanup_old_backups() {
    log "Cleaning up backups older than $BACKUP_RETENTION_DAYS days..."
    
    find $BACKUP_DIR -name "varfish_*.sql.gz" -mtime +$BACKUP_RETENTION_DAYS -delete
    find $BACKUP_DIR -name "varfish_*.rdb" -mtime +$BACKUP_RETENTION_DAYS -delete
    find $BACKUP_DIR -name "varfish_*.tar.gz" -mtime +$BACKUP_RETENTION_DAYS -delete
    
    log "Cleanup completed"
}

# Main backup process
main() {
    log "Starting VarFish backup process..."
    
    # Perform backups
    DB_BACKUP=$(backup_postgres)
    backup_redis
    backup_media
    
    # Upload to S3 if configured
    upload_to_s3
    
    # Clean old backups
    cleanup_old_backups
    
    log "Backup process completed successfully!"
    
    # Output backup location for scripts
    echo "BACKUP_LOCATION=$DB_BACKUP"
}

# Run main function
main "$@"