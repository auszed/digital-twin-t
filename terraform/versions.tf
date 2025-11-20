terraform {
  # Specifies the minimum required version for Terraform CLI
  required_version = ">= 1.0"

  required_providers {
    # Defines the AWS provider source and version constraint
    aws = {
      source  = "hashicorp/aws" # The official source for the AWS provider
      version = "~> 6.0"        # Requires a version greater than or equal to 6.0 and less than 7.0 (e.g., 6.x)
    }
  }
}

# 1. Default AWS Provider Configuration
provider "aws" {
  profile = "default"
  # This block configures the default AWS provider.
  # Since no region or explicit credentials are provided, 
  # Terraform will typically use the configuration (credentials, region) 
  # set in your local environment (e.g., AWS CLI profile, environment variables).
}

# 2. Aliased AWS Provider Configuration
provider "aws" {
  alias  = "us_east_1" # Assigns a specific name (alias) to this provider instance
  region = "us-east-1" # Explicitly sets the AWS region for this provider instance
  profile = "default" # add the profile to use
  # Resources that need to be deployed in us-east-1 (or a different region 
  # from the default provider) must explicitly reference this alias 
  # using the 'provider = aws.us_east_1' argument.
}