# Security and operating boundaries

This public learning repository is not a managed service, a compliance assessment, or a production detection pack. Test data must be synthetic. No repository workflow is authorized to change AWS or RunReveal resources by default.

## Credentials stay outside Git

Never commit AWS credentials, RunReveal API tokens, private keys, customer logs, Terraform state or plan files, local CLI profiles, or environment files. Ignore rules reduce accidents; they are not a secret scanner or an access boundary. Review the staged diff and enable repository secret scanning where available. If a secret is exposed, revoke or rotate it first; deleting a line or a commit is not sufficient remediation.

For an eventual deployment, use short-lived AWS role sessions and a separately scoped RunReveal token in a protected environment. Keep untrusted pull-request jobs credential-free. A token must never be passed through a URL, interpolated into a workflow's shell script, printed in debug output, or stored in a Terraform variable committed to the repo.

## AWS ingestion is a sensitive integration

- Review the exact reader principal, external ID, bucket prefixes, queue permissions, account, and region before applying. Obtain the principal and external IDs through the trusted RunReveal workspace configuration, not a copied example.
- Separate WAF and ALB logging buckets and reader roles limit cross-source access. The module manages only new resources it creates. Do not import an existing production bucket, replace its notification configuration, or take over an existing WAF logging destination without a migration plan.
- The ALB remains owned by its existing Terraform configuration. Review the provided `access_logs` wiring there. The optional WAF logging resource is disabled by default.
- Terraform state can contain identifiers and sensitive inputs despite `sensitive = true`. Protect and encrypt state, restrict access, and keep saved plans and CLI output out of public artifacts.
- Logs can contain IP addresses, URLs, cookies, authorization headers, and personal information. Redact WAF fields before delivery where supported; ALB URLs may still expose query-string data. Use synthetic traffic first, and obtain data-handling approval before sending real logs to a third party.
- Review retention, S3/SQS request costs, delivery delays, RunReveal source entitlements, and ingestion charges. A successful Terraform plan is not evidence that events reached the right workspace.

## Detection and deployment boundaries

An alert is an investigative signal, not proof of compromise. WAF denial and an ALB response are different observations; neither fixture asserts an application compromise. Test false positives, missing fields, parser changes, late delivery, and expected legitimate activity before enabling notifications.

The deployment workflow is an inactive template. Configure branch restrictions, required review, an environment approval gate, and the intended workspace before activating it. Review the sync diff, including removals, and keep staging separate from production. Sync is a remote mutation even when it only changes a detection. A dry run may contact the API and requires trusted credentials; it does not belong in a public fork PR job.

Do not automatically block clients, terminate workloads, delete logs, or grant new cloud permissions in response to these sample detections.

## Reporting issues

Use a private reporting channel for sensitive issues. If GitHub private vulnerability reporting is unavailable, request a private channel from the maintainer without posting secrets or customer evidence. Public issues are suitable for nonsensitive documentation errors and failures reproduced with the included synthetic fixtures. No support or response SLA is implied.
