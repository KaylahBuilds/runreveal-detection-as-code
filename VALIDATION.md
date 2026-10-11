# Validation checklist

Use this as an acceptance checklist, not a declaration that an end-to-end production integration has passed. The [CI run](https://github.com/KaylahBuilds/runreveal-detection-as-code/actions/workflows/validate.yml) for the commit you use is the source of truth for repository checks.

## 1. Repository and local contracts

- [ ] Terraform formatting and validation pass for both module and example.
- [ ] Mocked provider tests cover resource defaults, policy scope, input rejection, and explicit WAF logging opt-in.
- [ ] Synthetic Sigma positive, negative, and boundary cases produce the expected results in the native CLI.
- [ ] The Python wrapper rejects process failures and unexpected output, checks every event result, and uses the pinned release's behavior rather than an older guide's exit-code convention.
- [ ] Scheduled SQL examples remain disabled until tested against the actual workspace schemas and time windows.
- [ ] No credentials, raw logs, local profiles, state, plans, or generated reports are in the proposed commit.

## 2. AWS delivery and least privilege — requires your environment

- [ ] Record the intended AWS account, region, RunReveal workspace, entitlement, and data-handling approval.
- [ ] Confirm the trusted RunReveal principal and distinct external IDs through the workspace configuration.
- [ ] Review the plan: new dedicated buckets and queues only; no unintended replacements; ALB logging stays in its owner stack; WAF destination takeover is intentional if enabled.
- [ ] Verify the buckets reject public access and unencrypted transport and the reader roles cannot write logs or read the other source's log objects.
- [ ] Test a benign request against your own test application and confirm its WAF/ALB delivery independently. Do not scan or attack unrelated services.
- [ ] Check S3 object prefixes, compression and content, SQS notification routing, source authentication, parser fields, and workspace destination.
- [ ] Measure actual delivery delay and queue age; test source outage, retry, duplicate handling, retention, and recovery before production use.
- [ ] Confirm redaction and inspect a deliberately synthetic record end to end before sending customer data.

## 3. Detection semantics — requires RunReveal validation

- [ ] Run both native Sigma and SQL linters using the protected staging environment. These commands call the API in v2026.9.1 and are not part of credential-free PR validation.
- [ ] Verify field names and types against the actual normalized WAF and ALB tables.
- [ ] Exercise the scheduled SQL queries over a bounded historical test interval; prove below-threshold, at-threshold, and above-threshold cases.
- [ ] Account for delayed events, received time versus event time, quiet sources, maintenance traffic, and known false positives.
- [ ] Confirm the alert contains sufficient investigation context without copying unnecessary sensitive payloads.
- [ ] Assign an owner, triage runbook, tuning criteria, and a notification destination appropriate for a test workspace.

## 4. Controlled synchronization — inactive until configured

- [ ] Use a dedicated disposable workspace; export and back up any existing definitions outside this public repository.
- [ ] Protect the default branch and deployment environment, require human review, and restrict deployment to the reviewed commit on `main`.
- [ ] Keep PR jobs secret-free. Provide only a scoped RunReveal token through the protected environment; keep debug logging off.
- [ ] Review the full sync dry-run diff, especially removals. A partial directory is not necessarily an additive deployment.
- [ ] Apply only the reviewed bundle, confirm remote definitions and enabled/disabled state, then repeat the functional checks.
- [ ] Rehearse rollback by reverting and reviewing a new sync diff. A Git revert alone does not undo a remote change.

No AWS resources, RunReveal sources, authenticated linting, workspace sync, live SQL replay, or notification delivery were performed when authoring this repository. Those checks require the operator's accounts and explicit deployment decisions.
