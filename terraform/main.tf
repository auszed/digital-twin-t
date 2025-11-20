# Data source to get current AWS account ID
data "aws_caller_identity" "current" {} # Retrieves the AWS Account ID of the user executing Terraform.
                                        # This is used to create unique bucket names globally.

locals {
  # Conditional block to define domain aliases for CloudFront.
  # If 'use_custom_domain' is true AND 'root_domain' is not empty, it includes the root domain and 'www' subdomain.
  aliases = var.use_custom_domain && var.root_domain != "" ? [
    var.root_domain,
    "www.${var.root_domain}"
  ] : [] # Otherwise, the list of aliases is empty.

  # Creates a standard prefix for most resources (e.g., my-app-dev).
  name_prefix = "${var.project_name}-${var.environment}"

  # Standard set of tags applied to most resources for cost tracking and organization.
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# --- S3 Bucket for Conversation Memory (Backend State) ---

resource "aws_s3_bucket" "memory" {
  # Bucket name structure: [prefix]-memory-[account_id] to ensure global uniqueness.
  bucket = "${local.name_prefix}-memory-${data.aws_caller_identity.current.account_id}"
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "memory" {
  bucket = aws_s3_bucket.memory.id

  # All settings are set to true to ensure this sensitive data bucket is completely private.
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "memory" {
  bucket = aws_s3_bucket.memory.id

  rule {
    # Ensures the bucket owner (the account) has full control over objects.
    object_ownership = "BucketOwnerEnforced"
  }
}

# --- S3 Bucket for Frontend Static Website (Public Access) ---

resource "aws_s3_bucket" "frontend" {
  # Bucket name structure: [prefix]-frontend-[account_id]
  bucket = "${local.name_prefix}-frontend-${data.aws_caller_identity.current.account_id}"
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  # All settings are set to false to allow the bucket to serve content publicly via its policy.
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  # Defines the default file to serve when accessing the root of the bucket.
  index_document {
    suffix = "index.html"
  }

  # Defines the file to serve on a 404 error.
  error_document {
    key = "404.html"
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  # Defines a policy to allow anonymous users (Principal: "*") to read (s3:GetObject) all files.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        # Applies to all objects within the bucket.
        Resource  = "${aws_s3_bucket.frontend.arn}/*" 
      },
    ]
  })

  # Ensures the Public Access Block resource is created before setting this policy.
  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

# --- IAM Role and Policies for AWS Lambda ---

resource "aws_iam_role" "lambda_role" {
  name = "${local.name_prefix}-lambda-role"
  tags = local.common_tags

  # Trust policy: allows the Lambda service to assume this role.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

# Attaches standard policy for writing logs to CloudWatch.
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

# Attaches policy to allow the Lambda to interact with Amazon Bedrock (for LLM calls).
resource "aws_iam_role_policy_attachment" "lambda_bedrock" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
  role       = aws_iam_role.lambda_role.name
}

# Attaches policy to allow the Lambda to read/write from the memory S3 bucket.
resource "aws_iam_role_policy_attachment" "lambda_s3" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.lambda_role.name
}

# --- AWS Lambda Function Definition ---

resource "aws_lambda_function" "api" {
  # Specifies the location of the deployment package (ZIP file) containing the code.
  filename         = "${path.module}/../backend/lambda-deployment.zip"
  function_name    = "${local.name_prefix}-api"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_handler.handler" # The file and function within the ZIP to execute.
  # A hash of the file content ensures Lambda is redeployed if the code changes.
  source_code_hash = filebase64sha256("${path.module}/../backend/lambda-deployment.zip")
  runtime          = "python3.12"
  architectures    = ["x86_64"]
  timeout          = var.lambda_timeout # Uses the variable to set the execution timeout.
  tags             = local.common_tags

  # Environment variables passed to the Lambda runtime.
  environment {
    variables = {
      # CORS origins are set conditionally based on whether a custom domain is used.
      CORS_ORIGINS     = var.use_custom_domain ? "https://${var.root_domain},https://www.${var.root_domain}" : "https://${aws_cloudfront_distribution.main.domain_name}"
      S3_BUCKET        = aws_s3_bucket.memory.id
      USE_S3           = "true"
      BEDROCK_MODEL_ID = var.bedrock_model_id
    }
  }

  # Ensures the Lambda configuration has access to the CloudFront domain name 
  # for the CORS_ORIGINS variable.
  depends_on = [aws_cloudfront_distribution.main]
}

# --- API Gateway HTTP API Setup ---

resource "aws_apigatewayv2_api" "main" {
  name          = "${local.name_prefix}-api-gateway"
  protocol_type = "HTTP" # Uses the cheaper, simpler HTTP API type.
  tags          = local.common_tags

  cors_configuration {
    allow_credentials = false
    allow_headers     = ["*"]
    allow_methods     = ["GET", "POST", "OPTIONS"]
    # Allows all origins for development, will be restricted by Lambda env var in practice.
    allow_origins     = ["*"] 
    max_age           = 300
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default" # The default stage is the root path (/).
  auto_deploy = true
  tags        = local.common_tags

  default_route_settings {
    # Applies throttling limits using input variables.
    throttling_burst_limit = var.api_throttle_burst_limit 
    throttling_rate_limit  = var.api_throttle_rate_limit
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id           = aws_apigatewayv2_api.main.id
  integration_type = "AWS_PROXY" # Passes the entire request to Lambda.
  integration_uri  = aws_lambda_function.api.invoke_arn # The ARN required to invoke the Lambda.
}

# API Gateway Routes: Maps HTTP paths to the Lambda integration.
resource "aws_apigatewayv2_route" "get_root" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "post_chat" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /chat" # Main endpoint for chat interactions.
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "get_health" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /health" # Endpoint for health checks.
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# Lambda permission: Grants API Gateway the authority to invoke the Lambda function.
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  # Source ARN restricts permission to only this specific API Gateway instance.
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*" 
}

# --- CloudFront Distribution (CDN) ---

resource "aws_cloudfront_distribution" "main" {
  # Uses the conditional list of aliases defined in the locals block.
  aliases = local.aliases
  
  viewer_certificate {
    # Uses ACM certificate only if a custom domain is enabled, otherwise uses the default CloudFront certificate.
    acm_certificate_arn            = var.use_custom_domain ? aws_acm_certificate.site[0].arn : null
    cloudfront_default_certificate = var.use_custom_domain ? false : true
    ssl_support_method             = var.use_custom_domain ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  origin {
    # The origin is the public S3 website endpoint.
    domain_name = aws_s3_bucket_website_configuration.frontend.website_endpoint
    origin_id   = "S3-${aws_s3_bucket.frontend.id}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      # S3 website endpoints only support HTTP, so CloudFront connects via HTTP.
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html" # File to return when root is requested.
  tags                = local.common_tags

  default_cache_behavior {
    # Allows all HTTP methods to reach the origin, essential for the API.
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.frontend.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    # Redirects all HTTP requests to HTTPS for security.
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none" # No geographic restrictions.
    }
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    # On a 404, returns index.html. This is crucial for single-page applications (SPAs).
    response_page_path = "/index.html" 
  }
}

# --- Optional: Custom Domain Configuration (Route 53 & ACM) ---

# Data source to find the Route 53 hosted zone for the root domain.
data "aws_route53_zone" "root" {
  # 'count = 1' if custom domain is enabled, 'count = 0' if disabled (resource is skipped).
  count        = var.use_custom_domain ? 1 : 0 
  name         = var.root_domain
  private_zone = false
}

# ACM Certificate: Required for CloudFront to serve HTTPS traffic over a custom domain.
resource "aws_acm_certificate" "site" {
  count                     = var.use_custom_domain ? 1 : 0
  # ACM certificates for CloudFront must be provisioned in the 'us-east-1' region.
  provider                  = aws.us_east_1 
  domain_name               = var.root_domain
  subject_alternative_names = ["www.${var.root_domain}"]
  validation_method         = "DNS"
  lifecycle { create_before_destroy = true }
  tags = local.common_tags
}

# Route 53 Records for ACM validation (proves ownership of the domain).
resource "aws_route53_record" "site_validation" {
  # 'for_each' loop creates validation records required by the ACM certificate.
  for_each = var.use_custom_domain ? {
    for dvo in aws_acm_certificate.site[0].domain_validation_options :
    dvo.domain_name => dvo
  } : {}

  zone_id = data.aws_route53_zone.root[0].zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  ttl     = 300
  records = [each.value.resource_record_value]
}

# Finalizes the ACM certificate validation process after the R53 records are created.
resource "aws_acm_certificate_validation" "site" {
  count           = var.use_custom_domain ? 1 : 0
  provider        = aws.us_east_1
  certificate_arn = aws_acm_certificate.site[0].arn
  validation_record_fqdns = [
    for r in aws_route53_record.site_validation : r.fqdn
  ]
}

# Route 53 A and AAAA (IPv6) alias records pointing the root domain to CloudFront.
resource "aws_route53_record" "alias_root" {
  count   = var.use_custom_domain ? 1 : 0
  zone_id = data.aws_route53_zone.root[0].zone_id
  name    = var.root_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "alias_root_ipv6" {
  count   = var.use_custom_domain ? 1 : 0
  zone_id = data.aws_route53_zone.root[0].zone_id
  name    = var.root_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

# Route 53 A and AAAA (IPv6) alias records pointing the 'www' subdomain to CloudFront.
resource "aws_route53_record" "alias_www" {
  count   = var.use_custom_domain ? 1 : 0
  zone_id = data.aws_route53_zone.root[0].zone_id
  name    = "www.${var.root_domain}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "alias_www_ipv6" {
  count   = var.use_custom_domain ? 1 : 0
  zone_id = data.aws_route53_zone.root[0].zone_id
  name    = "www.${var.root_domain}"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}