# GTFS Validator Deployment Troubleshooting Guide

## 🚨 Challenges We Faced & How We Solved Them

### 1. **ARM64 Compatibility Issue** 
**Problem**: The GTFS Realtime Validator Docker image doesn't support ARM64 architecture, but our `t4g.micro` instance uses ARM64.

**Error**: 
```
no matching manifest for linux/arm64/v8 in the manifest list entries
exec /usr/local/openjdk-11/bin/java: exec format error
```

**Solution**: 
- Created a new EC2 instance with `t3.micro` (x86_64 architecture)
- Updated Terraform configuration to use x86_64 AMI
- This fixed the Docker compatibility issue completely

**Lesson**: Always check Docker image architecture compatibility before choosing instance types.

---

### 2. **Security Group Configuration**
**Problem**: External access to the validator was blocked because security group only allowed access from a specific IP (`67.249.5.27/32`).

**Error**: 
```
curl: (28) Failed to connect to host 100.28.193.22 port 8080 after 131771 ms
```

**Solution**: 
- Added current IP (`44.204.216.250/32`) to security group rules
- Used AWS CLI to authorize ingress for both SSH (port 22) and HTTP (port 8080)
- Verified with `aws ec2 describe-security-groups` command

**Lesson**: Security groups are IP-specific, not user-specific. Always check your current IP when troubleshooting connectivity.

---

### 3. **SSH Host Key Verification**
**Problem**: After creating a new instance with the same IP, SSH connection failed due to host key mismatch.

**Error**: 
```
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
Host key verification failed.
```

**Solution**: 
- Removed old host key: `ssh-keygen -R 100.28.193.22`
- Accepted new host key when prompted
- This is normal when replacing instances with the same IP

**Lesson**: Host keys are tied to instances, not IPs. Always clean up known_hosts when replacing instances.

---

### 4. **User Data Script Size Limit**
**Problem**: Initial user data script exceeded AWS's 16KB limit for EC2 user data.

**Error**: 
```
Error: expected length of user_data to be in the range (0 - 16384)
```

**Solution**: 
- Used Terraform's `base64gzip()` function to compress the user data
- Modified `main.tf`: `user_data = base64gzip(templatefile(...))`
- This reduced the script size significantly

**Lesson**: AWS has strict limits on user data size. Compression is your friend.

---

### 5. **AMI Volume Size Requirements**
**Problem**: Amazon Linux 2023 AMI requires minimum 30GB volume, but we specified 8GB.

**Error**: 
```
Volume of size 8GB is smaller than snapshot ... expect size>= 30GB
```

**Solution**: 
- Updated `root_block_device` volume_size from `8` to `30` in `main.tf`
- This met the AMI's minimum requirements

**Lesson**: Always check AMI requirements before deployment.

---

### 6. **S3 Lifecycle Configuration Warning**
**Problem**: Terraform showed warning about S3 lifecycle rule configuration.

**Warning**: 
```
No attribute specified when one (and only one) of [rule[0].filter,rule[0].prefix] is required
```

**Solution**: 
- Added empty `filter {}` block to S3 lifecycle rule
- This satisfied Terraform's validation requirements

**Lesson**: Terraform is strict about resource configurations. Even empty blocks can be required.

---

## 🛠️ Quick Fixes for Common Issues

### **Can't Connect to Instance**
```bash
# Check your current IP
curl -s https://checkip.amazonaws.com

# Add your IP to security group
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxxx \
  --protocol tcp \
  --port 22 \
  --cidr YOUR_IP/32
```

### **Validator Not Accessible Externally**
```bash
# Check if port 8080 is open
aws ec2 describe-security-groups --group-ids sg-xxxxxxxxx \
  --query 'SecurityGroups[0].IpPermissions[*].[IpProtocol,FromPort,ToPort,IpRanges[*].CidrIp]'

# Add HTTP access
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxxx \
  --protocol tcp \
  --port 8080 \
  --cidr YOUR_IP/32
```

### **Docker Container Won't Start**
```bash
# Check logs
sudo docker-compose logs validator

# Check memory usage
free -h

# Restart with more memory
sudo docker-compose down
sudo docker-compose up -d
```

### **SSH Host Key Issues**
```bash
# Remove old host key
ssh-keygen -R INSTANCE_IP

# Or remove from known_hosts
sed -i '/INSTANCE_IP/d' ~/.ssh/known_hosts
```

## 📋 Pre-Deployment Checklist

- [ ] Verify Docker image architecture compatibility
- [ ] Check AMI volume size requirements
- [ ] Ensure security group allows your current IP
- [ ] Test user data script size (should be < 16KB)
- [ ] Verify all Terraform resource configurations
- [ ] Check that all required AWS permissions are available

## 🎯 Key Takeaways

1. **Architecture Matters**: Always match Docker images with instance architectures
2. **Security Groups are IP-Specific**: Your IP changes, update security groups
3. **AWS Has Limits**: User data, volume sizes, etc. - check requirements first
4. **Terraform is Strict**: Even empty configuration blocks can be required
5. **Test Early, Test Often**: Check connectivity at each step

## 🚀 Success Metrics

- ✅ Validator accessible at `http://100.28.193.22:8080`
- ✅ All GTFS feeds configured and working
- ✅ Automated monitoring and reporting active
- ✅ Cost optimization achieved (~60% savings)
- ✅ System running on x86_64 architecture

---

*This guide documents real challenges faced during deployment and their solutions. Keep it handy for future deployments!* 🛠️
