variable "aws_region" {
  description = "Same AWS region as the existing ALB and regional WAF ACL."
  type        = string
  default     = "us-east-1"
}
variable "aws_account_id" {
  description = "Explicit deployment account guardrail; provider refuses other accounts."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Provide a 12-digit deployment account ID."
  }
}
variable "name" {
  type    = string
  default = "runreveal-edge"
}
variable "waf_bucket_name" { type = string }
variable "alb_bucket_name" { type = string }
variable "alb_arn" { type = string }
variable "runreveal_principal_arn" { type = string }
variable "external_ids" {
  type      = object({ waf = string, alb = string })
  sensitive = true
}
variable "manage_waf_logging" {
  type    = bool
  default = false
}
variable "waf_web_acl_arn" {
  type    = string
  default = null
}
variable "log_retention_days" {
  type    = number
  default = 90
}
