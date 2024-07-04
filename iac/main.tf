terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 5.55"
        }
    }
}

provider "aws" {
    region = "us-east-1"  
}


resource "aws_s3_bucket" "my-bucket" {
    bucket = "cv-bucket-from-iac-20240629"

    tags = {
      name = "bucket-terra"
    }
}


resource "aws_s3_bucket_ownership_controls" "s3-ownership" {
  bucket = aws_s3_bucket.my-bucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}


resource "aws_s3_bucket_versioning" "s3-versioning" {
    bucket = aws_s3_bucket.my-bucket.id

    versioning_configuration {
      status = "Enabled"
    }
}


resource "aws_s3_bucket_website_configuration" "s3-hosting" {
    bucket = aws_s3_bucket.my-bucket.id
    
    index_document {
      suffix = "cv.html"
    }

    error_document {
      key = "error.html"
    }
}

resource "aws_s3_bucket_public_access_block" "s3-public-access" {
  bucket = aws_s3_bucket.my-bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

data "aws_iam_policy_document" "allow_access_for_get_bucket" {
    statement {
        principals {
          type = "*"
          identifiers = ["*"]
        }
      actions = ["s3:GetObject"]
      effect = "Allow"
      resources = ["${aws_s3_bucket.my-bucket.arn}/*"]
    }
}


resource "aws_s3_bucket_policy" "s3-policy-get-bucket" {
    bucket = aws_s3_bucket.my-bucket.id
    policy = data.aws_iam_policy_document.allow_access_for_get_bucket.json
  
}


# Architecture for ACM
resource "aws_acm_certificate" "my-acm-cert" {
  domain_name = "apot.dev"
  validation_method = "DNS"

  subject_alternative_names = [ 
    "www.apot.dev"
   ]

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_route53_zone" "primary" {
  name = "apot.dev"
}

resource "aws_route53_record" "my-record" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "www.apot.dev"
  type    = "A"
  ttl     = 300
  records = [ aws_elb.ok ]
  alias {
    name = "apot.dev"
    zone_id = aws_elb.zone_id
    evaluate_target_health = true
  }
}


resource "aws_acm_certificate_validation" "my-valid-cert" {
  certificate_arn = aws_acm_certificate.my-acm-cert.arn
  validation_record_fqdns = [for record in aws_route53_record.my-record : record.fqdn]
  
}


# Architecture for https
locals {
  s3_origin_id = "cvBucket_iac"
}

resource "aws_cloudfront_distribution" "s3-distribution" {
  origin {
    domain_name = aws_s3_bucket.my-bucket.bucket_regional_domain_name
    origin_id = local.s3_origin_id
  }

  enabled = false
  is_ipv6_enabled = true
  comment = "distribution created via terraform"

  aliases = ["apot.dev", "www.apot.dev"]

  restrictions {
    geo_restriction {
      restriction_type = "none" 
      locations = []
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = false
    acm_certificate_arn = aws_acm_certificate.my-acm-cert.arn
    ssl_support_method = "sni-only"
  }

  default_cache_behavior {
    allowed_methods = ["GET", "HEAD"]
    cached_methods = [ "GET", "HEAD"]
    target_origin_id = local.s3_origin_id
    viewer_protocol_policy = "allow-all"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }
  
}