data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id      = data.aws_caller_identity.current.account_id
  region          = data.aws_region.current.region
  alb_prefix      = var.alb_log_prefix == "" ? "" : "${var.alb_log_prefix}/"
  bucket_names    = { waf = var.waf_bucket_name, alb = var.alb_bucket_name }
  bucket_arns     = { for key, name in local.bucket_names : key => "arn:aws:s3:::${name}" }
  log_prefixes    = { waf = "AWSLogs/${local.account_id}/WAFLogs/", alb = "${local.alb_prefix}AWSLogs/${local.account_id}/elasticloadbalancing/" }
  queue_arns      = { for source in ["waf", "alb"] : source => "arn:aws:sqs:${local.region}:${local.account_id}:${var.name}-${source}-events" }
  dlq_arns        = { for source in ["waf", "alb"] : source => "arn:aws:sqs:${local.region}:${local.account_id}:${var.name}-${source}-dead-letter" }
  delivery_source = "arn:aws:logs:${local.region}:${local.account_id}:*"
  common_tags     = merge(var.tags, { ManagedBy = "Terraform", Project = "runreveal-detection-as-code" })
}

resource "aws_s3_bucket" "logs" {
  for_each      = local.bucket_names
  bucket        = each.value
  force_destroy = false
  tags          = merge(local.common_tags, { Source = each.key })

  lifecycle {
    precondition {
      condition     = split(":", var.alb_arn)[3] == local.region && split(":", var.alb_arn)[4] == local.account_id
      error_message = "The existing ALB must be in the provider's account and region."
    }
    precondition {
      condition     = var.waf_web_acl_arn == null ? true : (split(":", var.waf_web_acl_arn)[3] == local.region && split(":", var.waf_web_acl_arn)[4] == local.account_id)
      error_message = "The WAF ACL must be in the provider's account and region."
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  for_each                = local.bucket_names
  bucket                  = aws_s3_bucket.logs[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  for_each = local.bucket_names
  bucket   = aws_s3_bucket.logs[each.key].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  for_each = local.bucket_names
  bucket   = aws_s3_bucket.logs[each.key].id
  rule {
    apply_server_side_encryption_by_default {
      # Legacy ALB S3 access logs support SSE-S3, not SSE-KMS.
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "logs" {
  for_each = local.bucket_names
  bucket   = aws_s3_bucket.logs[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  for_each = local.bucket_names
  bucket   = aws_s3_bucket.logs[each.key].id
  rule {
    id     = "bounded-log-retention"
    status = "Enabled"
    filter {}
    expiration {
      days = var.log_retention_days
    }
    noncurrent_version_expiration {
      noncurrent_days = var.log_retention_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
  depends_on = [aws_s3_bucket_versioning.logs]
}

resource "aws_s3_bucket_policy" "logs" {
  for_each = local.bucket_names
  bucket   = aws_s3_bucket.logs[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid       = "DenyNonTLSClients"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.bucket_arns[each.key], "${local.bucket_arns[each.key]}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false", "aws:PrincipalIsAWSService" = "false" } }
      }
      ], jsondecode(each.key == "waf" ? jsonencode([
        {
          Sid       = "AWSLogDeliveryWrite"
          Effect    = "Allow"
          Principal = { Service = "delivery.logs.amazonaws.com" }
          Action    = "s3:PutObject"
          Resource  = "${local.bucket_arns.waf}/AWSLogs/${local.account_id}/*"
          Condition = {
            StringEquals = { "aws:SourceAccount" = local.account_id, "s3:x-amz-acl" = "bucket-owner-full-control" }
            ArnLike      = { "aws:SourceArn" = local.delivery_source }
          }
        },
        {
          Sid       = "AWSLogDeliveryAclCheck"
          Effect    = "Allow"
          Principal = { Service = "delivery.logs.amazonaws.com" }
          Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
          Resource  = local.bucket_arns.waf
          Condition = {
            StringEquals = { "aws:SourceAccount" = local.account_id }
            ArnLike      = { "aws:SourceArn" = local.delivery_source }
          }
        }
        ]) : jsonencode([
        {
          Sid       = "ALBLogDeliveryWrite"
          Effect    = "Allow"
          Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
          Action    = "s3:PutObject"
          # Includes ELBAccessLogTestFile; notification filtering excludes that test file.
          Resource  = "${local.bucket_arns.alb}/${local.alb_prefix}AWSLogs/${local.account_id}/*"
          Condition = { ArnEquals = { "aws:SourceArn" = var.alb_arn } }
        }
    ])))
  })
  depends_on = [aws_s3_bucket_public_access_block.logs, aws_s3_bucket_ownership_controls.logs]
}

resource "aws_sqs_queue" "dead_letter" {
  for_each                  = local.bucket_names
  name                      = "${var.name}-${each.key}-dead-letter"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
  tags                      = local.common_tags
}

resource "aws_sqs_queue" "events" {
  for_each                   = local.bucket_names
  name                       = "${var.name}-${each.key}-events"
  message_retention_seconds  = 345600
  visibility_timeout_seconds = 300
  receive_wait_time_seconds  = 20
  sqs_managed_sse_enabled    = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dead_letter[each.key].arn
    maxReceiveCount     = 5
  })
  tags = local.common_tags
}

resource "aws_sqs_queue_redrive_allow_policy" "dead_letter" {
  for_each  = local.bucket_names
  queue_url = aws_sqs_queue.dead_letter[each.key].url
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.events[each.key].arn]
  })
}

resource "aws_sqs_queue_policy" "events" {
  for_each  = local.bucket_names
  queue_url = aws_sqs_queue.events[each.key].url
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowOnlyThisBucketToPublish"
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = local.queue_arns[each.key]
        Condition = {
          ArnEquals    = { "aws:SourceArn" = local.bucket_arns[each.key] }
          StringEquals = { "aws:SourceAccount" = local.account_id }
        }
      },
      {
        Sid       = "DenyNonTLSClients"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = local.queue_arns[each.key]
        Condition = { Bool = { "aws:SecureTransport" = "false", "aws:PrincipalIsAWSService" = "false" } }
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "logs" {
  for_each = local.bucket_names
  bucket   = aws_s3_bucket.logs[each.key].id
  queue {
    id            = "runreveal-${each.key}"
    queue_arn     = aws_sqs_queue.events[each.key].arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = local.log_prefixes[each.key]
    filter_suffix = ".log.gz"
  }
  depends_on = [aws_sqs_queue_policy.events]
}

resource "aws_iam_role" "reader" {
  for_each             = local.bucket_names
  name                 = "${var.name}-${each.key}-runreveal"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.runreveal_principal_arn }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "sts:ExternalId" = var.external_ids[each.key] } }
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "reader" {
  for_each = local.bucket_names
  name     = "read-${each.key}-logs-and-consume-events"
  role     = aws_iam_role.reader[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListThisBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [local.bucket_arns[each.key]]
      },
      {
        Sid      = "ReadOnlyThisLogPrefix"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${local.bucket_arns[each.key]}/${local.log_prefixes[each.key]}*"]
      },
      {
        Sid      = "ConsumeOnlyThisQueue"
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes"]
        Resource = [local.queue_arns[each.key]]
      }
    ]
  })
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  count                   = var.manage_waf_logging ? 1 : 0
  resource_arn            = var.waf_web_acl_arn
  log_destination_configs = [aws_s3_bucket.logs["waf"].arn]
  dynamic "redacted_fields" {
    for_each = var.waf_redacted_headers
    content {
      single_header { name = redacted_fields.value }
    }
  }
  depends_on = [aws_s3_bucket_policy.logs, aws_s3_bucket_notification.logs]
}
