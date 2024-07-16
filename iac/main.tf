terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 5.55"
        }
    }
}

variable "region" {
  description = "The region"
  type        = string
  default     = "us-east-1"
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

# architecture for dynamodb

resource "aws_dynamodb_table" "my-table" {
  name = "iac-counter"
  billing_mode = "PAY_PER_REQUEST"
  hash_key = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    name = "dynamo-iac-table"
  }
}


resource "aws_dynamodb_table_item" "my-table-item" {
  table_name = aws_dynamodb_table.my-table.name
  hash_key   = aws_dynamodb_table.my-table.hash_key

  item = <<ITEM
{
  "id": {"S": "visitors"},
  "counter": {"N": "0"}
}
ITEM
}


resource "aws_api_gateway_rest_api" "my-rest-api" {
  name = "iac-api"
  description = "My API IAC"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_iam_role" "my-lambda-role" {
  name = "lambda_iac_dynamodb_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "my-lambda-dynamodb-policy" {
  name = "lambda_iac_dynamodb_policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid: "Stmt1428341300017",
        Action: [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem"
        ],
        Effect: "Allow",
        Resource: [
          "arn:aws:dynamodb:*:*:table/VisitorCount"
        ]
      },
      {
        Sid: "",
        Action: [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect: "Allow",
        Resource: "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "my-lambda-dynamodb-policy-attachment" {
  role       = aws_iam_role.my-lambda-role.name
  policy_arn = aws_iam_policy.my-lambda-dynamodb-policy.arn
}

resource "aws_lambda_function" "my_iac_function" {
  function_name = "MyIacFunction"
  handler       = "lambda_function.handler"
  runtime       = "python3.12"
  role          = aws_iam_role.my-lambda-role.arn
  filename      = data.archive_file.zip.output_path
  source_code_hash = data.archive_file.zip.output_base64sha256

  environment {
    variables = {
      VISITOR_TABLE = "iac-counter"
    }
  }
}

data "archive_file" "zip" {
    type = "zip"
    source_dir = "${path.module}/lambda/"
    output_path = "${path.module}/myLambdaFunction.zip"
}



resource "aws_lambda_permission" "lambda_permission" {
  statement_id  = "AllowIacRestAPIInvoke"
  action        = "lambda:InvokeFunction"
  function_name = "MyIacFunction"
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.my-rest-api.execution_arn}/*"
}


resource "aws_api_gateway_resource" "my-resource" {
  parent_id   = aws_api_gateway_rest_api.my-rest-api.root_resource_id
  path_part   = "v1"
  rest_api_id = aws_api_gateway_rest_api.my-rest-api.id
}

resource "aws_api_gateway_method" "my-get-method" {
  authorization = "NONE"
  http_method   = "GET"
  resource_id   = aws_api_gateway_resource.my-resource.id
  rest_api_id   = aws_api_gateway_rest_api.my-rest-api.id
}

resource "aws_api_gateway_integration" "my-api-integration" {
  http_method = aws_api_gateway_method.my-get-method.http_method
  resource_id = aws_api_gateway_resource.my-resource.id
  rest_api_id = aws_api_gateway_rest_api.my-rest-api.id
  type        = "AWS_PROXY"
  integration_http_method = "GET"
  uri = aws_lambda_function.my_iac_function.invoke_arn
}


resource "aws_api_gateway_integration_response" "integration_response" {
  rest_api_id = aws_api_gateway_rest_api.my-rest-api.id
  resource_id = aws_api_gateway_resource.my-resource.id
  http_method = aws_api_gateway_method.my-get-method.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code

  response_templates = {
    "application/json" = "{}"
  }  
}

resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.my-rest-api.id
  resource_id = aws_api_gateway_resource.my-resource.id
  http_method = aws_api_gateway_method.my-get-method.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Content-Type" = true
  }
}

resource "aws_api_gateway_deployment" "my-api-deploy" {
  rest_api_id = aws_api_gateway_rest_api.my-rest-api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.my-resource.id,
      aws_api_gateway_method.my-get-method.id,
      aws_api_gateway_integration.my-api-integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "example" {
  deployment_id = aws_api_gateway_deployment.my-api-deploy.id
  rest_api_id   = aws_api_gateway_rest_api.my-rest-api.id
  stage_name    = "STAGE_EXAMPLE"
}