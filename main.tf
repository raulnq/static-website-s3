terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.31.0"
    }
  }
  backend "local" {}
}

provider "aws" {
  region      = "<MY_REGION>"
  profile     = "<MY_AWS_PROFILE>"
  max_retries = 2
}

locals {
  bucket_name             = "<MY_BUCKET_NAME>"
  zone_id                 = "<MY_ROUTE53_HOSTED_ZONE_ID>"
}

data "aws_route53_zone" "zone" {
  zone_id      = local.zone_id
  private_zone = false
}

resource "aws_s3_bucket" "bucket" {
  bucket        = "${local.bucket_name}.${data.aws_route53_zone.zone.name}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "bucket-access-block" {
  bucket                  = aws_s3_bucket.bucket.id
  ignore_public_acls      = false
  block_public_acls       = false
  restrict_public_buckets = false
  block_public_policy     = false
}

resource "aws_s3_bucket_website_configuration" "website-config" {
  bucket = aws_s3_bucket.bucket.id
  index_document {
    suffix = "index.html"
  }
}

data "aws_iam_policy_document" "bucket-policy-document" {
  statement {
    sid    = "AllowPublicRead"
    effect = "Allow"
    resources = [
      "${aws_s3_bucket.bucket.arn}/*",
    ]
    actions = ["S3:GetObject"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_bucket_policy" "bucket-policy" {
  bucket = aws_s3_bucket.bucket.id
  policy = data.aws_iam_policy_document.bucket-policy-document.json
}

resource "aws_route53_record" "record" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = "${local.bucket_name}.${data.aws_route53_zone.zone.name}"
  type    = "A"

  alias {
    name                   = aws_s3_bucket_website_configuration.website-config.website_domain
    zone_id                = aws_s3_bucket.bucket.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_s3_object" "html-files" {
  for_each = fileset("./site/", "*.html")
  bucket = aws_s3_bucket.bucket.id
  key = each.value
  content_type    = "text/html"
  source = "./site/${each.value}"
  etag = filemd5("./site/${each.value}")
}

output "website_endpoint" {
  value = aws_s3_bucket_website_configuration.website-config.website_endpoint
}

output "route53_name" {
  value = aws_route53_record.record.name
}