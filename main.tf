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

# resource "aws_s3_bucket" "terraform_state" {
#   bucket = "test-gmarialva-terraform-state-bucket"

#   versioning {
#     enabled = true
#   }

#   server_side_encryption_configuration {
#     rule {
#       apply_server_side_encryption_by_default {
#         sse_algorithm = "AES256"
#       }
#     }
#   }

#   lifecycle {
#     prevent_destroy = true
#   }
# }

# resource "aws_dynamodb_table" "terraform_state_lock" {
#   name         = "test-gmarialva-terraform-state-lock"
#   billing_mode = "PAY_PER_REQUEST"
#   hash_key     = "LockID"

#   attribute {
#     name = "LockID"
#     type = "S"
#   }
# }

# resource "aws_vpc" "main" {
#   cidr_block = "10.0.0.0/16"
#   tags = {
#     Name = "test-gmarialva-vpc"
#   }
# }

# resource "aws_subnet" "private" {
#   vpc_id            = aws_vpc.main.id
#   cidr_block        = "10.0.1.0/24"
#   map_public_ip_on_launch = false
#   tags = {
#     Name = "test-gmarialva-private-subnet"
#   }
# }

# resource "aws_internet_gateway" "gw" {
#   vpc_id = aws_vpc.main.id
#   tags = {
#     Name = "test-gmarialva-gateway"
#   }
# }

# resource "aws_route_table" "private" {
#   vpc_id = aws_vpc.main.id
#   tags = {
#     Name = "test-gmarialva-private-route-table"
#   }
# }

# resource "aws_route" "private_route" {
#   route_table_id         = aws_route_table.private.id
#   destination_cidr_block = "0.0.0.0/0"
#   gateway_id             = aws_internet_gateway.gw.id
# }

# resource "aws_route_table_association" "a" {
#   subnet_id      = aws_subnet.private.id
#   route_table_id = aws_route_table.private.id
# }

resource "aws_security_group" "instance" {
  vpc_id = "vpc-02ca8c4ce6926db7e" #aws_vpc.main.id
  tags = {
    Name = "test-gmarialva-instance-sg"
  }

  # ingress {
  #   from_port   = 22
  #   to_port     = 22
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  # ingress {
  #   from_port   = 80
  #   to_port     = 80
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

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
              apt-get install -y apt-transport-https ca-certificates curl
              curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
              echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" >> /etc/apt/sources.list.d/kubernetes.list
              apt-get update -y
              apt-get install -y docker.io conntrack
              curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
              install minikube-linux-amd64 /usr/local/bin/minikube
              minikube start
              EOF

  tags = {
    Name = "test-gmarialva-app-instance"
  }
}

# resource "aws_lb" "app_lb" {
#   name               = "test-gmarialva-app-lb"
#   internal           = false
#   load_balancer_type = "application"
#   security_groups    = [aws_security_group.instance.id]
#   subnets            = [aws_subnet.private.id]

#   tags = {
#     Name = "test-gmarialva-app-lb"
#   }
# }

# resource "aws_lb_target_group" "app_tg" {
#   name     = "test-gmarialva-app-tg"
#   port     = 80
#   protocol = "HTTP"
#   vpc_id   = aws_vpc.main.id

#   health_check {
#     path                = "/"
#     protocol            = "HTTP"
#     matcher             = "200"
#     interval            = 30
#     timeout             = 5
#     healthy_threshold   = 5
#     unhealthy_threshold = 2
#   }

#   tags = {
#     Name = "test-gmarialva-app-tg"
#   }
# }

# resource "aws_lb_listener" "app_listener" {
#   load_balancer_arn = aws_lb.app_lb.arn
#   port              = "80"
#   protocol          = "HTTP"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.app_tg.arn
#   }

#   tags = {
#     Name = "test-gmarialva-app-listener"
#   }
# }

# resource "aws_lb_target_group_attachment" "app_attachment" {
#   target_group_arn = aws_lb_target_group.app_tg.arn
#   target_id        = aws_instance.app.id
#   port             = 80
# }

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