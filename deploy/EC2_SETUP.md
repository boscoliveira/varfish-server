# EC2 Deployment Setup for VarFish Server

## Prerequisites

### 1. EC2 Instance Setup
- Ubuntu 20.04/22.04 LTS recommended
- Instance type: t3.medium minimum (adjust based on load)
- Security Group rules:
  - SSH (port 22) from your IP
  - HTTP (port 80) from anywhere
  - HTTPS (port 443) from anywhere  
  - Application port 8080 (optional, if not using reverse proxy)

### 2. Initial EC2 Configuration

SSH into your EC2 instance and run:

```bash
# Update system
sudo apt-get update
sudo apt-get upgrade -y

# Install Docker and Docker Compose
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker ubuntu
sudo systemctl enable docker

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Install Git
sudo apt-get install -y git

# Install nginx for reverse proxy (optional)
sudo apt-get install -y nginx

# Clone your repository
cd /home/ubuntu
git clone https://github.com/boscoliveira/varfish-server.git
cd varfish-server
```

### 3. Environment Configuration

Create a `.env` file in the project root:

```bash
# Database Configuration
DATABASE_URL=postgresql://varfish:password@localhost:5432/varfish
REDIS_URL=redis://localhost:6379/0

# Django Settings
DJANGO_SECRET_KEY=your-secret-key-here
DJANGO_DEBUG=False
DJANGO_ALLOWED_HOSTS=your-ec2-public-dns.amazonaws.com,yourdomain.com

# Application Settings
VARFISH_ENABLE_EXOMISER_PRIORITISER=0
VARFISH_ENABLE_CADD=0
FIELD_ENCRYPTION_KEY=your-encryption-key

# Optional: S3 for static files
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret
AWS_STORAGE_BUCKET_NAME=your-bucket
```

### 4. Setup Nginx Reverse Proxy (Optional but Recommended)

Create `/etc/nginx/sites-available/varfish`:

```nginx
server {
    listen 80;
    server_name your-domain.com;
    
    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    client_max_body_size 100M;
}
```

Enable the site:
```bash
sudo ln -s /etc/nginx/sites-available/varfish /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

## GitHub Actions Secrets Configuration

In your GitHub repository, go to Settings → Secrets and variables → Actions, and add:

1. **EC2_HOST**: Your EC2 public IP or domain
   - Example: `ec2-xx-xxx-xxx-xx.compute-1.amazonaws.com`

2. **EC2_USER**: SSH username (usually `ubuntu` for Ubuntu AMIs)
   - Example: `ubuntu`

3. **EC2_SSH_KEY**: Your private SSH key content
   - Copy the entire content of your `.pem` file
   - Make sure to include the BEGIN and END lines

4. **DEPLOY_PATH**: Path where the application is deployed
   - Example: `/home/ubuntu/varfish-server`

### Adding Secrets via GitHub CLI

```bash
# Install GitHub CLI if not already installed
brew install gh  # macOS
# or
sudo apt install gh  # Ubuntu

# Authenticate
gh auth login

# Add secrets
gh secret set EC2_HOST --body "your-ec2-host.amazonaws.com"
gh secret set EC2_USER --body "ubuntu"
gh secret set EC2_SSH_KEY < path/to/your-key.pem
gh secret set DEPLOY_PATH --body "/home/ubuntu/varfish-server"
```

## Database Configuration Options

### Option 1: Local PostgreSQL and Redis (Docker)
The deployment includes PostgreSQL and Redis as Docker containers. This is suitable for single-instance deployments.

```bash
# In your .env file, use:
DATABASE_URL=postgresql://varfish:changeme@postgres:5432/varfish
CELERY_BROKER_URL=redis://redis:6379/0
```

### Option 2: External Managed Services (Recommended for Production)
Use managed database services like AWS RDS for PostgreSQL and ElastiCache for Redis, or services from Render, Supabase, etc.

```bash
# In your .env file, use your external service URLs:
DATABASE_URL=postgresql://user:password@your-rds-endpoint.amazonaws.com:5432/varfish
CELERY_BROKER_URL=redis://your-elasticache-endpoint.cache.amazonaws.com:6379
```

### Option 3: Hybrid Approach
You can mix local and external services based on your needs.

## Deployment Methods

### Method 1: Automatic Deployment (GitHub Actions)

Once configured, deployments happen automatically when you push to the main branch:

```bash
git add .
git commit -m "Update feature"
git push origin main
```

### Method 2: Manual Deployment

SSH into EC2 and run:

```bash
cd /home/ubuntu/varfish-server
./deploy/deploy.sh
```

### Method 3: Manual GitHub Actions Trigger

Go to Actions tab → Deploy to EC2 → Run workflow

## Monitoring and Logs

### View Application Logs
```bash
# Docker Compose logs
docker-compose logs -f

# Standalone Docker logs
docker logs -f varfish-server

# Deployment logs
tail -f /var/log/varfish-deploy.log
```

### Health Check
```bash
curl http://localhost:8080/health/
```

## Troubleshooting

### Permission Issues
```bash
# Fix Docker permissions
sudo usermod -aG docker $USER
newgrp docker

# Fix directory permissions
sudo chown -R ubuntu:ubuntu /home/ubuntu/varfish-server
```

### Port Already in Use
```bash
# Find process using port 8080
sudo lsof -i :8080
# Kill the process
sudo kill -9 <PID>
```

### Database Connection Issues
- Ensure PostgreSQL is running
- Check DATABASE_URL in .env
- Verify network connectivity

### Rollback Procedure
```bash
# Backups are stored in /home/ubuntu/backups
cd /home/ubuntu
tar -xzf backups/varfish-backup-[timestamp].tar.gz
cd varfish-server
docker-compose up -d
```

## Security Best Practices

1. **Never commit secrets to Git**
   - Use .env files (add to .gitignore)
   - Use GitHub Secrets for CI/CD

2. **Regular Updates**
   ```bash
   sudo apt-get update && sudo apt-get upgrade
   docker system prune -a
   ```

3. **SSL/TLS Setup**
   ```bash
   # Install Certbot
   sudo apt-get install certbot python3-certbot-nginx
   
   # Get certificate
   sudo certbot --nginx -d your-domain.com
   ```

4. **Firewall Configuration**
   ```bash
   sudo ufw allow 22/tcp
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   sudo ufw enable
   ```

## Backup and Restore

### Automated Backups

The deployment includes comprehensive backup scripts for database, Redis, and media files.

#### Setting up Automated Backups

```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM
0 2 * * * /home/ubuntu/varfish-server/deploy/db-backup.sh

# Or every 6 hours for critical systems
0 */6 * * * /home/ubuntu/varfish-server/deploy/db-backup.sh
```

#### Manual Backup

```bash
cd /home/ubuntu/varfish-server
./deploy/db-backup.sh
```

#### Backup to S3

Configure S3 backup in your .env:

```bash
S3_BACKUP_BUCKET=your-backup-bucket
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret
BACKUP_RETENTION_DAYS=30
```

### Database Restore

#### List Available Backups

```bash
./deploy/db-restore.sh --list
```

#### Restore from Latest Backup

```bash
./deploy/db-restore.sh latest
```

#### Restore from Specific Backup

```bash
./deploy/db-restore.sh /home/ubuntu/db-backups/varfish_db_20240101_120000.sql.gz
```

#### Interactive Restore

```bash
./deploy/db-restore.sh
# Follow the prompts to select database, Redis, and media backups
```

## Support

For issues specific to this deployment setup:
1. Check deployment logs: `/var/log/varfish-deploy.log`
2. Review GitHub Actions logs in the Actions tab
3. Ensure all secrets are correctly configured
4. Verify EC2 security group settings