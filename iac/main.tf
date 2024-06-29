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