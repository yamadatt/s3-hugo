terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.7.0"
    }
  }
}

provider "aws" {
  region     = "ap-northeast-1"
  default_tags {
    tags = {
      Owner    = "yamadatt"
      Resource = "terraform"
    }
  }
}


locals {
  bucket_name = "sococa-hugo"
}

resource "aws_s3_bucket" "sococa_hugo_bucket" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_website_configuration" "ars_img_website" {
  bucket = aws_s3_bucket.sococa_hugo_bucket.bucket
  index_document {
    suffix = "index.html"
  }
  error_document {
    key = "error.html"
  }
}


resource "aws_s3_bucket_policy" "policy" {
  depends_on = [
    aws_s3_bucket.sococa_hugo_bucket,
  ]
  bucket = aws_s3_bucket.sococa_hugo_bucket.id
  policy = data.aws_iam_policy_document.policy_document.json
}

data "aws_iam_policy_document" "policy_document" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = [
      "s3:GetObject",
    ]

    resources = [
      aws_s3_bucket.sococa_hugo_bucket.arn,
      "${aws_s3_bucket.sococa_hugo_bucket.arn}/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudfront_distribution.ars_img_cfront.arn]
    }
  }
}

resource "aws_cloudfront_distribution" "ars_img_cfront" {
  enabled = true
  default_root_object = "index.html"
  web_acl_id      = aws_wafv2_web_acl.web_acl.arn
 

 
  origin {
    origin_id                = aws_s3_bucket.sococa_hugo_bucket.id
    domain_name              = aws_s3_bucket.sococa_hugo_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.hugo_oac.id
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  default_cache_behavior {
    target_origin_id       = aws_s3_bucket.sococa_hugo_bucket.id
    viewer_protocol_policy = "redirect-to-https"
    cached_methods         = ["GET", "HEAD"]
    allowed_methods        = ["GET", "HEAD"]
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    # CloudFront Functionsの紐づけ
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.main.arn
    }

  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

resource "aws_cloudfront_origin_access_control" "hugo_oac" {
  name                              = aws_s3_bucket.sococa_hugo_bucket.bucket_domain_name
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

output "cfront_domain_name" {
  value = aws_cloudfront_distribution.ars_img_cfront.domain_name
  
}

# CloudFront Functions
resource "aws_cloudfront_function" "main" {
  name    = "function"
  runtime = "cloudfront-js-1.0"
  comment = "default directory index"
  publish = true
  code    = file("./CloudFront_Functions/function.js")
}


######## WAF

provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}

resource "aws_wafv2_ip_set" "admin-ips" {
  name = "admin-ip-set"
  scope = "CLOUDFRONT"
  provider = aws.virginia
  ip_address_version = "IPV4"
  addresses = ["133.203.185.64/32", "192.168.1.2/32"] // 指定したいIPをサブネット付きで書く
}


resource "aws_wafv2_web_acl" "web_acl" {
  provider    = aws.virginia
  name        = "only-myip"
  description = "A sample Web ACL that blocks all traffic except for a allow IP set"
  scope       = "CLOUDFRONT"
  default_action {
    block {}
  }

  rule {
    name     = "allow_ips_in_ip_set"
    priority = 1
    action {
      allow {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.admin-ips.arn
      }
    }

    visibility_config {
      sampled_requests_enabled   = false
      cloudwatch_metrics_enabled = false
      metric_name                = "sample"
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "sample_web_acl_metric"
    sampled_requests_enabled   = false
  }
}