# St. Lawrence County Transit - GTFS Realtime Validator Configuration

# AWS Configuration
aws_region   = "us-east-1"
project_name = "slc-transit-validator"

# GTFS Feed URLs - St. Lawrence County Transit (Passio)
gtfs_static_url               = "https://passio3.com/stlawrence/passioTransit/gtfs/google_transit.zip"
gtfs_rt_trip_updates_url      = "https://passio3.com/stlawrence/passioTransit/gtfs/realtime/tripUpdates"
gtfs_rt_vehicle_positions_url = "https://passio3.com/stlawrence/passioTransit/gtfs/realtime/vehiclePositions"
gtfs_rt_service_alerts_url    = "https://passio3.com/stlawrence/passioTransit/gtfs/realtime/serviceAlerts"

# Email for critical alerts (primary contact)
# Note: Additional emails can be subscribed via SNS console after deployment
alert_email = "anuj@volunteertransportation.org"

# Security - Your IP for SSH access
my_ip_address = "67.249.5.27/32"

# EC2 Key Pair - will be created in deployment step
ssh_key_name = "slc-transit-validator-key"

# Timezone for St. Lawrence County, New York
timezone = "America/New_York"

