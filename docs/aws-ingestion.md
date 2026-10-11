# AWS edge logs: provision, connect, prove

This example provisions the AWS ingestion path and intentionally leaves RunReveal workspace registration as an explicit handoff. An official RunReveal Terraform source resource was not verified for this implementation, so no provider name or source schema is invented. The AWS resources are real `hashicorp/aws` resources.

## Data path

```text
Existing regional WAF ACL -> WAF S3 bucket -> WAF event queue -> RunReveal WAF source
Existing ALB             -> ALB S3 bucket -> ALB event queue -> RunReveal ALB source
                                |                 |
                       bounded retention     per-source DLQ
```

There is one reader role and external ID per source. RunReveal assumes that role, consumes S3 object notifications and retrieves the referenced object. The module grants no access to other buckets or queue consumers. Notifications only match the relevant `AWSLogs/<account>/...` path and `.log.gz` files; the ALB access-log permission check file is not treated as traffic.

We deliberately use two buckets and the **AWS S3 Bucket with custom SQS** ingestion option. This makes source ownership and permissions easy to inspect. A shared datalake can be supported with separately routed queues, but it is not what this module implements. It also avoids changing notification settings on existing production buckets.

## 1. Plan AWS resources without assuming logging ownership

Start with [examples/aws-waf-alb](../examples/aws-waf-alb/). The provider is pinned, the deployment account is explicitly allow-listed, and WAF logging ownership is off by default. Review the plan with an identity authorized to create S3/SQS/IAM infrastructure in a sandbox. Use an encrypted, locked, access-controlled state backend; never commit state, saved plans, credentials or customer logs.

The example uses standard same-account, same-region ALB and REGIONAL WAF resources. It is not a CloudFront, Outposts, multi-account or other-partition recipe. Use short-lived AWS credentials rather than access keys in Terraform variables.

The WAF bucket starts with `aws-waf-logs-`. Both buckets use SSE-S3; this preserves compatibility with the legacy ALB S3 logging path. AWS also offers newer CloudWatch-based ALB logging, which is outside this example. No KMS key or decryption grant is implied by this design.

## 2. Enable logs in the existing resource owners

### ALB

Merge the following into the **existing** `aws_lb` resource in its owning stack. Do not create a second resource for a live ALB or overwrite unrelated attributes:

```hcl
# Inside your existing resource "aws_lb" "app" { ... }
access_logs {
  bucket  = module.runreveal_logs.alb_access_logs.bucket
  prefix  = module.runreveal_logs.alb_access_logs.prefix
  enabled = module.runreveal_logs.alb_access_logs.enabled
}
```

Supply the module's `alb_arn` as the known existing ARN input. Referencing this same resource's ARN as input while consuming the module's outputs creates a dependency cycle. If the ALB belongs to a different state, pass reviewed outputs through your existing infrastructure handoff, keeping its ARN an explicit input.

Review any existing log destination before changing it. If another team consumes the old destination, agree on migration and retention first. The bucket policy scopes writes to this specific ALB and its account path. After configuring logging, verify an actual compressed traffic log, not only `ELBAccessLogTestFile`.

### WAF

Choose one owner for the ACL's single logging configuration:

- Keep the ACL's existing logging stack in charge and use `waf_log_destination_arn` as its destination; leave `manage_waf_logging = false`.
- Or, after a reviewed ownership migration/import, supply the regional ACL ARN and set `manage_waf_logging = true`.

Do not apply both. Enabling the option against an already-configured ACL can replace its log destination. Removing the option after the resource is managed plans to disable that logging configuration; it is not a harmless pause switch.

Module-managed WAF logging redacts authorization and cookie headers. It does **not** sanitize ALB URLs, every WAF field, or WAF sampled requests. Request paths/query strings can expose private data. Define redaction, consent, retention and access controls before sending production traffic. Where required, separately review WAF sampling/data-protection controls and application handling of sensitive URLs.

## 3. Register two RunReveal sources

1. Confirm that your RunReveal plan/deployment supports AWS WAF and AWS ALB sources.
2. In RunReveal, connect an **AWS WAF** source and select **AWS S3 Bucket with custom SQS**.
3. Choose IAM role authentication. From `runreveal_sources.waf`, enter the queue URL, queue region and role ARN. Provide the exact WAF external ID through your protected configuration process.
4. Repeat with **AWS ALB**, using the ALB queue, reader role and different external ID.
5. Verify both sources. Match the trust principal to your actual SaaS or BYOC/BYODB deployment rather than copying a vendor account number without checking.

The output is a human-readable handoff, not a claimed RunReveal API request schema. Do not paste AWS credentials into these fields. If verification needs a permission not listed by the documented integration, inspect the specific denial and vendor guidance; do not attach administrative access or wildcard bucket permissions to make it pass.

## 4. Staging acceptance checklist

- [ ] Confirm each intended bucket receives genuine, fresh, compressed logs from the corresponding resource.
- [ ] Confirm WAF blocked **and allowed** traffic is represented; do not inadvertently filter out useful baselines.
- [ ] Confirm ALB access-log test objects are excluded from notifications, but traffic objects are included.
- [ ] Verify role assumption with the correct external ID; the wrong external ID must fail in a controlled test.
- [ ] Verify each source role cannot read the other source's bucket or consume its queue.
- [ ] Confirm RunReveal connects, consumes events and parses known requests into the expected source. Compare source timestamps with ingestion time.
- [ ] Observe notification retries/duplicates and check that detection windows/deduplication do not create avoidable duplicate incidents.
- [ ] Confirm queue age/backlog and dead-letter alerts reach an owned destination. The module provides DLQs, not a staffed monitoring service or alarm destination.
- [ ] Test a controlled broken-ingestion condition in staging and prove it becomes visible. Silence is not proof that there were no attacks.
- [ ] Review what happens during a four-day queue retention outage, log lifecycle expiry and RunReveal downtime. Document a bounded backfill procedure before it is needed.
- [ ] Confirm expected fields and values using redacted/synthetic requests before promoting detection queries. IP address overlap alone is not proof that a WAF event and ALB event are the same request.
- [ ] Estimate S3 versions, WAF logging, SQS operations and RunReveal ingest/retention charges with your traffic volume. Set budgets before production.

S3 notifications and these standard SQS queues can repeat or arrive out of order. Logs arrive in batches, not as a guaranteed synchronous request stream. Tune detection lookback and duplicate handling using measured ingestion delay.

## Operations, recovery and teardown

Retain evidence and disable/reroute producers before retiring their buckets. AWS warns that deleting a still-configured ALB log bucket can expose future logs if someone else recreates that bucket name with a compatible policy. Do not rely on `terraform destroy` as a complete offboarding workflow: ALB logging is owned elsewhere.

Bucket `force_destroy` is false. Removing a nonempty bucket will fail instead of deleting its contents for you. Current versions expire after the chosen period; noncurrent versions expire after another period. With the default 90/90 configuration, old bytes can remain about 180 days plus lifecycle processing delay. If policy demands a stricter deletion deadline or immutable evidence, redesign that lifecycle/storage control explicitly.

Dead-letter queues are not automatic recovery. After fixing the consumer, review why messages failed and redrive a bounded sample using an appropriately authorized operator. Monitor consumer delay relative to the 300-second visibility timeout. Adjust only after measuring your workload, with tests for duplicate handling.

## Primary references

- [RunReveal custom-SQS and IAM-role integration](https://docs.runreveal.com/sources/object-storage/external-s3)
- [RunReveal S3 ingestion and shared-datalake alternative](https://docs.runreveal.com/sources/object-storage/s3)
- [RunReveal AWS WAF source](https://docs.runreveal.com/sources/source-types/aws/aws-waf)
- [RunReveal AWS ALB source](https://docs.runreveal.com/sources/source-types/aws/alb)
- [AWS WAF S3 delivery requirements and permissions](https://docs.aws.amazon.com/waf/latest/developerguide/logging-s3.html)
- [AWS ALB access-log configuration and bucket policies](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html)
- [AWS ALB access-log format and delivery timing](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-access-logs.html)
- [HashiCorp AWS provider 6.68.0 release](https://github.com/hashicorp/terraform-provider-aws/releases/tag/v6.68.0)

These are implementation references, not endorsements or a guarantee of production suitability. Recheck source entitlements, trust details and service requirements for your own deployment before applying.
