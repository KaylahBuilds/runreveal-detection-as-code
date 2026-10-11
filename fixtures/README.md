# Synthetic events, not customer logs

All NDJSON events here are hand-authored test inputs. Addresses use documentation ranges. They have no request bodies, authorization headers, cookies, account credentials or real customer identifiers.

The Sigma example evaluates **raw WAF-shaped JSON**, including `httpRequest.uri`, not a normalized SQL row. These files exercise the matcher only: they do not prove S3 delivery, source routing, WAF parsing, complete AWS event-schema acceptance or alert delivery. Confirm the actual event shape in your workspace before enabling.

| File | Purpose | Expected matched lines |
| --- | --- | --- |
| `waf-positive.ndjson` | Both configured administrative paths | 1, 2 |
| `waf-negative.ndjson` | Allow/count actions, other path, prefix near-miss | None |
| `waf-edge.ndjson` | Missing and null fields | None |
| `waf-mixed.ndjson` | Prove per-line outcomes, not merely one successful match | 2 |

The SQL examples query normalized `aws_waf_logs` and `http_logs`. There is deliberately no fake local SQL pass: RunReveal's `detections test` needs workspace data. Follow the controlled staging checklist in [the detection guide](../docs/detection-cicd.md).
