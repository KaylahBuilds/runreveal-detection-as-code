# RunReveal AWS log-ingestion module

Reusable Terraform infrastructure for two RunReveal sources: regional AWS WAF logs and legacy Application Load Balancer S3 access logs. It creates AWS resources, **not RunReveal workspace objects**. After applying an approved plan, register the two sources with the documented RunReveal custom-SQS ingest method.

No unofficial `runreveal_source` resource, API token, provisioner or shell-based API call is hidden in this module. Provider versions are deliberate pins, updated through review.

## Resources and boundaries

| Component | Behavior |
| --- | --- |
| Two new S3 buckets | Source separation, public access blocked, bucket-owner enforced, SSE-S3, versioning, lifecycle rules, TLS required for clients. Existing buckets are not imported or merged automatically. |
| Two notification queues | Only the corresponding S3 bucket can publish; all object-created events under the expected account/log prefix and `.log.gz` suffix are included. |
| Two dead-letter queues | Encrypted; 14-day retention and redrive restricted to the matching event queue. Main queues retain events for four days, use a five-minute visibility timeout and redrive after five receives. |
| Two IAM reader roles | One verified RunReveal principal; a distinct required external ID per source. Bucket-scoped listing, log-prefix-scoped object reads, and consumption of only that source's queue. |
| Existing ALB | Never created, imported or modified. Outputs provide the `access_logs` values for its existing owner. |
| Existing WAF ACL | Logging untouched by default. Explicit `manage_waf_logging = true` manages its single logging configuration; requires a regional ACL ARN. |
| RunReveal | Manual source registration and connection verification. External IDs are not included in outputs. |

Commercial AWS, one account and one region per module instance. The ALB and WAF ACL must be in that account/region. This deliberately excludes Outposts, GovCloud, China, CloudFront/global WAF and centralized cross-account log delivery. Do not extrapolate their principals or bucket requirements from this example.

The buckets must be new and globally unique. Because this module owns the entire bucket policy and notification configuration, do not point it at shared buckets or add a second `aws_s3_bucket_notification` resource for the same bucket.

## Use

See [the runnable example](../../examples/aws-waf-alb/) and [the integration guide](../../docs/aws-ingestion.md). The module requires Terraform 1.9.8 or later and pins `hashicorp/aws` 6.68.0.

```hcl
module "runreveal_logs" {
  source = "../../modules/runreveal-aws-logs"

  name                   = "edge-security"
  waf_bucket_name        = var.waf_bucket_name
  alb_bucket_name        = var.alb_bucket_name
  alb_arn                = var.existing_alb_arn
  runreveal_principal_arn = var.verified_runreveal_principal_arn
  external_ids           = var.external_ids

  # A separate, reviewed change after checking ownership of existing logging.
  manage_waf_logging = false
}
```

`alb_arn` should be the existing ARN supplied as an input when the same ALB consumes this module's bucket output. Referencing `aws_lb.app.arn` and then feeding the module back into `aws_lb.app.access_logs` creates a dependency cycle. Do not recreate an ALB to solve that cycle.

## Inputs

| Input | Required/default | Purpose |
| --- | --- | --- |
| `name` | Required | Unique 3-30 character resource-name stem. |
| `waf_bucket_name` | Required | New bucket beginning `aws-waf-logs-`. |
| `alb_bucket_name` | Required | New, distinct bucket. |
| `alb_arn` | Required | Existing same-account/region application load balancer. |
| `runreveal_principal_arn` | Required | Exact principal confirmed for your RunReveal deployment; no vendor account assumed. |
| `external_ids` | Required, sensitive | Object with different `waf` and `alb` values. Agree these with RunReveal. |
| `alb_log_prefix` | `alb` | Existing ALB access-log prefix to configure. Empty supported; `AWSLogs` prohibited. |
| `manage_waf_logging` | `false` | Deliberate opt-in to ownership of the ACL's single logging configuration. |
| `waf_web_acl_arn` | `null` | Existing regional ACL; required for opt-in. |
| `waf_redacted_headers` | `authorization`, `cookie` | Header redaction for module-managed WAF logging only. |
| `log_retention_days` | `90` | Current-version expiration and subsequent noncurrent-version expiration. |
| `tags` | `{}` | Non-sensitive metadata. |

**Retention is not a hard 90-day erasure guarantee.** With versioning, a current object expires after 90 days; the resulting noncurrent version may remain for another 90 days. Lifecycle processing is asynchronous. Set retention according to policy and account for both periods and delete markers. This is not immutable/WORM evidence storage.

External IDs are a confused-deputy control, not a substitute for authenticating the RunReveal principal. Marking them `sensitive` hides routine Terraform display; IAM policies and state still contain them. Keep state and plans in a protected, encrypted, access-controlled backend outside Git. Do not publish `terraform output -json`, state, plans or operational logs as CI artifacts.

## Outputs

- `runreveal_sources`: per-source name/type, bucket, log prefix, queue URL/region, reader role ARN and dead-letter queue URL.
- `alb_access_logs`: `bucket`, `prefix`, `enabled` for the existing ALB's owner.
- `waf_log_destination_arn`: destination for a separately managed WAF logging configuration.
- `waf_logging_managed`: confirms whether the module owns WAF logging.

SQS consumer access includes `ReceiveMessage`, `DeleteMessage`, `ChangeMessageVisibility` and `GetQueueAttributes`, scoped to one queue. RunReveal's documented minimum is receive/delete; visibility and metadata operations support normal SQS consumer behavior. No SQS send/purge or S3 write/delete is granted to the reader. Listing is bucket-scoped without a prefix condition so source discovery can list; object reads remain prefix-scoped.

## Checks

```sh
terraform fmt -check -recursive
terraform -chdir=modules/runreveal-aws-logs init -backend=false
terraform -chdir=modules/runreveal-aws-logs validate
terraform -chdir=modules/runreveal-aws-logs test
terraform -chdir=examples/aws-waf-alb init -backend=false
terraform -chdir=examples/aws-waf-alb validate
```

The commands above assume the repository root. `terraform test` uses mock providers and plan-only runs. It does not prove AWS delivery, role assumption, RunReveal parsing, queue processing or alert quality. Those require the staging checklist in the integration guide. No `apply` is run by repository validation.
