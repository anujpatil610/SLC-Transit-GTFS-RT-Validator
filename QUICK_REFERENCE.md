# 🚀 Quick Reference - SLC Transit Validator

## Your Configuration Summary

### ✅ Pre-configured Settings
| Setting | Value |
|---------|-------|
| **Project Name** | `slc-transit-validator` |
| **AWS Region** | `us-east-1` (N. Virginia) |
| **Timezone** | `America/New_York` |
| **Your IP** | `67.249.5.27/32` |
| **SSH Key** | `slc-transit-validator-key` |

### 📡 GTFS Feeds (Passio3)
```
Static:    https://passio3.com/stlawrence/passioTransit/gtfs/google_transit.zip
Trips:     https://passio3.com/stlawrence/passioTransit/gtfs/realtime/tripUpdates
Vehicles:  https://passio3.com/stlawrence/passioTransit/gtfs/realtime/vehiclePositions
Alerts:    https://passio3.com/stlawrence/passioTransit/gtfs/realtime/serviceAlerts
```

### 📧 Alert Recipients
1. sonja@volunteertransportation.org (primary - auto-configured)
2. anuj@volunteertransportation.org (add after deployment)
3. kyle@volunteertransportation.org (add after deployment)

---

## 🎯 Deployment Steps (15 minutes)

### 1️⃣ Create SSH Key (2 min)
```bash
aws ec2 create-key-pair \
  --key-name slc-transit-validator-key \
  --region us-east-1 \
  --query 'KeyMaterial' \
  --output text > slc-transit-validator-key.pem

chmod 400 slc-transit-validator-key.pem
```

### 2️⃣ Deploy Infrastructure (10 min)
```bash
cd terraform
terraform init
terraform apply
# Type: yes
```

### 3️⃣ Confirm Email (1 min)
- Check **sonja@volunteertransportation.org**
- Click "Confirm subscription"

### 4️⃣ Add Additional Emails (2 min)
```bash
SNS_TOPIC=$(terraform output -raw sns_topic_arn)

aws sns subscribe --topic-arn $SNS_TOPIC --protocol email \
  --notification-endpoint anuj@volunteertransportation.org

aws sns subscribe --topic-arn $SNS_TOPIC --protocol email \
  --notification-endpoint kyle@volunteertransportation.org
```

### 5️⃣ Access Validator
```bash
# Get IP and URL
terraform output

# SSH
ssh -i ../slc-transit-validator-key.pem ec2-user@<IP>

# Web UI
http://<IP>:8080
```

---

## 📊 Common Commands

### View Deployment Info
```bash
cd terraform
terraform output
```

### Check Validation Status
```bash
# SSH to instance
ssh -i slc-transit-validator-key.pem ec2-user@<IP>

# Check if running
docker ps

# View logs
docker logs gtfs-validator -f
```

### Download Daily Report
```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
TODAY=$(date +%Y-%m-%d)

aws s3 cp \
  s3://slc-transit-validator-reports-$ACCOUNT/daily-reports/$TODAY/validation-report.json \
  ./slc-transit-report-$TODAY.json
```

### View Error Metrics (Last 7 Days)
```bash
aws cloudwatch get-metric-statistics \
  --namespace GTFS/Validator \
  --metric-name CriticalErrors \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Sum
```

---

## 🆘 Troubleshooting

### Problem: Validator not starting
```bash
# Check logs
ssh -i slc-transit-validator-key.pem ec2-user@<IP>
sudo cat /var/log/user-data.log
docker logs gtfs-validator
```

### Problem: No email alerts
```bash
# Verify subscriptions
aws sns list-subscriptions-by-topic \
  --topic-arn $(cd terraform && terraform output -raw sns_topic_arn)
```

### Problem: Can't SSH
```bash
# Verify your current IP
curl https://checkip.amazonaws.com

# If IP changed, update security group
cd terraform
# Edit terraform.tfvars with new IP
terraform apply
```

---

## 💰 Monthly Cost: ~$8

| Component | Cost |
|-----------|------|
| EC2 t4g.micro | $6.13 |
| Storage | $0.80 |
| S3 + Data | $1.13 |
| SNS (3 emails) | $0.15 |

**Save $2.33/month with Reserved Instance (1-year commitment)**

---

## 📞 Support

**Deployment Issues:** See [DEPLOYMENT.md](DEPLOYMENT.md)

**Operations:** See [README.md](README.md)

**VTC Team:**
- Sonja: sonja@volunteertransportation.org
- Anuj: anuj@volunteertransportation.org  
- Kyle: kyle@volunteertransportation.org

---

## 🧹 Cleanup (if needed)

```bash
cd terraform
terraform destroy
# Type: yes
```

Removes all infrastructure and stops billing.

