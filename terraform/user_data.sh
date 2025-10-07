#!/bin/bash
set -ex

# Log all output
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=== Starting GTFS Validator Setup ==="
echo "Timestamp: $(date)"

# Update system
echo "=== Updating system packages ==="
dnf update -y

# Install Docker
echo "=== Installing Docker ==="
dnf install -y docker
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

# Install Docker Compose
echo "=== Installing Docker Compose ==="
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
curl -L "https://github.com/docker/compose/releases/download/$${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Install Python and dependencies
echo "=== Installing Python and dependencies ==="
dnf install -y python3 python3-pip cronie
pip3 install --upgrade pip
pip3 install boto3 requests pytz

# Create application directory
echo "=== Setting up application directory ==="
mkdir -p /opt/gtfs-validator
cd /opt/gtfs-validator

# Create environment file
cat > /opt/gtfs-validator/.env << 'ENVEOF'
S3_BUCKET=${s3_bucket}
SNS_TOPIC_ARN=${sns_topic_arn}
AWS_REGION=${aws_region}
GTFS_STATIC_URL=${gtfs_static_url}
GTFS_RT_TRIP_UPDATES_URL=${gtfs_rt_trip_updates_url}
GTFS_RT_VEHICLE_POSITIONS_URL=${gtfs_rt_vehicle_positions_url}
GTFS_RT_SERVICE_ALERTS_URL=${gtfs_rt_service_alerts_url}
TIMEZONE=${timezone}
ENVEOF

# Create Docker Compose file
cat > /opt/gtfs-validator/docker-compose.yml << 'COMPOSEEOF'
version: '3.8'
services:
  validator:
    image: ghcr.io/mobilitydata/gtfs-realtime-validator:latest
    container_name: gtfs-validator
    ports:
      - "8080:8080"
    restart: unless-stopped
    volumes:
      - validator-data:/data
    environment:
      - JAVA_OPTS=-Xmx512m
volumes:
  validator-data:
    driver: local
COMPOSEEOF

