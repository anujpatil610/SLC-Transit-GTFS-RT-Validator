# GTFS Realtime Validator - Ultra-Low-Cost AWS Deployment

## Overview
Automated GTFS Realtime validation system running on a single EC2 instance with intelligent scheduling based on bus service hours.

**Cost: ~$8/month** (90% savings compared to full infrastructure)

## Features
✅ Automated start/stop based on GTFS schedule  
✅ Real-time critical error alerts via email (SNS)  
✅ Daily validation reports exported to S3  
✅ CloudWatch metrics for monitoring  
✅ Automatic schedule updates  
✅ 30-day report retention  

## Prerequisites
1. AWS account with programmatic access configured
2. Terraform installed (1.5+)
3. AWS CLI configured

## Quick Deployment (10 minutes)

### Step 1: Create SSH Key
```bash
# Create new EC2 key pair
aws ec2 create-key-pair \
  --key-name gtfs-validator-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/gtfs-validator-key.pem

chmod 400 ~/.ssh/gtfs-validator-key.pem
```

### Step 2: Get Your IP Address
```bash
MY_IP=$(curl -s https://checkip.amazonaws.com)
echo "Your IP: $MY_IP/32"
```

### Step 3: Configure
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

### Step 4: Deploy
```bash
terraform init
terraform plan
terraform apply
```

### Step 5: Confirm Email Subscription
Check your email and click the SNS confirmation link.

## Accessing the System

### SSH Access
```bash
# Get SSH command from Terraform output
terraform output ssh_command

# Or manually
ssh -i ~/.ssh/gtfs-validator-key.pem ec2-user@<INSTANCE_IP>
```

### Web UI Access
```bash
# Get validator URL from output
terraform output validator_url

# Open in browser: http://<INSTANCE_IP>:8080
```

## Operations

### Check Validator Status
```bash
ssh -i ~/.ssh/gtfs-validator-key.pem ec2-user@<INSTANCE_IP>

# Check Docker containers
docker ps

# View logs
docker logs gtfs-validator

# Check cron schedule
crontab -l

# View monitoring logs
tail -f /var/log/validator-monitor.log
tail -f /var/log/validator-daily.log
```

### Manual Control
```bash
# Start validator manually
cd /opt/gtfs-validator
docker-compose up -d

# Stop validator
docker-compose down

# View live logs
docker-compose logs -f

# Restart validator
docker-compose restart
```

### View Reports in S3
```bash
# List all reports
aws s3 ls s3://gtfs-validator-reports-<ACCOUNT_ID>/daily-reports/ --recursive

# Download specific report
aws s3 cp s3://gtfs-validator-reports-<ACCOUNT_ID>/daily-reports/2025-10-07/validation-report.json .
```

### Update GTFS Feed URLs
```bash
# Edit environment file on EC2
sudo nano /opt/gtfs-validator/.env

# Restart validator to apply changes
cd /opt/gtfs-validator
docker-compose restart
```

## Monitoring

### CloudWatch Metrics
```bash
# View error metrics
aws cloudwatch get-metric-statistics \
  --namespace GTFS/Validator \
  --metric-name CriticalErrors \
  --start-time 2025-10-07T00:00:00Z \
  --end-time 2025-10-07T23:59:59Z \
  --period 3600 \
  --statistics Sum
```

### Email Alerts
Critical errors trigger immediate email notifications with:
- Error count and severity
- Affected feed names
- Detailed error messages
- Entity information
- Timestamps
