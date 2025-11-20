# Defines input parameters (variables) for the Terraform configuration.
# This allows the configuration to be reused easily across different environments or projects.

# --- Core Application Variables ---

variable "project_name" {
  description = "Name prefix for all resources (e.g., my-app-service)"
  type        = string
  
  # Validation block ensures the variable input meets specific requirements.
  validation {
    # 'can(regex(...))' checks if the value matches the pattern: 
    # start (^) -> lowercase letters, numbers, or hyphens ([a-z0-9-]+) -> end ($)
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, test, prod)"
  type        = string
  
  # Validation block restricts the environment name to a specific set of values.
  validation {
    # 'contains()' checks if the value is one of the items in the list.
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, prod."
  }
}

# --- AWS Service Configuration Variables ---

variable "bedrock_model_id" {
  description = "The specific AWS Bedrock model ID to be used (e.g., for an LLM)"
  type        = string
  # Provides a default model ID if the user doesn't specify one.
  default     = "amazon.nova-micro-v1:0" 
}

variable "lambda_timeout" {
  description = "Timeout for the AWS Lambda function in seconds"
  type        = number
  # Default set to 60 seconds, which is often necessary for tasks involving LLMs.
  default     = 60
}

# --- API Gateway Throttling Variables ---

variable "api_throttle_burst_limit" {
  description = "API Gateway throttle burst limit (maximum concurrent requests allowed in a short period)"
  type        = number
  default     = 10
}

variable "api_throttle_rate_limit" {
  description = "API Gateway throttle rate limit (steady-state average requests per second)"
  type        = number
  default     = 5
}

# --- Custom Domain Variables (Optional) ---

variable "use_custom_domain" {
  description = "Boolean flag: set to true to attach a custom domain (via CloudFront/API Gateway)"
  type        = bool
  # Default is false, skipping the domain setup unless explicitly enabled.
  default     = false
}

variable "root_domain" {
  description = "The apex domain name (e.g., mydomain.com). Required if use_custom_domain is true."
  type        = string
  # Empty string default; the value only matters if use_custom_domain is true.
  default     = ""
}