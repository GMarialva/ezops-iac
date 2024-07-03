terraform {
  backend "s3" {
    bucket         = "test-gmarialva-terraform-state-bucket"
    key            = "test/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "test-gmarialva-terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"
  profile = "EZOPS"
}

resource "aws_security_group" "instance" {
  vpc_id = "vpc-02ca8c4ce6926db7e" #aws_vpc.main.id
  tags = {
    Name = "test-gmarialva-instance-sg"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app" {
  ami           = "ami-04a81a99f5ec58529"
  instance_type = "t3.small"
  subnet_id     = "subnet-042ba6c4b445abf04" #aws_subnet.private.id
  key_name      = var.key_name

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
  }

  security_groups = [aws_security_group.instance.id]

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get upgrade -y
              apt-get install -y apt-transport-https ca-certificates curl software-properties-common
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
              add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
              apt-get update -y
              apt-get install -y docker-ce docker-ce-cli containerd.io
              usermod -aG docker ubuntu
              newgrp docker
              curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
              install minikube-linux-amd64 /usr/local/bin/minikube
              minikube start
              curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
              install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
              EOF

  tags = {
    Name = "test-gmarialva-app-instance"
  }
}

resource "aws_s3_bucket" "static_website" {
  bucket = "test-gmarialva-website-bucket"

  tags = {
    Name = "test-gmarialva-website-bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.static_website.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.static_website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = "s3:GetObject"
        Resource = "${aws_s3_bucket.static_website.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_website_configuration" "static_website_configuration" {
  bucket = aws_s3_bucket.static_website.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_cloudfront_distribution" "static_website_distribution" {
  origin {
    domain_name = aws_s3_bucket.static_website.bucket_domain_name
    origin_id   = "S3-static-website-origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-static-website-origin"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "test-gmarialva-website-distribution"
  }
}

resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for static website bucket"
}

output "website_url" {
  value = aws_cloudfront_distribution.static_website_distribution.domain_name
}

variable "key_name" {
  description = "Nome da chave SSH para acessar a instância"
   default     = "test-gmarialva-key"
}
