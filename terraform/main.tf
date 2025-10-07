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
    values = ["al2023-ami-*-arm64"]
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

