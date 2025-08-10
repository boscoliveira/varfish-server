#!/bin/bash
# Database restore script for VarFish
# Restores from backup files created by db-backup.sh

set -e

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/home/ubuntu/db-backups}"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Function to list available backups
list_backups() {
    log "Available backups:"
    echo "===================="
    ls -lht $BACKUP_DIR/varfish_db_*.sql.gz 2>/dev/null | head -10 || echo "No database backups found"
    echo ""
    ls -lht $BACKUP_DIR/varfish_redis_*.rdb 2>/dev/null | head -10 || echo "No Redis backups found"
    echo ""
    ls -lht $BACKUP_DIR/varfish_media_*.tar.gz 2>/dev/null | head -10 || echo "No media backups found"
}

# Function to restore PostgreSQL
restore_postgres() {
    local BACKUP_FILE=$1
    
    if [ ! -f "$BACKUP_FILE" ]; then
        error "Backup file not found: $BACKUP_FILE"
    fi
    
    log "Restoring PostgreSQL from $BACKUP_FILE..."
    
    if [[ "$DATABASE_URL" =~ ^postgresql://([^:]+):([^@]+)@([^:/]+):?([0-9]*)/(.+)$ ]]; then
        DB_USER="${BASH_REMATCH[1]}"
        DB_PASS="${BASH_REMATCH[2]}"
        DB_HOST="${BASH_REMATCH[3]}"
        DB_PORT="${BASH_REMATCH[4]:-5432}"
        DB_NAME="${BASH_REMATCH[5]}"
        
        # Stop application containers first
        warning "Stopping application containers..."
        docker-compose down web celery-worker celery-beat 2>/dev/null || true
        
        # Drop and recreate database
        if [[ "$DB_HOST" == "postgres" ]] || [[ "$DB_HOST" == "localhost" ]]; then
            # Local Docker PostgreSQL
            log "Restoring to local Docker PostgreSQL..."
            
            # Drop existing connections
            docker exec varfish-postgres psql -U "$DB_USER" -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();" || true
            
            # Drop and recreate database
            docker exec varfish-postgres dropdb -U "$DB_USER" "$DB_NAME" || true
            docker exec varfish-postgres createdb -U "$DB_USER" "$DB_NAME"
            
            # Restore
            gunzip -c "$BACKUP_FILE" | docker exec -i varfish-postgres psql -U "$DB_USER" -d "$DB_NAME"
        else
            # External PostgreSQL
            log "Restoring to external PostgreSQL at $DB_HOST..."
            warning "This will DROP and RECREATE the database. Press Ctrl+C to cancel, or wait 10 seconds to continue..."
            sleep 10
            
            # Drop existing connections
            PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();" || true
            
            # Drop and recreate database
            PGPASSWORD="$DB_PASS" dropdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB_NAME" || true
            PGPASSWORD="$DB_PASS" createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB_NAME"
            
            # Restore
            gunzip -c "$BACKUP_FILE" | PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME"
        fi
        
        log "PostgreSQL restore completed"
    else
        error "Could not parse DATABASE_URL"
    fi
}

# Function to restore Redis
restore_redis() {
    local BACKUP_FILE=$1
    
    if [ ! -f "$BACKUP_FILE" ]; then
        error "Backup file not found: $BACKUP_FILE"
    fi
    
    log "Restoring Redis from $BACKUP_FILE..."
    
    if [[ "$CELERY_BROKER_URL" =~ ^redis://([^:/]+):?([0-9]*) ]]; then
        REDIS_HOST="${BASH_REMATCH[1]}"
        
        if [[ "$REDIS_HOST" == "redis" ]] || [[ "$REDIS_HOST" == "localhost" ]]; then
            # Local Docker Redis
            log "Restoring to local Docker Redis..."
            
            # Stop Redis to replace dump file
            docker stop varfish-redis
            
            # Copy backup file
            docker cp "$BACKUP_FILE" varfish-redis:/data/dump.rdb
            
            # Start Redis
            docker start varfish-redis
            
            log "Redis restore completed"
        else
            warning "Cannot restore to external Redis instance - please handle through provider"
        fi
    fi
}

# Function to restore media files
restore_media() {
    local BACKUP_FILE=$1
    
    if [ ! -f "$BACKUP_FILE" ]; then
        error "Backup file not found: $BACKUP_FILE"
    fi
    
    log "Restoring media files from $BACKUP_FILE..."
    
    MEDIA_VOLUME="/var/lib/docker/volumes/varfish-server_media_files/_data"
    
    if [ -d "$MEDIA_VOLUME" ]; then
        # Clear existing media files
        rm -rf $MEDIA_VOLUME/*
        
        # Extract backup
        tar -xzf "$BACKUP_FILE" -C "$MEDIA_VOLUME"
        
        log "Media files restore completed"
    else
        error "Media volume not found at $MEDIA_VOLUME"
    fi
}

# Interactive restore
interactive_restore() {
    list_backups
    
    echo ""
    read -p "Enter the database backup file name (or 'latest' for most recent): " DB_BACKUP
    
    if [ "$DB_BACKUP" == "latest" ]; then
        DB_BACKUP=$(ls -t $BACKUP_DIR/varfish_db_*.sql.gz 2>/dev/null | head -1)
        if [ -z "$DB_BACKUP" ]; then
            error "No database backups found"
        fi
    elif [ ! -z "$DB_BACKUP" ]; then
        DB_BACKUP="$BACKUP_DIR/$DB_BACKUP"
    fi
    
    if [ ! -z "$DB_BACKUP" ] && [ -f "$DB_BACKUP" ]; then
        restore_postgres "$DB_BACKUP"
    fi
    
    read -p "Restore Redis backup? (y/N): " RESTORE_REDIS
    if [ "$RESTORE_REDIS" == "y" ]; then
        read -p "Enter the Redis backup file name (or 'latest'): " REDIS_BACKUP
        
        if [ "$REDIS_BACKUP" == "latest" ]; then
            REDIS_BACKUP=$(ls -t $BACKUP_DIR/varfish_redis_*.rdb 2>/dev/null | head -1)
        elif [ ! -z "$REDIS_BACKUP" ]; then
            REDIS_BACKUP="$BACKUP_DIR/$REDIS_BACKUP"
        fi
        
        if [ ! -z "$REDIS_BACKUP" ] && [ -f "$REDIS_BACKUP" ]; then
            restore_redis "$REDIS_BACKUP"
        fi
    fi
    
    read -p "Restore media files? (y/N): " RESTORE_MEDIA
    if [ "$RESTORE_MEDIA" == "y" ]; then
        read -p "Enter the media backup file name (or 'latest'): " MEDIA_BACKUP
        
        if [ "$MEDIA_BACKUP" == "latest" ]; then
            MEDIA_BACKUP=$(ls -t $BACKUP_DIR/varfish_media_*.tar.gz 2>/dev/null | head -1)
        elif [ ! -z "$MEDIA_BACKUP" ]; then
            MEDIA_BACKUP="$BACKUP_DIR/$MEDIA_BACKUP"
        fi
        
        if [ ! -z "$MEDIA_BACKUP" ] && [ -f "$MEDIA_BACKUP" ]; then
            restore_media "$MEDIA_BACKUP"
        fi
    fi
}

# Main restore process
main() {
    log "Starting VarFish restore process..."
    
    if [ "$1" == "--list" ]; then
        list_backups
    elif [ ! -z "$1" ]; then
        # Restore from specific file
        restore_postgres "$1"
        
        # Restart services
        log "Restarting services..."
        docker-compose up -d
    else
        # Interactive mode
        interactive_restore
        
        # Restart services
        log "Restarting services..."
        docker-compose up -d
    fi
    
    log "Restore process completed!"
}

# Run main function
main "$@"