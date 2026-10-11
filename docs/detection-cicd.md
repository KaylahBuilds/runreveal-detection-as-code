# Example 2: detection changes that must earn deployment authority

This example implements the lifecycle from [RunReveal's CI/CD guide](https://blog.runreveal.com/runreveal-detection-cicd-guide/) with separate trust boundaries. Repository checks do not get a workspace token. A credentialed preview and an explicitly approved sync are later, inactive steps.

## What is included

| Detection | Question | Validation here |
| --- | --- | --- |
| `sigma/aws-waf-blocked-admin-request.yaml` | Did WAF block a request to one of two illustrative administrative paths? | Synthetic positive, negative, missing/null and mixed-event fixtures |
| `sql/aws-waf-block-burst.yaml` | Did one IP and ACL accumulate at least 20 blocked requests in a received window? | Configuration contract and native SQL lint; workspace execution is separate |
| `sql/alb-server-error-burst.yaml` | Did one ALB log source and host accumulate at least 10 HTTP 5xx responses? | Configuration contract and native SQL lint; workspace execution is separate |

Paths are relative to `detections/`. Every detection ships **disabled**, without notification destinations or automated triage. Counts are demonstration thresholds, not universal baselines. A blocked request is not proof of a successful attack; a 5xx burst can be an application outage. There is no automated IP blocking or remediation.

## Check locally without a workspace token

Use Python 3.12+; the pinned native installer below targets Linux x86_64.

```sh
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tests -v
python scripts/test_detections.py
bash scripts/install-runreveal.sh .tools
python scripts/test_detections.py --native .tools/runreveal
```

The installer downloads RunReveal **v2026.9.1**, verifies the Linux amd64 archive's pinned SHA-256, and extracts only the executable. Review a new version and checksum together; do not switch to `latest`. Other platforms should use a matching official release asset and verify its published checksum independently.

`tests/detection-tests.json` is the explicit contract: four cases, twelve events, a boolean outcome per line. `scripts/test_detections.py` has two layers:

1. Offline checks validate repository paths, fixture shape and this demonstration's narrowly supported exact-equality selection. This little evaluator is **not a Sigma engine**. It also checks disabled defaults and scheduled SQL windowing, without claiming SQL execution.
2. `--native` runs the actual CLI's Sigma and SQL linters, then feeds each fixture into `detections run`. It requires the documented result for **every line** and the expected exit code. A positive result uses exit 1; ordinary command failure can also use exit 1. Therefore exit 1 alone never counts as success. Missing, duplicate, unknown or error output fails closed. A changed output format requires reviewing and updating the harness, not suppressing errors.

The native commands here do not call sync or historical queries. Remove `RUNREVEAL_TOKEN` before using the native runner; it refuses that environment variable. It isolates the CLI's config directory. Read [VALIDATION.md](../VALIDATION.md) for checks actually completed in this repository, not assumed capabilities.

## Know which event shape you are testing

The streaming rule selects raw WAF fields `action` and `httpRequest.uri`. The synthetic NDJSON is a minimal raw-event fixture, not an entire AWS log-delivery envelope. A native local match does not verify which sources run the rule in your workspace, AWS parsing, transforms, or alert delivery.

Scheduled SQL uses different, normalized tables: `aws_waf_logs` for WAF and `http_logs` filtered to `sourceType = 'alb'` for ALB. The ALB status is documented as a string, so the query converts it before comparison. Queries use a half-open `receivedAt` window with RunReveal's `{from:DateTime}` and `{to:DateTime}` parameters. This keeps adjacent windows nonoverlapping and handles delivery delays; it does not make at-least-once source delivery exactly once. Validate duplicate handling and latency in your environment.

## Stage with evidence before enabling

- Create a **dedicated disposable RunReveal workspace** for these examples. Do not point this demo at an existing production detection catalog. Confirm the plan includes the required WAF and ALB source types.
- Confirm both source integrations deliver representative records. Compare raw WAF selector paths with the actual streaming event; compare SQL columns and source types with the documented schemas and your workspace.
- In a controlled test window, replay harmless authorized requests to your own test application. Record baseline traffic, deliberate test requests, source arrival delay and expected detection counts. Do not send attacks to third-party endpoints.
- Authenticate outside Git using a securely stored token. Do not print `auth status`, enable `RUNREVEAL_DEBUG`, put tokens in arguments, or include production logs in this public repository.
- Run each SQL query against a known staging time range and inspect returned rows. Empty output alone is not validation: show a known positive and a known negative window, plus a threshold boundary case. Check below-threshold, exactly-threshold, 4xx vs 5xx and delayed events.

```sh
# Credentialed operations: opt-in staging only, not executed by ordinary CI.
runreveal detections test -f detections/sql/aws-waf-block-burst.yaml --from 'now-1h' --to 'now'
runreveal detections test -f detections/sql/alb-server-error-burst.yaml --from 'now-1h' --to 'now'
runreveal detections sync --dry-run -d detections
```

Use a secure session to provide `RUNREVEAL_TOKEN` and `RUNREVEAL_WORKSPACE`; no token values belong in these files. Current CLI releases use these environment variables, replacing the older guide's configuration example.

## Important: sync owns a catalog, not only an individual file

RunReveal sync can **delete CLI-managed detections missing from the sync directory**. Always preview the complete owned catalog in one invocation. Do not sync `detections/sigma` and `detections/sql` separately into the same workspace. Never add `--overwrite` casually: it changes ownership of UI-managed detections.

Before adopting this repository in an existing environment, export and reconcile that entire CLI-managed catalog, establish ownership and review every proposed deletion. Keep the export private and out of Git until sanitized. A source-code revert only restores definitions; it cannot undo alerts, investigations, billing or an upstream logging change.

## Inactive, manual deployment template

`workflow-templates/deploy-detections.yml.example` is intentionally outside `.github/workflows`. Copying it into an active workflow is a deliberate operational decision; this repository does not grant deployment authority automatically.

Before activation:

1. Use a dedicated synthetic-data workspace. Workflow logs in a public repository are public, and a dry-run reveals detection names and definitions. Use a private deployment repository for sensitive rules or workspace details.
2. Protect `main`, require validation and peer review, and configure two GitHub environments: `runreveal-lab-preview` and `runreveal-lab-apply`. Restrict both to `main`; require reviewers and prevent self-review for apply. An environment's name in YAML does **not** configure these controls by itself.
3. Store a least-privilege token as the environment secret `RUNREVEAL_TOKEN` and the workspace ID as `RUNREVEAL_WORKSPACE`. Ensure both environments target the **same** dedicated workspace; apply checks its ID against the successful preview job's output before sync. The workspace ID is an identifier, not a credential, and is included in run metadata. Use a read-capable token for preview if your RunReveal permission model supports all dry-run operations; grant write scope only to apply. Confirm exact token permissions with your deployment's RBAC.
4. Manually dispatch on `main`, initially with `apply=false`. The template validates the exact commit before the credentialed preview. Review create/update/delete scope, warnings and source routing.
5. A later `apply=true` dispatch revalidates and previews its exact commit, then waits on a separate apply-environment approval. The reviewer must read that run's preview and confirm the commit/workspace. The acknowledgement must be `SYNC-DEDICATED-LAB`. There are no PR secrets, `pull_request_target` triggers, automatic push deployments or overwrite flags.
6. The sync still uploads **disabled** definitions. Enable rules and notification routing only after a separate reviewed configuration change, staging results, an owner and a rollback procedure. Do not weaken this demo's disabled-default contract just to get a deployment green.

Preview is not an immutable server-side plan: workspace drift between preview and sync remains possible. Serialize writers and re-preview after out-of-band changes. The template's concurrency group serializes runs in this repository only. It is a reviewed lab pattern, not a transactional production deployment engine.

## Primary references

- [RunReveal CI/CD guide](https://blog.runreveal.com/runreveal-detection-cicd-guide/)
- [Current CLI and credential resolution](https://docs.runreveal.com/reference/using-the-cli)
- [CLI v2026.9.1 release](https://github.com/runreveal/homebrew-runreveal/releases/tag/v2026.9.1)
- [Testing, dry runs and sync deletion behavior](https://docs.runreveal.com/detections/detection-as-code/uploading-detections)
- [Detection data model and time windows](https://docs.runreveal.com/detections/detection-as-code)
- [Sigma source scoping and raw-event processing](https://docs.runreveal.com/detections/sigma-streaming)
- [WAF source schema](https://docs.runreveal.com/sources/source-types/aws/aws-waf)
- [ALB source schema](https://docs.runreveal.com/sources/source-types/aws/alb)
