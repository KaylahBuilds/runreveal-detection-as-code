output "runreveal_sources" {
  description = "Non-secret handoff for two RunReveal sources. Choose AWS S3 Bucket with custom SQS and IAM role authentication; configure the matching external ID securely in RunReveal."
  value = {
    for key in ["waf", "alb"] : key => {
      source_name           = "${var.name}-${key}"
      source_type           = key == "waf" ? "aws-waf" : "alb"
      ingest_method         = "AWS S3 Bucket with custom SQS"
      bucket_name           = aws_s3_bucket.logs[key].id
      log_prefix            = local.log_prefixes[key]
      queue_url             = aws_sqs_queue.events[key].url
      queue_region          = local.region
      role_arn              = aws_iam_role.reader[key].arn
      dead_letter_queue_url = aws_sqs_queue.dead_letter[key].url
    }
  }
  depends_on = [aws_iam_role_policy.reader, aws_sqs_queue_policy.events, aws_s3_bucket_notification.logs]
}

output "alb_access_logs" {
  description = "Merge this into the existing ALB resource's access_logs block. This module never creates or modifies your load balancer."
  value = {
    bucket  = aws_s3_bucket.logs["alb"].id
    prefix  = var.alb_log_prefix
    enabled = true
  }
  depends_on = [aws_s3_bucket_policy.logs, aws_s3_bucket_notification.logs]
}

output "waf_log_destination_arn" {
  description = "WAF destination for an externally managed logging configuration; only manage it in ONE state."
  value       = aws_s3_bucket.logs["waf"].arn
  depends_on  = [aws_s3_bucket_policy.logs, aws_s3_bucket_notification.logs]
}

output "waf_logging_managed" {
  description = "Whether this module owns the WAF logging configuration."
  value       = var.manage_waf_logging
}
