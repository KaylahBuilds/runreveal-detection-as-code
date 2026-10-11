# Example 1: WAF + ALB ingestion

This root module prepares the AWS side of two RunReveal integrations. It does not create an application, ALB, ACL or a RunReveal workspace/source. Read [the integration guide](../../docs/aws-ingestion.md) before connecting real logs.

## Safe local validation

No AWS credentials are required for these checks:

```sh
terraform init -backend=false
terraform validate
terraform -chdir=../../modules/runreveal-aws-logs init -backend=false
terraform -chdir=../../modules/runreveal-aws-logs test
```

Provider downloads require network access. `init` is not deployment, and mocked tests are not a live integration test.

## Prepare a sandbox plan

1. Authenticate through AWS SSO or another approved short-lived credential flow.
2. Copy the settings from `terraform.tfvars.example` into an ignored local file. Replace every placeholder; use the intended AWS account as the provider allow-list guardrail.
3. Verify RunReveal's actual trust principal for your deployment. Do not use the placeholder principal or assume the public SaaS account applies to BYOC/BYODB.
4. Supply `TF_VAR_external_ids` through a protected environment/secret manager as a JSON object with distinct `waf` and `alb` values. Do not paste real values into repository files or command history.
5. Configure a protected remote backend with encryption and locking suitable for your team. This starter has no backend or credential defaults.
6. Run `terraform plan` and review resource identities, bucket policies, expiry, cost and trust. Apply only in an approved sandbox after review; no CI job in this repo applies it.

`manage_waf_logging` is false by default. An existing WAF logging configuration has one owner; inspect it before enabling this option or importing it. Turning this option off after the module owns logging plans to remove that logging configuration, not merely stop management. Use a reviewed state-ownership migration when handing it back.

The module outputs do **not** turn on ALB logging. Add the `access_logs` block to the already-owned ALB resource as shown in the integration guide, then register and verify the corresponding RunReveal sources.
