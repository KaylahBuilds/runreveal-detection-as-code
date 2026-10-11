variable "name" {
  description = "Short unique deployment name used for queues and IAM roles."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,29}$", var.name))
    error_message = "Use 3-30 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "waf_bucket_name" {
  description = "New globally unique bucket, beginning aws-waf-logs-. This module owns its entire policy and notification configuration."
  type        = string
  validation {
    condition     = can(regex("^aws-waf-logs-[a-z0-9][a-z0-9-]*[a-z0-9]$", var.waf_bucket_name)) && length(var.waf_bucket_name) <= 63
    error_message = "Use a valid 15-63 character lowercase/hyphen S3 name beginning aws-waf-logs-."
  }
}

variable "alb_bucket_name" {
  description = "New globally unique bucket for legacy ALB S3 access logs. Must differ from the WAF bucket."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,61}[a-z0-9]$", var.alb_bucket_name)) && var.alb_bucket_name != var.waf_bucket_name
    error_message = "Use a distinct 3-63 character lowercase/hyphen S3 bucket name beginning with a letter."
  }
}

variable "alb_arn" {
  description = "Existing standard AWS Application Load Balancer ARN, in this provider's account and region. Does not alter that ALB."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:loadbalancer/app/[^/]+/[a-zA-Z0-9]+$", var.alb_arn))
    error_message = "Supply a commercial AWS application load balancer ARN, not an NLB, Classic or Outposts configuration."
  }
}

variable "alb_log_prefix" {
  description = "Prefix to configure on the existing ALB. Empty is allowed; AWSLogs is reserved by AWS."
  type        = string
  default     = "alb"
  validation {
    condition     = var.alb_log_prefix == "" || (can(regex("^[a-zA-Z0-9][a-zA-Z0-9/_-]*[a-zA-Z0-9]$|^[a-zA-Z0-9]$", var.alb_log_prefix)) && !strcontains(var.alb_log_prefix, "AWSLogs"))
    error_message = "Use a simple prefix without leading/trailing slashes or AWSLogs, or use an empty string."
  }
}

variable "runreveal_principal_arn" {
  description = "RunReveal's confirmed commercial AWS role or account-root ARN. No default: verify your SaaS/BYOC deployment's trust principal."
  type        = string
  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:(root|role/[A-Za-z0-9+=,.@_/-]+)$", var.runreveal_principal_arn))
    error_message = "Use the explicit RunReveal IAM role ARN or account-root ARN; wildcard principals are not allowed."
  }
}

variable "external_ids" {
  description = "Distinct, source-specific external IDs agreed with RunReveal; supply securely outside tracked files. They are written to IAM and Terraform state."
  type = object({
    waf = string
    alb = string
  })
  sensitive = true
  validation {
    condition     = alltrue([for id in values(var.external_ids) : can(regex("^[A-Za-z0-9+=,.@:/_-]{16,1224}$", id))]) && var.external_ids.waf != var.external_ids.alb
    error_message = "Provide distinct 16-1224 character external IDs for WAF and ALB, using STS ExternalId-compatible characters."
  }
}

variable "manage_waf_logging" {
  description = "Explicitly opt in to managing the existing WAF ACL's ONE logging configuration. Review/import any existing logging configuration first."
  type        = bool
  default     = false
  validation {
    condition     = !var.manage_waf_logging || var.waf_web_acl_arn != null
    error_message = "Enabling WAF logging ownership requires waf_web_acl_arn."
  }
}

variable "waf_web_acl_arn" {
  description = "Optional existing REGIONAL WAFv2 ACL ARN in this provider's account/region. CloudFront/global ACLs are deliberately unsupported."
  type        = string
  default     = null
  validation {
    condition     = var.waf_web_acl_arn == null ? true : can(regex("^arn:aws:wafv2:[a-z0-9-]+:[0-9]{12}:regional/webacl/[^/]+/[a-zA-Z0-9-]+$", var.waf_web_acl_arn))
    error_message = "Supply a commercial AWS REGIONAL WAFv2 web ACL ARN, or null."
  }
}

variable "waf_redacted_headers" {
  description = "Lowercase WAF log header names to redact. Redaction does not sanitize ALB logs or WAF sampled requests."
  type        = set(string)
  default     = ["authorization", "cookie"]
  validation {
    condition     = alltrue([for header in var.waf_redacted_headers : can(regex("^[a-z0-9-]+$", header))])
    error_message = "Use lowercase HTTP header names."
  }
}

variable "log_retention_days" {
  description = "S3 current/noncurrent log version expiration. Confirm organizational retention before changing."
  type        = number
  default     = 90
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3650 && floor(var.log_retention_days) == var.log_retention_days
    error_message = "Set an integer retention period from 1 to 3650 days."
  }
}

variable "tags" {
  description = "Non-sensitive AWS resource tags."
  type        = map(string)
  default     = {}
}
