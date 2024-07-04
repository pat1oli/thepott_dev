terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 5.55"
        }
    }
}

variable "region" {
  description = "The AWS region where resources will be deployed."
  type        = string
  default     = "us-east-1" # Default to US East (N. Virginia) if not provided
}


provider "aws" {
    region = var.region  
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


# Architecture for https
locals {
  s3_origin_id = "cvBucket_iac" 
  s3_domain_name = "${aws_s3_bucket.my-bucket.id}.s3-website-${var.region}.amazonaws.com"  #aws_s3_bucket.my-bucket.bucket_regional_domain_name
}

data "aws_cloudfront_cache_policy" "cache_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "s3-distribution" {
  origin {
    domain_name = local.s3_domain_name
    origin_id = local.s3_origin_id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1"]
    }
  }

  enabled = false
  is_ipv6_enabled = true
  comment = "distribution created via terraform"


  restrictions {
    geo_restriction {
      restriction_type = "none" 
      locations = []
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  default_cache_behavior {
    allowed_methods = ["GET", "HEAD"]
    cached_methods = [ "GET", "HEAD"]
    target_origin_id = local.s3_origin_id
    viewer_protocol_policy = "allow-all"
    cache_policy_id = data.aws_cloudfront_cache_policy.cache_optimized.id

    compress = true
  }
  
}