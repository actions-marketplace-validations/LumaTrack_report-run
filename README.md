# LumaTrack: Report Run

Report each workflow run (success or failure) to [LumaTrack](https://lumatrack.io),
the system of record for automation value. One step at the end of a job
gives you an auditable ledger of what your CI/CD automation is worth:
runs, failures priced as costs, and time and dollars against a baseline
you define.

## Usage

```yaml
- name: Report run to LumaTrack
  if: always()
  uses: LumaTrack/report-run@v1
  with:
    base-url: ${{ vars.LUMATRACK_URL }}
    api-key: ${{ secrets.LUMATRACK_KEY }}
    automation: deploy-pipeline
    status: ${{ job.status }}
```

`if: always()` makes failures report too; they cost money and save
nothing, and the ledger prices that honestly.

`@v1` tracks the latest 1.x release, currently **v1.0.1**. Pin
`LumaTrack/report-run@v1.0.1` instead if you want an exact version. `status` accepts the raw
`${{ job.status }}` value: `cancelled` and `skipped` book as failures
with the reason preserved.

## Inputs

| Input | Required | Notes |
|---|---|---|
| `base-url` | yes | Your LumaTrack host |
| `api-key` | yes | Store in repository or organization secrets |
| `automation` | yes | The automation slug this workflow reports as |
| `status` | no | `success` (default), `failure`, `cancelled`, `skipped` |
| `duration-seconds` | no | Wall-clock runtime |
| `units` | no | Items processed; drives per-unit valuation |
| `external-id` | no | Idempotency key; defaults to run id + attempt, so step retries never double-count |
| `failure-reason` | no | Root cause, e.g. `tests/unit`; powers the failure Pareto |
| `metadata` | no | JSON object kept with the run |
| `fail-on-error` | no | Default `false`: a LumaTrack outage never breaks your pipeline |

## Outputs

- `run-id`: the LumaTrack run id
- `deduplicated`: `true` when this external id was already reported

## Requirements

A LumaTrack workspace (free tier works) and an API key from Settings.
The action is a composite of `bash`, `curl`, and `jq`, all present on
GitHub-hosted runners; self-hosted runners need those three tools.
