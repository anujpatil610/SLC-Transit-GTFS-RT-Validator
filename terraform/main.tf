terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "gtfs-validator"
}

variable "gtfs_static_url" {
  description = "GTFS static feed URL"
  type        = string
}

variable "gtfs_rt_trip_updates_url" {
  description = "GTFS Realtime trip updates URL"
  type        = string
}

variable "gtfs_rt_vehicle_positions_url" {
  description = "GTFS Realtime vehicle positions URL"
  type        = string
}

variable "gtfs_rt_service_alerts_url" {
  description = "GTFS Realtime service alerts URL (optional)"
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Email for critical alerts"
  type        = string
}

variable "my_ip_address" {
  description = "Your IP address for SSH access (e.g., 1.2.3.4/32)"
  type        = string
}

variable "ssh_key_name" {
  description = "EC2 key pair name (must exist)"
  type        = string
}

variable "timezone" {
  description = "Timezone for schedule parsing"
  type        = string
  default     = "America/New_York"
}

# Data sources
data "aws_caller_identity" "current" {}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# IAM Role for EC2
resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "ec2_policy" {
  name = "${var.project_name}-ec2-policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.validation_reports.arn,
          "${aws_s3_bucket.validation_reports.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["sns:Publish"]
        Resource = aws_sns_topic.critical_alerts.arn
      },
      {
        Effect = "Allow"
        Action = ["cloudwatch:PutMetricData"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# S3 Bucket for validation reports
resource "aws_s3_bucket" "validation_reports" {
  bucket = "${var.project_name}-reports-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_lifecycle_configuration" "validation_reports" {
  bucket = aws_s3_bucket.validation_reports.id

  rule {
    id     = "delete-old-reports"
    status = "Enabled"
    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket_public_access_block" "validation_reports" {
  bucket = aws_s3_bucket.validation_reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "validation_reports" {
  bucket = aws_s3_bucket.validation_reports.id

  versioning_configuration {
    status = "Enabled"
  }
}

# SNS Topic for alerts
resource "aws_sns_topic" "critical_alerts" {
  name         = "${var.project_name}-alerts"
  display_name = "GTFS Validation Alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.critical_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Security Group
resource "aws_security_group" "validator" {
  name        = "${var.project_name}-sg"
  description = "Security group for GTFS validator EC2"

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_address]
  }

  ingress {
    description = "Validator web UI from my IP"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_address]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

# EC2 Instance
resource "aws_instance" "validator" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  key_name               = var.ssh_key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids = [aws_security_group.validator.id]

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = base64gzip(templatefile("${path.module}/user_data.sh", {
    gtfs_static_url               = var.gtfs_static_url
    gtfs_rt_trip_updates_url      = var.gtfs_rt_trip_updates_url
    gtfs_rt_vehicle_positions_url = var.gtfs_rt_vehicle_positions_url
    gtfs_rt_service_alerts_url    = var.gtfs_rt_service_alerts_url
    s3_bucket                     = aws_s3_bucket.validation_reports.id
    sns_topic_arn                 = aws_sns_topic.critical_alerts.arn
    aws_region                    = var.aws_region
    timezone                      = var.timezone
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = var.project_name
  }

  lifecycle {
    ignore_changes = [user_data, ami]
  }
}

# Elastic IP (optional - for stable IP address)
resource "aws_eip" "validator" {
  instance = aws_instance.validator.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-eip"
  }
}

# Outputs
output "instance_id" {
  value       = aws_instance.validator.id
  description = "EC2 instance ID"
}

output "instance_public_ip" {
  value       = aws_eip.validator.public_ip
  description = "Public IP address (Elastic IP)"
}

output "validator_url" {
  value       = "http://${aws_eip.validator.public_ip}:8080"
  description = "Validator web UI URL"
}

output "ssh_command" {
  value       = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ec2-user@${aws_eip.validator.public_ip}"
  description = "SSH command to connect"
}

output "s3_bucket" {
  value       = aws_s3_bucket.validation_reports.id
  description = "S3 bucket for validation reports"
}

output "sns_topic_arn" {
  value       = aws_sns_topic.critical_alerts.arn
  description = "SNS topic ARN for alerts"
}

output "instance_state" {
  value       = aws_instance.validator.instance_state
  description = "EC2 instance state"
}

