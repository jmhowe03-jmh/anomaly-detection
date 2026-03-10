#vars
variable "instance_type" {
  description = "The EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name of the existing EC2 KeyPair"
  type        = string
  default     = "ds5229_1"
}

variable "uva_id" {
  description = "User ID for naming uniqueness"
  type        = string
  default     = "vxx4kn"
}

variable "ssh_location" {
  description = "The IP address range that can be used to SSH to the EC2 instances"
  type        = string
  default     = "216.30.182.34/32"
}

variable "github_repo_url" {
  description = "URL of the GitHub repository"
  type        = string
  default     = "https://github.com/jmhowe03-jmh/anomaly-detection"
}


data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

#security group
resource "aws_security_group" "ec2_sg" {
  name        = "anomaly-detection-sg"
  description = "Allow SSH and app access"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_location]
  }

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# S3 
resource "aws_s3_bucket" "app_bucket" {
  bucket = "${var.uva_id}-anomaly-stack"
}

resource "aws_s3_bucket_versioning" "app_bucket_versioning" {
  bucket = aws_s3_bucket.app_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "app_bucket_block" {
  bucket = aws_s3_bucket.app_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- IAM Role & Policy ---
resource "aws_iam_role" "ec2_role" {
  name = "anomaly-detection-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "s3_access" {
  name = "s3-access-policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:DeleteObject",
        "s3:GetBucketLocation"
      ]
      Resource = [
        aws_s3_bucket.app_bucket.arn,
        "${aws_s3_bucket.app_bucket.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "anomaly-detection-instance-profile"
  role = aws_iam_role.ec2_role.name
}

#SNS topic, policy 
resource "aws_sns_topic" "anomaly_topic" {
  name         = "ds5220-dp1"
  display_name = "Anomaly Detection SNS Topic"
}

resource "aws_sns_topic_policy" "default" {
  arn = aws_sns_topic.anomaly_topic.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.anomaly_topic.arn
      Condition = {
        ArnLike = { "aws:SourceArn" = aws_s3_bucket.app_bucket.arn }
      }
    }]
  })
}

#S3 Notification 
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.app_bucket.id

  topic {
    topic_arn     = aws_sns_topic.anomaly_topic.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "raw/"
    filter_suffix = ".csv"
  }
  depends_on = [aws_sns_topic_policy.default]
}

# EC2 Instance
resource "aws_instance" "app_server" {
  ami                  = "ami-080e1f13689e07408" 
  instance_type        = var.instance_type
  key_name             = var.key_name
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  root_block_device {
    volume_size = 16
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e
              apt-get update -y
              apt-get install -y python3-pip python3-venv git awscli
              cd /home/ubuntu
              git clone ${var.github_repo_url} app
              cd app
              python3 -m venv /opt/anomaly-detection/venv
              source /opt/anomaly-detection/venv/bin/activate
              /opt/anomaly-detection/venv/bin/pip install -r requirements.txt
              /opt/anomaly-detection/venv/bin/fastapi run app.py --reload
              EOF

  tags = { Name = "anomaly-detection-ec2" }
}

resource "aws_eip" "app_eip" {
  instance = aws_instance.app_server.id
  domain   = "vpc"
}

#SNS Subscription 
resource "aws_sns_topic_subscription" "app_subscription" {
  topic_arn = aws_sns_topic.anomaly_topic.arn
  protocol  = "http"
  endpoint  = "http://${aws_eip.app_eip.public_ip}:8000/notify"
}


#put outs
output "api_endpoint" {
  value = "http://${aws_eip.app_eip.public_ip}:8000"
}

output "s3_bucket_name" {
  value = aws_s3_bucket.app_bucket.id
}

output "sns_topic_arn" {
  value = aws_sns_topic.anomaly_topic.arn
}