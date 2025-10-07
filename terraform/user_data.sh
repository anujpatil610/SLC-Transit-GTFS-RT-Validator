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

# Create monitoring script
cat > /opt/gtfs-validator/monitor.py << 'MONITOREOF'
#!/usr/bin/env python3
import boto3
import requests
import json
import csv
from datetime import datetime
from io import StringIO
import os
import sys

# Configuration from environment
S3_BUCKET = os.environ.get('S3_BUCKET')
SNS_TOPIC = os.environ.get('SNS_TOPIC_ARN')
AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')
VALIDATOR_URL = "http://localhost:8080"

# Initialize AWS clients
s3 = boto3.client('s3', region_name=AWS_REGION)
sns = boto3.client('sns', region_name=AWS_REGION)
cloudwatch = boto3.client('cloudwatch', region_name=AWS_REGION)

def log(message):
    """Log with timestamp"""
    print(f"[{datetime.now().isoformat()}] {message}")

def check_validator_health():
    """Check if validator is running and accessible"""
    try:
        response = requests.get(f"{VALIDATOR_URL}/health", timeout=5)
        return response.status_code == 200
    except:
        return False

def fetch_validation_errors(minutes=5):
    """Fetch validation errors from the last N minutes"""
    try:
        # Get all feeds
        response = requests.get(f"{VALIDATOR_URL}/api/gtfs-feeds", timeout=30)
        if response.status_code != 200:
            log(f"Failed to fetch feeds: {response.status_code}")
            return []
        
        feeds = response.json()
        all_errors = []
        
        for feed in feeds:
            feed_id = feed.get('id')
            feed_name = feed.get('name', 'Unknown')
            
            # Get errors for this feed
            errors_response = requests.get(
                f"{VALIDATOR_URL}/api/gtfs-rt-feed/{feed_id}/errors",
                params={'minutes': minutes},
                timeout=30
            )
            
            if errors_response.status_code == 200:
                errors = errors_response.json()
                
                for error in errors:
                    if error.get('severity') in ['CRITICAL', 'ERROR']:
                        error['feed_name'] = feed_name
                        error['feed_id'] = feed_id
                        error['timestamp'] = datetime.now().isoformat()
                        all_errors.append(error)
        
        return all_errors
    
    except Exception as e:
        log(f"Error fetching validation errors: {e}")
        return []

def send_critical_alert(errors):
    """Send SNS notification for critical errors"""
    if not errors:
        return
    
    # Group errors by feed
    errors_by_feed = {}
    for error in errors:
        feed_name = error.get('feed_name', 'Unknown')
        if feed_name not in errors_by_feed:
            errors_by_feed[feed_name] = []
        errors_by_feed[feed_name].append(error)
    
    # Build message
    message = f"""
GTFS REALTIME VALIDATION CRITICAL ALERT
========================================

Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S %Z')}
Total Critical Errors: {len(errors)}
Affected Feeds: {len(errors_by_feed)}

CRITICAL ISSUES DETECTED:

"""
    
    for feed_name, feed_errors in errors_by_feed.items():
        message += f"\n{'='*60}\n"
        message += f"Feed: {feed_name}\n"
        message += f"Error Count: {len(feed_errors)}\n"
        message += f"{'-'*60}\n\n"
        
        for idx, error in enumerate(feed_errors[:10], 1):
            message += f"{idx}. [{error.get('severity')}] {error.get('errorType', 'Unknown')}\n"
            message += f"   Message: {error.get('errorMessage', 'No message available')}\n"
            message += f"   Entity: {error.get('entityType', 'N/A')} (ID: {error.get('entityId', 'N/A')})\n"
            
            if error.get('occurrenceCount', 0) > 1:
                message += f"   Occurrences: {error['occurrenceCount']}\n"
            message += "\n"
        
        if len(feed_errors) > 10:
            message += f"   ... and {len(feed_errors) - 10} more errors\n\n"
    
    message += f"\n{'='*60}\n"
    message += "\nACTION REQUIRED:\n"
    message += "1. Review GTFS Realtime feeds for data quality issues\n"
    message += "2. Check validator dashboard for detailed error analysis\n"
    message += "3. Investigate feed source systems\n"
    message += f"\nValidator Dashboard: {VALIDATOR_URL}\n"
    
    try:
        sns.publish(
            TopicArn=SNS_TOPIC,
            Subject=f"🚨 GTFS Validation Alert - {len(errors)} Critical Error(s)",
            Message=message
        )
        log(f"Alert sent for {len(errors)} critical errors")
    except Exception as e:
        log(f"Error sending SNS notification: {e}")

def export_daily_report():
    """Export comprehensive daily validation report to S3"""
    try:
        log("Starting daily report export")
        
        # Fetch all feeds
        response = requests.get(f"{VALIDATOR_URL}/api/gtfs-feeds", timeout=30)
        if response.status_code != 200:
            log("Failed to fetch feeds for daily report")
            return
        
        feeds = response.json()
        
        # Collect data for report
        report_data = {
            'generated_at': datetime.now().isoformat(),
            'report_type': 'daily_validation',
            'feeds': []
        }
        
        total_errors = 0
        critical_errors = 0
        
        for feed in feeds:
            feed_id = feed.get('id')
            feed_name = feed.get('name', 'Unknown')
            
            # Get errors from last 24 hours
            errors_response = requests.get(
                f"{VALIDATOR_URL}/api/gtfs-rt-feed/{feed_id}/errors",
                params={'hours': 24},
                timeout=30
            )
            
            if errors_response.status_code == 200:
                errors = errors_response.json()
                
                feed_data = {
                    'name': feed_name,
                    'id': feed_id,
                    'gtfs_url': feed.get('gtfsUrl'),
                    'error_count': len(errors),
                    'errors': errors
                }
                
                report_data['feeds'].append(feed_data)
                total_errors += len(errors)
                critical_errors += sum(1 for e in errors if e.get('severity') in ['CRITICAL', 'ERROR'])
        
        report_data['summary'] = {
            'total_feeds': len(feeds),
            'total_errors': total_errors,
            'critical_errors': critical_errors
        }
        
        # Export JSON report
        date_str = datetime.now().strftime('%Y-%m-%d')
        json_key = f"daily-reports/{date_str}/validation-report.json"
        
        s3.put_object(
            Bucket=S3_BUCKET,
            Key=json_key,
            Body=json.dumps(report_data, indent=2),
            ContentType='application/json'
        )
        
        log(f"JSON report uploaded to s3://{S3_BUCKET}/{json_key}")
        
        # Export CSV report
        csv_key = f"daily-reports/{date_str}/validation-errors.csv"
        csv_buffer = StringIO()
        csv_writer = csv.writer(csv_buffer)
        
        # CSV header
        csv_writer.writerow([
            'Date', 'Feed Name', 'Error Type', 'Severity', 
            'Error Message', 'Entity Type', 'Entity ID', 'Occurrence Count'
        ])
        
        # CSV data
        for feed_data in report_data['feeds']:
            for error in feed_data['errors']:
                csv_writer.writerow([
                    date_str,
                    feed_data['name'],
                    error.get('errorType', ''),
                    error.get('severity', ''),
                    error.get('errorMessage', ''),
                    error.get('entityType', ''),
                    error.get('entityId', ''),
                    error.get('occurrenceCount', 1)
                ])
        
        s3.put_object(
            Bucket=S3_BUCKET,
            Key=csv_key,
            Body=csv_buffer.getvalue(),
            ContentType='text/csv'
        )
        
        log(f"CSV report uploaded to s3://{S3_BUCKET}/{csv_key}")
        
        # Publish metrics
        publish_metrics(total_errors, critical_errors)
        
        log("Daily report export completed successfully")
        
    except Exception as e:
        log(f"Error exporting daily report: {e}")

def publish_metrics(total_errors=0, critical_errors=0):
    """Publish CloudWatch metrics"""
    try:
        cloudwatch.put_metric_data(
            Namespace='GTFS/Validator',
            MetricData=[
                {
                    'MetricName': 'TotalErrors',
                    'Value': total_errors,
                    'Unit': 'Count',
                    'Timestamp': datetime.now()
                },
                {
                    'MetricName': 'CriticalErrors',
                    'Value': critical_errors,
                    'Unit': 'Count',
                    'Timestamp': datetime.now()
                }
            ]
        )
        log(f"Metrics published: TotalErrors={total_errors}, CriticalErrors={critical_errors}")
    except Exception as e:
        log(f"Error publishing metrics: {e}")

def main():
    """Main entry point"""
    if len(sys.argv) < 2:
        log("Usage: monitor.py [monitor|daily-report]")
        sys.exit(1)
    
    action = sys.argv[1]
    
    if action == 'monitor':
        log("Starting critical error monitoring")
        
        if not check_validator_health():
            log("Validator is not running or not accessible")
            sys.exit(0)
        
        errors = fetch_validation_errors(minutes=5)
        
        if errors:
            log(f"Found {len(errors)} critical errors")
            send_critical_alert(errors)
            publish_metrics(len(errors), len(errors))
        else:
            log("No critical errors detected")
            publish_metrics(0, 0)
    
    elif action == 'daily-report':
        log("Starting daily report generation")
        
        if not check_validator_health():
            log("Validator is not running - skipping daily report")
            sys.exit(0)
        
        export_daily_report()
    
    else:
        log(f"Unknown action: {action}")
        sys.exit(1)

if __name__ == '__main__':
    main()
MONITOREOF

chmod +x /opt/gtfs-validator/monitor.py

# Create schedule parser script
cat > /opt/gtfs-validator/parse_schedule.py << 'SCHEDULEEOF'
#!/usr/bin/env python3
import requests
import zipfile
import io
import csv
from datetime import datetime, time
import os

GTFS_URL = os.environ.get('GTFS_STATIC_URL')
TIMEZONE = os.environ.get('TIMEZONE', 'America/New_York')

def parse_gtfs_schedule():
    """Parse GTFS feed to determine service hours"""
    try:
        print(f"Downloading GTFS feed from {GTFS_URL}")
        response = requests.get(GTFS_URL, timeout=120)
        response.raise_for_status()
        
        times = []
        
        with zipfile.ZipFile(io.BytesIO(response.content)) as z:
            # Parse stop_times.txt to find service hours
            if 'stop_times.txt' in z.namelist():
                with z.open('stop_times.txt') as f:
                    reader = csv.DictReader(io.TextIOWrapper(f, 'utf-8'))
                    for row in reader:
                        if row.get('arrival_time'):
                            times.append(row['arrival_time'])
        
        if not times:
            print("No times found in GTFS feed, using default schedule")
            # Default: 5 AM to 11 PM
            print("5:00|23:00")
            return
        
        times.sort()
        earliest = times[0]
        latest = times[-1]
        
        # Parse time strings (handle 24+ hours)
        def parse_time(time_str):
            parts = time_str.split(':')
            hours = int(parts[0]) % 24
            minutes = int(parts[1])
            return hours, minutes
        
        start_h, start_m = parse_time(earliest)
        end_h, end_m = parse_time(latest)
        
        # Add 15-minute buffer before, 30-minute buffer after
        start_m = max(0, start_m - 15)
        if start_m < 0:
            start_h = max(0, start_h - 1)
            start_m = 45
        
        end_m = min(59, end_m + 30)
        if end_m >= 60:
            end_h = min(23, end_h + 1)
            end_m = 29
        
        print(f"{start_h}:{start_m:02d}|{end_h}:{end_m:02d}")
        
    except Exception as e:
        print(f"Error parsing GTFS schedule: {e}")
        # Default fallback
        print("5:00|23:00")

if __name__ == '__main__':
    parse_gtfs_schedule()
SCHEDULEEOF

chmod +x /opt/gtfs-validator/parse_schedule.py

