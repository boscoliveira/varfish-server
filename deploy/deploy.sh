#!/bin/bash
# Deployment script for VarFish server on EC2
# This script handles the deployment process when triggered by GitHub Actions or manually

set -e  # Exit on error

# Configuration
DEPLOY_DIR="${DEPLOY_PATH:-/home/ubuntu/varfish-server}"
BRANCH="${GIT_BRANCH:-main}"
LOG_FILE="/var/log/varfish-deploy.log"
BACKUP_DIR="/home/ubuntu/backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a $LOG_FILE
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a $LOG_FILE
    exit 1
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a $LOG_FILE
}

# Create backup of current deployment
backup_current() {
    log "Creating backup of current deployment..."
    mkdir -p $BACKUP_DIR
    if [ -d "$DEPLOY_DIR" ]; then
        BACKUP_NAME="varfish-backup-$(date +'%Y%m%d-%H%M%S').tar.gz"
        tar -czf "$BACKUP_DIR/$BACKUP_NAME" -C "$(dirname $DEPLOY_DIR)" "$(basename $DEPLOY_DIR)" 2>/dev/null || warning "Backup creation failed"
        log "Backup created: $BACKUP_NAME"
        
        # Keep only last 5 backups
        ls -t $BACKUP_DIR/varfish-backup-*.tar.gz | tail -n +6 | xargs -r rm
    fi
}

# Pull latest code
update_code() {
    log "Updating code from GitHub..."
    cd $DEPLOY_DIR
    
    # Stash any local changes
    git stash
    
    # Pull latest changes
    git fetch origin
    git checkout $BRANCH
    git pull origin $BRANCH
    
    log "Code updated to latest version"
}

# Deploy with Docker Compose
deploy_docker_compose() {
    log "Deploying with Docker Compose..."
    
    # Load environment variables if .env file exists
    if [ -f .env ]; then
        export $(cat .env | grep -v '^#' | xargs)
    fi
    
    # Determine which compose file to use
    if [ -f docker-compose.production.yml ]; then
        COMPOSE_FILE="docker-compose.production.yml"
    else
        COMPOSE_FILE="docker-compose.yml"
    fi
    
    # Check if using external services or local
    if [[ "$DATABASE_URL" == *"localhost"* ]] || [[ "$DATABASE_URL" == *"postgres:"* ]]; then
        log "Using local PostgreSQL and Redis services..."
        COMPOSE_PROFILES="--profile local-db --profile services"
    else
        log "Using external database and Redis services..."
        COMPOSE_PROFILES=""
    fi
    
    # Build the image first
    docker-compose -f $COMPOSE_FILE build web
    
    # Pull other images
    docker-compose -f $COMPOSE_FILE pull
    
    # Stop current containers
    docker-compose -f $COMPOSE_FILE down
    
    # Start containers with appropriate profiles
    docker-compose -f $COMPOSE_FILE $COMPOSE_PROFILES up -d
    
    # Wait for services to be healthy
    log "Waiting for services to be healthy..."
    sleep 20
    
    # Run migrations in container
    docker-compose -f $COMPOSE_FILE exec -T web python manage.py migrate --noinput || warning "Migration failed"
    
    # Collect static files
    docker-compose -f $COMPOSE_FILE exec -T web python manage.py collectstatic --noinput || warning "Static collection failed"
    
    # Create superuser if it doesn't exist (optional)
    if [ ! -z "$DJANGO_SUPERUSER_EMAIL" ]; then
        docker-compose -f $COMPOSE_FILE exec -T web python manage.py createsuperuser --noinput --email $DJANGO_SUPERUSER_EMAIL || true
    fi
}

# Deploy with standalone Docker
deploy_docker() {
    log "Deploying with standalone Docker..."
    
    # Build new image
    docker build -t varfish-server:latest .
    
    # Stop and remove old container
    docker stop varfish-server 2>/dev/null || true
    docker rm varfish-server 2>/dev/null || true
    
    # Run new container
    docker run -d \
        --name varfish-server \
        --restart unless-stopped \
        -p 8080:8080 \
        --env-file .env \
        -v varfish-data:/data \
        -v varfish-static:/static \
        varfish-server:latest
    
    # Wait for container to be ready
    log "Waiting for container to be ready..."
    sleep 10
}

# Deploy without Docker (native Python)
deploy_native() {
    log "Deploying with native Python..."
    
    # Activate virtual environment
    if [ -f venv/bin/activate ]; then
        source venv/bin/activate
    elif [ -f .venv/bin/activate ]; then
        source .venv/bin/activate
    else
        error "No virtual environment found!"
    fi
    
    # Update dependencies
    pip install -r backend/requirements.txt
    
    # Run migrations
    cd backend
    python manage.py migrate --noinput
    
    # Collect static files
    python manage.py collectstatic --noinput
    
    # Restart service
    sudo systemctl restart varfish-server
    sudo systemctl restart varfish-celery 2>/dev/null || true
    sudo systemctl restart varfish-celerybeat 2>/dev/null || true
}

# Health check
health_check() {
    log "Performing health check..."
    
    # Wait a bit for service to fully start
    sleep 5
    
    # Check if service is responding
    HEALTH_URL="http://localhost:8080/health/"
    
    for i in {1..6}; do
        if curl -f -s $HEALTH_URL > /dev/null 2>&1; then
            log "Health check passed! Service is running."
            return 0
        fi
        warning "Health check attempt $i failed, waiting..."
        sleep 10
    done
    
    error "Health check failed after 60 seconds!"
}

# Rollback to previous version
rollback() {
    error "Deployment failed! Consider manual rollback from: $BACKUP_DIR"
    # Implement automatic rollback if needed
}

# Main deployment flow
main() {
    log "Starting deployment process..."
    
    # Check if deployment directory exists
    if [ ! -d "$DEPLOY_DIR" ]; then
        error "Deployment directory $DEPLOY_DIR does not exist!"
    fi
    
    # Create backup
    backup_current
    
    # Update code
    update_code
    
    # Determine deployment method and deploy
    cd $DEPLOY_DIR
    
    if [ -f docker-compose.yml ] || [ -f docker-compose.yaml ]; then
        deploy_docker_compose
    elif [ -f Dockerfile ]; then
        deploy_docker
    else
        deploy_native
    fi
    
    # Verify deployment
    if health_check; then
        log "Deployment completed successfully!"
        
        # Clean up old Docker images
        docker image prune -f 2>/dev/null || true
    else
        rollback
    fi
}

# Run main function
main "$@"