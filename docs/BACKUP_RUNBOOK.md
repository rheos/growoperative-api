# Backup & restore runbook

Covers recovering the FOAF prod databases and the image buckets after a bad
migration, a bad seed, vandalism, or an accidental delete.

Every claim below was verified against the live AWS and Neon APIs on
2026-09-17. If you change how backups work, re-verify and update this file in
the same PR — the previous version of this runbook documented a daily backup
that had never run once, and that is worse than documenting nothing.

## What's protected, and how

| Asset | Mechanism | Recovery point |
|---|---|---|
| Neon prod DBs (last 6 h) | Neon instant restore (history retention) | Any point in the last 6 h |
| `growoperative-api` prod DB | Nightly `pg_dump` → `s3://growoperative-backups/growoperative-api-prod/` | Within ~24 h, kept 30 days |
| `foaf-auth` prod DB | Nightly `pg_dump` → `s3://growoperative-backups/foaf-auth-prod/` | Within ~24 h, kept 30 days |
| `foaf-protocol` prod DB | Nightly `pg_dump` → `s3://growoperative-backups/foaf-protocol-prod/` | Within ~24 h, kept 30 days |
| Item images + app avatars | S3 versioning on `growoperative-uploads-{production,demo}` | Any prior version, last 30 days |
| Identity avatars | S3 versioning on `foaf-auth-avatars-{prod,demo}` | Any prior version, last 30 days |

**Not covered:** demo and beta databases. Demo has the `demo:reset` break-glass
below; beta is disposable. Both still have Neon's 6-hour window.

## The two recovery windows

Neon's **free plan caps history retention at 6 hours** and the cap cannot be
raised by API — a longer window needs a paid plan (Launch = 7 days, Scale = 30).
So there are two distinct situations:

- **Noticed within 6 hours** → use Neon instant restore. Faster, exact to the
  second, no dump needed.
- **Noticed later** → use the nightly S3 dump. Up to 24 h of writes are lost.

The dumps also matter for a reason the 6-hour window can't cover: they live in a
different failure domain. Neon's history lives in the Neon account. An S3 dump
survives that account being lost, deleted, or locked out.

## Where the backup runs

A scheduled GitHub Action: [`.github/workflows/backup-prod-dbs.yml`](../.github/workflows/backup-prod-dbs.yml),
daily at 09:17 UTC (~02:17 PT), one job per database.

It is deliberately *not* a cron on the Contabo box. The backup it replaced was a
host cron that nobody could see from the repo, was never actually installed, and
left the bucket empty for four months without a single signal. Running it in CI
means every run has a visible history and a failure emails the repo owner.

Each run refuses to upload a bad dump. It checks that `pg_dump` wrote its
completion marker (catching a truncated dump), that the archive clears a size
floor (catching a dump of the wrong, empty database), and then re-reads the
object's size back from S3 (proving the upload actually landed rather than
trusting an exit code).

### Required repository secrets

| Secret | What |
|---|---|
| `NEON_GROWOPERATIVE_API_PROD_URL` | `DATABASE_URL` for Neon project `old-math-44951491` |
| `NEON_FOAF_AUTH_PROD_URL` | `DATABASE_URL` for Neon project `dry-salad-85577653` |
| `NEON_FOAF_PROTOCOL_PROD_URL` | `DATABASE_URL` for Neon project `calm-smoke-82417633` |
| `BACKUP_AWS_ACCESS_KEY_ID` | IAM user `growoperative-backup-ci` |
| `BACKUP_AWS_SECRET_ACCESS_KEY` | ditto |

Connection strings are in `~/Documents/novadiem/keys/neon/*-connection.txt`.
The IAM user can put, get, and list on `growoperative-backups` and nothing else
— it deliberately cannot delete, so a compromised CI token cannot destroy the
backup history. Expiry is handled by the bucket's `expire-dumps-after-30d`
lifecycle rule instead.

## Verify backups are running

Do this after any change to the workflow, and periodically regardless.

```bash
# Most recent dump per database (expect one per day; 14-34 KB gzipped as of
# 2026-09-17 - these databases are small, and most of Neon's reported 9-11 MB
# is index and catalog overhead rather than rows)
aws s3 ls s3://growoperative-backups/growoperative-api-prod/ | tail -3
aws s3 ls s3://growoperative-backups/foaf-auth-prod/ | tail -3
aws s3 ls s3://growoperative-backups/foaf-protocol-prod/ | tail -3
```

```bash
# Recent workflow runs and their outcomes
gh run list --workflow=backup-prod-dbs.yml --repo rheos/railsbackend --limit 10
```

An empty listing means the backup is not running. That is the exact state this
runbook existed in for four months, so treat it as an incident, not a to-do.

## Restore within 6 hours (Neon instant restore)

Preferred when the damage is recent. Restore to a **new branch** first and look
at it before touching the live branch.

```bash
NEON_KEY=$(tr -d '\n' < ~/Documents/novadiem/keys/neon/FOAF.txt)
PROJECT=old-math-44951491   # growoperative-api prod

# Branch the database as it was at a chosen moment
curl -s -X POST "https://console.neon.tech/api/v2/projects/$PROJECT/branches" \
  -H "Authorization: Bearer $NEON_KEY" -H "Content-Type: application/json" \
  -d '{"branch":{"name":"restore-check","parent_timestamp":"2026-09-17T18:00:00Z"},
       "endpoints":[{"type":"read_write"}]}'
```

Connect to the new branch, confirm the data is what you expect, then either
point the app at it or copy the missing rows back into `main`.

## Restore from an S3 dump (beyond 6 hours)

**Never restore straight over prod.** Load the dump into a scratch Neon branch,
verify it, then move the data you need.

This path was exercised on 2026-09-17: the `growoperative-api-prod` dump was
pulled back from S3 and restored into a scratch PostgreSQL 16 with
`ON_ERROR_STOP=1`, returning all 39 tables and their rows (including 57
`trustline_transactions`) with no errors. Re-run that drill after any change to
the workflow — a backup nobody has restored is a guess, which is how the
previous runbook ended up describing a backup that did not exist.

```bash
# 1. Pick a dump
aws s3 ls s3://growoperative-backups/growoperative-api-prod/

# 2. Fetch and unpack it
aws s3 cp s3://growoperative-backups/growoperative-api-prod/2026-09-17T0917Z.sql.gz /tmp/
gunzip /tmp/2026-09-17T0917Z.sql.gz

# 3. Create an empty branch to restore into (see the Neon call above, minus
#    parent_timestamp), then load the dump into that branch's connection string
psql "$RESTORE_BRANCH_URL" -v ON_ERROR_STOP=1 -f /tmp/2026-09-17T0917Z.sql
```

The dumps are `--no-owner --no-privileges` plain SQL, so they load into any Neon
branch regardless of role differences. Because they are plain SQL you can also
pull a single table out without a full restore:

```bash
# Extract just one table's data from a dump
gzip -dc 2026-09-17T0917Z.sql.gz | awk '/^COPY "public"."trustlines"/,/^\\\.$/'
```

If the dump predates recent migrations, run `rails db:migrate` against the
restored branch before pointing anything at it.

## Demo break-glass

If *demo* was vandalized, the fastest fix is not a restore at all. `demo:reset`
deletes every visitor-spawned account and rebuilds core demo users from the
committed baseline:

```bash
ssh -i ~/Documents/novadiem/keys/contabo/contabo_ed25519 root@144.126.145.4
docker exec <railsbackend-demo-container> bundle exec rails demo:reset
```

Use a dump-based restore for demo only when you need legitimate demo content
added since the baseline.

## Restore S3 images / avatars (versioning)

Versioning gives per-object rollback, not one-command whole-bucket rollback.

**Object deleted** — versioning leaves a delete marker. Remove it to bring the
object back:

```bash
B=growoperative-uploads-production
KEY=uploads/user/image/42/abc123.jpg
aws s3api list-object-versions --bucket "$B" --prefix "$KEY" \
  --query 'DeleteMarkers[].{V:VersionId,Latest:IsLatest}'
aws s3api delete-object --bucket "$B" --key "$KEY" --version-id <delete-marker-version-id>
```

**Object overwritten** — copy the prior version back over the current one:

```bash
aws s3api list-object-versions --bucket "$B" --prefix "$KEY" \
  --query 'Versions[].{V:VersionId,Date:LastModified,Latest:IsLatest}'
aws s3api copy-object --bucket "$B" --key "$KEY" \
  --copy-source "$B/$KEY?versionId=<good-version-id>"
```

For mass image vandalism, script a loop over `list-object-versions` selecting the
newest version dated at or before the incident.

## Infra reference

- Host: Contabo `144.126.145.4`, Coolify apps, key `~/Documents/novadiem/keys/contabo/contabo_ed25519`
- Databases: Neon Postgres 16, FOAF org `org-royal-fire-42143195`, **free plan**
- Prod Neon projects: `old-math-44951491` (growoperative-api),
  `dry-salad-85577653` (foaf-auth), `calm-smoke-82417633` (foaf-protocol)
- Backups bucket: `s3://growoperative-backups` (us-west-2, private, 30-day expiry)
- IAM: `growoperative-backup-ci`, policy `growoperative-backup-ci-policy` (put/get/list, no delete)
