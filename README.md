# RunReveal detection as code

[![Validate examples](https://github.com/KaylahBuilds/runreveal-detection-as-code/actions/workflows/validate.yml/badge.svg)](https://github.com/KaylahBuilds/runreveal-detection-as-code/actions/workflows/validate.yml)

Two hands-on examples connect log delivery to a reviewed detection workflow:

1. **Reusable Terraform for AWS WAF and ALB log ingestion.** Create separate private logging buckets, S3-to-SQS notifications, and scoped reader roles for RunReveal. Keep existing ALB ownership intact; opt in explicitly to WAF logging.
2. **Detection CI/CD.** Version Sigma and SQL examples, test synthetic match and non-match cases, and separate credential-free pull-request checks from reviewed RunReveal synchronization.

Companion article: [RunReveal detection as code](https://kaylahbuilds.io/#/blog/runreveal-detection-as-code).

## Start here

| Example | Start | What it does not do |
| --- | --- | --- |
| AWS log ingestion | [Terraform walkthrough](docs/aws-ingestion.md) · [module](modules/runreveal-aws-logs) · [example](examples/aws-waf-alb) | Does not create an ALB, WAF policy, RunReveal workspace, or RunReveal source registration |
| Detection-as-code pipeline | [CI/CD walkthrough](docs/detection-cicd.md) · [detections](detections) · [fixtures](fixtures) | Does not enable live alerts, sync automatically, or claim detection coverage from synthetic fixtures |
| Safe operation | [Security boundaries](SECURITY.md) · [validation checklist](VALIDATION.md) | Does not replace a review of your account, traffic, retention, and data-sharing requirements |

The Terraform module provisions the **AWS side** of the integration. Connect its outputs to two sources in your RunReveal workspace using the documented custom-SQS setup. This is not an unofficial Terraform provider pretending to manage RunReveal resources. Confirm that your subscription supports AWS WAF and ALB sources before incurring cloud costs.

```text
AWS WAF logs -> private WAF bucket -> WAF queue -> scoped WAF reader -> RunReveal WAF source
ALB logs     -> private ALB bucket -> ALB queue -> scoped ALB reader -> RunReveal ALB source

Detection PR -> local checks + native CLI tests -> review -> main
                                                          -> optional protected sync
```

S3 log delivery is asynchronous. WAF actions and ALB responses are different observations, not a guaranteed one-to-one request join. The examples keep these signals separate rather than implying every blocked WAF request will appear as an application error.

## Credential-free checks

Prerequisites: Terraform **1.9.8**, Python **3.12**, and, for the pinned CLI installer, Linux x86-64 with Bash, curl, tar, and sha256sum. Windows users can run the Python/Terraform checks natively; GitHub Actions runs the Linux CLI checks. Review downloaded tooling before running it.

```sh
python -m venv .venv
# Activate the virtual environment for your shell, then:
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tests -v

terraform fmt -check -recursive
terraform -chdir=modules/runreveal-aws-logs init -backend=false
terraform -chdir=modules/runreveal-aws-logs validate
terraform -chdir=modules/runreveal-aws-logs test
terraform -chdir=examples/aws-waf-alb init -backend=false
terraform -chdir=examples/aws-waf-alb validate

# Linux x86-64 only; installs the pinned official CLI after checksum verification.
bash scripts/install-runreveal.sh .tools
python scripts/test_detections.py --native .tools/runreveal
```

Module tests use Terraform's mocked provider. They do not create resources or need AWS credentials. A mock test does not prove that AWS will accept a policy or deliver logs. Native Sigma fixture replay does not prove live parser behavior or scheduled SQL results.

RunReveal v2026.9.1 requires a token setting even for its local fixture command. The runner supplies a deliberately invalid, nonsecret sentinel only to that child process and points its API URL to unreachable loopback port 1. No real token is used, and an API request cannot reach RunReveal. **Both Sigma and SQL lint commands are API-backed in this release**; they belong in the inactive credentialed preview workflow, not public PR validation. Do not mistake the local contract checks for those linters.

## Before a real integration

Read both walkthroughs and complete the [validation checklist](VALIDATION.md). Use a disposable account or isolated test resources, a dedicated RunReveal workspace, and approved synthetic traffic. Review plans and costs before any apply. Protect Terraform state. Do not paste a RunReveal token into a `.tf` file or commit a populated `.tfvars` file.

The only active workflow is validation. The credentialed workflow under `workflow-templates/` is deliberately inactive. Activating it requires your environment configuration, scoped credentials, branch restrictions, and approval gate. **RunReveal sync can remove CLI-managed detections omitted from the local directory**; never point this small demonstration bundle at a shared production workspace.

## Sources and versioning

- [RunReveal detection CI/CD guide](https://blog.runreveal.com/runreveal-detection-cicd-guide/) — the requested starting point, not a workflow to copy unchanged.
- [Current RunReveal CLI documentation](https://docs.runreveal.com/reference/using-the-cli) — newer CLI configuration differs from older examples.
- [RunReveal log source catalog](https://docs.runreveal.com/sources) and [S3 ingestion](https://docs.runreveal.com/sources/object-storage/s3).
- [AWS ALB access logging](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html).
- [AWS WAF S3 logging](https://docs.aws.amazon.com/waf/latest/developerguide/logging-s3.html).

Tool versions are intentionally pinned. Re-run native tests and review schema, permission, and output changes before upgrading. This repository is independent of RunReveal and AWS, and does not imply vendor endorsement.
