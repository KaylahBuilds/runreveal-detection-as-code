# Mocked plans only: no credentials, cloud API calls or real resources.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
}

variables {
  name                    = "runreveal-test"
  waf_bucket_name         = "aws-waf-logs-runreveal-test-unique"
  alb_bucket_name         = "runreveal-alb-test-unique"
  alb_arn                 = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/example/0123456789abcdef"
  runreveal_principal_arn = "arn:aws:iam::111122223333:root"
  external_ids            = { waf = "fixture-only-waf-external-id", alb = "fixture-only-alb-external-id" }
}

run "secure_default_plan" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket.logs) == 2 && aws_s3_bucket.logs["waf"].bucket != aws_s3_bucket.logs["alb"].bucket
    error_message = "Source types need independent buckets."
  }
  assert {
    condition     = alltrue([for config in aws_s3_bucket_public_access_block.logs : config.block_public_acls && config.block_public_policy && config.ignore_public_acls && config.restrict_public_buckets])
    error_message = "Every bucket must block public access."
  }
  assert {
    condition     = alltrue([for config in aws_s3_bucket_server_side_encryption_configuration.logs : one(config.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"])
    error_message = "SSE-S3 must be configured for both buckets, including ALB compatibility."
  }
  assert {
    condition     = alltrue([for config in aws_s3_bucket_ownership_controls.logs : one(config.rule).object_ownership == "BucketOwnerEnforced"])
    error_message = "Bucket owner must own all objects."
  }
  assert {
    condition     = alltrue([for bucket in aws_s3_bucket.logs : bucket.force_destroy == false])
    error_message = "Destroy must not silently empty log buckets."
  }
  assert {
    condition     = length(aws_wafv2_web_acl_logging_configuration.this) == 0 && !output.waf_logging_managed
    error_message = "Default must not take over existing WAF logging."
  }
  assert {
    condition     = alltrue([for queue in aws_sqs_queue.events : queue.sqs_managed_sse_enabled && queue.message_retention_seconds == 345600 && queue.visibility_timeout_seconds == 300])
    error_message = "Queue encryption, retention and visibility defaults must remain explicit."
  }
  assert {
    condition     = alltrue([for queue in aws_sqs_queue.dead_letter : queue.sqs_managed_sse_enabled && queue.message_retention_seconds == 1209600])
    error_message = "Dead letters require encrypted queues with longer retention."
  }
  assert {
    condition     = alltrue([for source, role in aws_iam_role.reader : jsondecode(role.assume_role_policy).Statement[0].Principal.AWS == var.runreveal_principal_arn && jsondecode(role.assume_role_policy).Statement[0].Condition.StringEquals["sts:ExternalId"] == var.external_ids[source]])
    error_message = "Each role must require its exact external ID from the verified principal."
  }
  assert {
    condition     = jsondecode(aws_iam_role_policy.reader["waf"].policy).Statement[1].Resource[0] == "arn:aws:s3:::aws-waf-logs-runreveal-test-unique/AWSLogs/123456789012/WAFLogs/*"
    error_message = "WAF reader must not read unrelated objects."
  }
  assert {
    condition     = jsondecode(aws_iam_role_policy.reader["alb"].policy).Statement[1].Resource[0] == "arn:aws:s3:::runreveal-alb-test-unique/alb/AWSLogs/123456789012/elasticloadbalancing/*"
    error_message = "ALB reader must not read unrelated objects."
  }
  assert {
    condition     = jsondecode(aws_iam_role_policy.reader["alb"].policy).Statement[2].Resource[0] == "arn:aws:sqs:us-east-1:123456789012:runreveal-test-alb-events"
    error_message = "ALB reader must consume only its source queue."
  }
  assert {
    condition     = jsondecode(aws_sqs_queue_policy.events["waf"].policy).Statement[0].Action == "sqs:SendMessage" && jsondecode(aws_sqs_queue_policy.events["waf"].policy).Statement[0].Condition.ArnEquals["aws:SourceArn"] == "arn:aws:s3:::aws-waf-logs-runreveal-test-unique" && jsondecode(aws_sqs_queue_policy.events["waf"].policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    error_message = "S3 queue delivery must be constrained to its exact bucket and account."
  }
  assert {
    condition     = jsondecode(aws_s3_bucket_policy.logs["alb"].policy).Statement[1].Condition.ArnEquals["aws:SourceArn"] == var.alb_arn
    error_message = "ALB bucket writes must be scoped to the selected ALB."
  }
  assert {
    condition     = jsondecode(aws_s3_bucket_policy.logs["waf"].policy).Statement[1].Condition.StringEquals["aws:SourceAccount"] == "123456789012" && jsondecode(aws_s3_bucket_policy.logs["waf"].policy).Statement[1].Condition.ArnLike["aws:SourceArn"] == "arn:aws:logs:us-east-1:123456789012:*"
    error_message = "WAF log delivery needs account and regional source constraints."
  }
  assert {
    condition     = alltrue([for notification in aws_s3_bucket_notification.logs : one(notification.queue).filter_suffix == ".log.gz" && contains(one(notification.queue).events, "s3:ObjectCreated:*")])
    error_message = "Notify all object-create variants for compressed log files, not ALB test objects."
  }
  assert {
    condition     = alltrue([for policy in aws_s3_bucket_policy.logs : jsondecode(policy.policy).Statement[0].Effect == "Deny" && jsondecode(policy.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false"])
    error_message = "Bucket client traffic must use TLS."
  }
}

run "empty_alb_prefix" {
  command = plan
  variables { alb_log_prefix = "" }
  assert {
    condition     = one(aws_s3_bucket_notification.logs["alb"].queue).filter_prefix == "AWSLogs/123456789012/elasticloadbalancing/"
    error_message = "Empty prefixes must not introduce a leading slash."
  }
}

run "waf_opt_in_and_retention" {
  command = plan
  variables {
    manage_waf_logging = true
    waf_web_acl_arn    = "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/example/00000000-0000-0000-0000-000000000001"
    log_retention_days = 30
  }
  assert {
    condition     = length(aws_wafv2_web_acl_logging_configuration.this) == 1 && aws_wafv2_web_acl_logging_configuration.this[0].resource_arn == var.waf_web_acl_arn
    error_message = "Opt-in must configure only the supplied ACL."
  }
  assert {
    condition     = length(aws_wafv2_web_acl_logging_configuration.this[0].redacted_fields) == 2
    error_message = "Default WAF redaction must cover authorization and cookie headers."
  }
  assert {
    condition     = alltrue([for config in aws_s3_bucket_lifecycle_configuration.logs : one(config.rule).expiration[0].days == 30 && one(config.rule).noncurrent_version_expiration[0].noncurrent_days == 30])
    error_message = "Configured retention must cover current and noncurrent versions."
  }
}

run "reject_shared_external_ids" {
  command = plan
  variables { external_ids = { waf = "fixture-shared-external-id", alb = "fixture-shared-external-id" } }
  expect_failures = [var.external_ids]
}

run "reject_short_external_ids" {
  command = plan
  variables { external_ids = { waf = "short", alb = "other" } }
  expect_failures = [var.external_ids]
}

run "reject_waf_bucket_without_prefix" {
  command = plan
  variables { waf_bucket_name = "wrong-waf-bucket-name" }
  expect_failures = [var.waf_bucket_name]
}

run "reject_reserved_alb_prefix" {
  command = plan
  variables { alb_log_prefix = "logs/AWSLogs" }
  expect_failures = [var.alb_log_prefix]
}

run "reject_waf_takeover_without_arn" {
  command = plan
  variables { manage_waf_logging = true }
  expect_failures = [var.manage_waf_logging]
}

run "reject_cloudfront_acl" {
  command = plan
  variables { waf_web_acl_arn = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/example/00000000-0000-0000-0000-000000000001" }
  expect_failures = [var.waf_web_acl_arn]
}

run "reject_other_alb_region" {
  command = plan
  variables { alb_arn = "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/example/0123456789abcdef" }
  expect_failures = [aws_s3_bucket.logs]
}

run "reject_other_alb_account" {
  command = plan
  variables { alb_arn = "arn:aws:elasticloadbalancing:us-east-1:444455556666:loadbalancer/app/example/0123456789abcdef" }
  expect_failures = [aws_s3_bucket.logs]
}

run "reject_wildcard_trust" {
  command = plan
  variables { runreveal_principal_arn = "*" }
  expect_failures = [var.runreveal_principal_arn]
}
