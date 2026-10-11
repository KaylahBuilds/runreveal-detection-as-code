terraform {
  required_version = ">= 1.9.8, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.68.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  # Use your SSO session or short-lived workload credentials; never hard-code keys.
  allowed_account_ids = [var.aws_account_id]
}

module "runreveal_logs" {
  source = "../../modules/runreveal-aws-logs"

  name                    = var.name
  waf_bucket_name         = var.waf_bucket_name
  alb_bucket_name         = var.alb_bucket_name
  alb_arn                 = var.alb_arn
  runreveal_principal_arn = var.runreveal_principal_arn
  external_ids            = var.external_ids
  manage_waf_logging      = var.manage_waf_logging
  waf_web_acl_arn         = var.waf_web_acl_arn
  log_retention_days      = var.log_retention_days
  tags                    = { Environment = "sandbox", Owner = "security-engineering" }
}

output "runreveal_sources" {
  value = module.runreveal_logs.runreveal_sources
}

output "alb_access_logs" {
  value = module.runreveal_logs.alb_access_logs
}

output "waf_log_destination_arn" {
  value = module.runreveal_logs.waf_log_destination_arn
}
