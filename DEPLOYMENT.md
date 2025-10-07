# St. Lawrence County Transit - GTFS Validator Deployment Guide

## 🎯 Quick Start (15 minutes)

This guide will help you deploy the GTFS Realtime Validator for St. Lawrence County Transit.

### Prerequisites Checklist
- ✅ AWS Account with administrator access
- ✅ AWS CLI installed and configured (`aws configure`)
- ✅ Terraform installed (version 1.5+)
- ✅ Your IP: **67.249.5.27**

### Step 1: Create EC2 SSH Key Pair

```bash
# Create the SSH key pair
aws ec2 create-key-pair \
  --key-name slc-transit-validator-key \
  --region us-east-1 \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/slc-transit-validator-key.pem

# Secure the key file (Mac/Linux)
chmod 400 ~/.ssh/slc-transit-validator-key.pem

# For Windows, save the key and set permissions via Properties > Security
```

### Step 2: Review Configuration

Your configuration has been pre-populated in `terraform/terraform.tfvars`:

```hcl
# St. Lawrence County Transit Settings
Region: us-east-1
Project: slc-transit-validator
Timezone: America/New_York

# GTFS Feeds (Passio3)
Static Feed: https://passio3.com/stlawrence/passioTransit/gtfs/google_transit.zip
Trip Updates: https://passio3.com/stlawrence/passioTransit/gtfs/realtime/tripUpdates
Vehicle Positions: https://passio3.com/stlawrence/passioTransit/gtfs/realtime/vehiclePositions
Service Alerts: https://passio3.com/stlawrence/passioTransit/gtfs/realtime/serviceAlerts

# Alerts
Primary Email: sonja@volunteertransportation.org
Your IP: 67.249.5.27/32
```

### Step 3: Deploy Infrastructure

```bash
# Navigate to terraform directory
cd terraform

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy (takes ~5 minutes)
terraform apply
# Type 'yes' when prompted
```

### Step 4: Configure Email Alerts

#### Primary Alert (Already Configured)
1. Check **sonja@volunteertransportation.org** inbox
2. Click "Confirm subscription" in the AWS SNS email

#### Add Additional Email Recipients
```bash
# Get the SNS Topic ARN
SNS_TOPIC=$(terraform output -raw sns_topic_arn)

# Subscribe additional emails
aws sns subscribe \
  --topic-arn $SNS_TOPIC \
  --protocol email \
  --notification-endpoint anuj@volunteertransportation.org

aws sns subscribe \
  --topic-arn $SNS_TOPIC \
  --protocol email \
  --notification-endpoint kyle@volunteertransportation.org
```

Each recipient will receive a confirmation email they must click.

### Step 5: Access the Validator

```bash
# Get connection details
terraform output

# SSH to instance
ssh -i ~/.ssh/slc-transit-validator-key.pem ec2-user@<INSTANCE_IP>

# Access Web UI
# Open browser: http://<INSTANCE_IP>:8080
```

## 📊 Expected Behavior

### First Boot
1. **Setup (5-10 min)**: Instance installs Docker, downloads validator
2. **Schedule Parse**: Analyzes SLC Transit GTFS to determine bus hours
3. **Cron Setup**: Creates automated start/stop schedule
4. **First Start**: Validator starts at scheduled time

### Ongoing Operation
- **Weekdays**: Validator runs during SLC Transit service hours
- **Monitoring**: Checks for errors every 5 minutes
- **Alerts**: Email sent within 5 minutes of critical errors
- **Reports**: Daily validation summary exported to S3 at 2 AM
- **Updates**: Weekly schedule refresh every Sunday at 3 AM

## 🔍 Monitoring

### View Validator Dashboard
```bash
# Get the URL
terraform output validator_url
# Opens: http://<IP>:8080
```

### Check Validation Reports
```bash
# List daily reports
aws s3 ls s3://slc-transit-validator-reports-$(aws sts get-caller-identity --query Account --output text)/daily-reports/ --recursive

# Download today's report
TODAY=$(date +%Y-%m-%d)
aws s3 cp s3://slc-transit-validator-reports-$(aws sts get-caller-identity --query Account --output text)/daily-reports/$TODAY/validation-report.json .
```

### CloudWatch Metrics
```bash
# View error trends
aws cloudwatch get-metric-statistics \
  --namespace GTFS/Validator \
  --metric-name CriticalErrors \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Sum
```

## 🛠️ Common Operations

### Manual Validator Control
```bash
# SSH to instance
ssh -i ~/.ssh/slc-transit-validator-key.pem ec2-user@<INSTANCE_IP>

# Start validator manually
cd /opt/gtfs-validator
docker-compose up -d

# Stop validator
docker-compose down

# View live logs
docker-compose logs -f

# Check cron schedule
crontab -l
```

### Update GTFS Feed URLs
```bash
# SSH to instance
ssh -i ~/.ssh/slc-transit-validator-key.pem ec2-user@<INSTANCE_IP>

# Edit configuration
sudo nano /opt/gtfs-validator/.env

# Restart to apply changes
cd /opt/gtfs-validator
docker-compose restart
```

### Troubleshooting

#### Validator Not Starting
```bash
# Check system logs
sudo cat /var/log/user-data.log

# Check Docker status
sudo systemctl status docker

# Check validator container
docker ps -a
docker logs gtfs-validator
```

#### No Email Alerts
```bash
# Verify SNS subscriptions
aws sns list-subscriptions-by-topic \
  --topic-arn $(terraform output -raw sns_topic_arn)

# Test monitoring manually
export $(cat /opt/gtfs-validator/.env | xargs)
/opt/gtfs-validator/monitor.py monitor
```

#### Reports Not in S3
```bash
# Check S3 bucket
aws s3 ls s3://slc-transit-validator-reports-$(aws sts get-caller-identity --query Account --output text)/

# Test report generation
export $(cat /opt/gtfs-validator/.env | xargs)
/opt/gtfs-validator/monitor.py daily-report
```

## 💰 Cost Estimate

**Monthly Cost: ~$8-10**

| Component | Monthly Cost |
|-----------|--------------|
| EC2 t4g.micro (ARM) | $6.13 |
| EBS 8GB gp3 | $0.80 |
| Elastic IP (attached) | $0.00 |
| S3 Storage (~10GB) | $0.23 |
| Data Transfer | $0.90 |
| SNS (3 emails) | $0.15 |
| CloudWatch (basic) | $0.00 |
| **Total** | **~$8.21/month** |

**Cost Optimization:**
- Reserve the EC2 instance (1-year): **$3.80/month** (saves $2.33/month)
- Reduce S3 retention from 30 to 7 days: Save ~$0.17/month

## 🧹 Cleanup

To remove all infrastructure:

```bash
cd terraform
terraform destroy
# Type 'yes' when prompted
```

This removes:
- EC2 instance and Elastic IP
- S3 bucket (after emptying)
- SNS topic and subscriptions
- IAM roles and security groups
- All monitoring data

## 📞 Support Contacts

**Volunteer Transportation Center Team:**
- Sonja: sonja@volunteertransportation.org
- Anuj: anuj@volunteertransportation.org
- Kyle: kyle@volunteertransportation.org

**AWS Support:**
- Check `/var/log/user-data.log` for setup logs
- Check `/var/log/validator-*.log` for runtime logs
- Run `docker logs gtfs-validator` for validator logs

## 📋 Next Steps After Deployment

1. ✅ Confirm all three email subscriptions
2. ✅ Access the web dashboard to see initial validation
3. ✅ Review first daily report (generated at 2 AM next day)
4. ✅ Set up CloudWatch alarms if needed (optional)
5. ✅ Consider Reserved Instance after 1 month of stable operation

---

**Deployment completed!** Your St. Lawrence County Transit GTFS Validator is now monitoring feed quality 24/7 with intelligent cost optimization. 🚌✨

