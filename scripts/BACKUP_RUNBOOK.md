# Backup & restore runbook

Covers recovering Growoperative demo and prod after vandalism or accidental
data loss: items/trades (MySQL), and item images + avatars (S3).

## What's protected, and how

| Asset | Mechanism | Recovery point |
|---|---|---|
| `growoperative_production` DB | Daily `mysqldump` → `s3://growoperative-backups/growoperative_production/` | Within ~24h |
| `growoperative_demo` DB | Daily `mysqldump` → `s3://growoperative-backups/growoperative_demo/` | Within ~24h |
| Item images + app avatars | S3 versioning on `growoperative-uploads-{production,demo}` | Any prior version, last 30 days |
| Identity avatars | S3 versioning on `foaf-auth-avatars-{prod,demo}` | Any prior version, last 30 days |

DB dumps and old object versions both expire after 30 days (bucket lifecycle rules).
The backups bucket is private + encrypted; the cron's IAM creds can write and read
backups but cannot delete them.

## First, for the demo specifically: try `demo:reset`

If the *demo* was vandalized, the fastest fix is the existing break-glass — it
deletes every visitor-spawned account and restores core demo users from the
committed baseline, no S3 or DB-dump work needed:

```bash
ssh ubuntu@35.163.185.37
docker exec <backend-demo-container> bundle exec rails demo:reset
```

Use the dump-based restore below only when you need a *specific point in time*
(e.g. legit demo content was added since the baseline and you want it back), or
for prod, which has no reset.

## Restore a database from a dump

On the Lightsail host (`ubuntu@35.163.185.37`):

```bash
# Latest dump
/home/ubuntu/backups/restore_db.sh growoperative_demo

# Specific point in time (list available first)
aws s3 ls s3://growoperative-backups/growoperative_demo/
/home/ubuntu/backups/restore_db.sh growoperative_demo 2026-05-20T0917Z
```

The script prompts for confirmation and overwrites the target DB. If the dump
predates recent migrations, run `rails db:migrate` in the backend container after.

## Restore S3 images / avatars (versioning)

Versioning gives per-object rollback, not one-command whole-bucket rollback.
The two vandalism cases:

**Object deleted** — versioning leaves a delete marker. Remove it to bring the
object back:

```bash
B=growoperative-uploads-demo
KEY=uploads/user/image/42/abc123.jpg
# Find the delete marker's VersionId
aws s3api list-object-versions --bucket "$B" --prefix "$KEY" \
  --query 'DeleteMarkers[].{V:VersionId,Latest:IsLatest}'
aws s3api delete-object --bucket "$B" --key "$KEY" --version-id <delete-marker-version-id>
```

**Object overwritten** — copy the prior version back over the current one:

```bash
B=growoperative-uploads-demo
KEY=uploads/user/image/42/abc123.jpg
aws s3api list-object-versions --bucket "$B" --prefix "$KEY" \
  --query 'Versions[].{V:VersionId,Date:LastModified,Latest:IsLatest}'
aws s3api copy-object --bucket "$B" --key "$KEY" \
  --copy-source "$B/$KEY?versionId=<good-version-id>"
```

For mass image vandalism across many keys, script a loop over
`list-object-versions` selecting the newest version dated at-or-before the
incident. If that becomes a recurring need, switch to the dated full-bucket
`aws s3 sync` snapshot approach instead — it makes whole-bucket point-in-time
restore a single sync.

## Verify backups are running

```bash
# Most recent dump per DB
aws s3 ls s3://growoperative-backups/growoperative_production/ | tail -3
aws s3 ls s3://growoperative-backups/growoperative_demo/ | tail -3
# Cron log on the host
ssh ubuntu@35.163.185.37 'tail -20 /home/ubuntu/backups/backup.log'
```

## Infra reference

- Rails host: `35.163.185.37` (containers `backend`, `backend-demo`, `nginx`)
- MySQL host: `172.26.13.168` (private), DBs `growoperative_production`, `growoperative_demo`, user `buddy`
- Backups bucket: `s3://growoperative-backups` (us-west-2, private, versioned, 30-day retention)
- IAM: `growoperative-upload-user` policy `growoperative-uploade-policy`, statement `BackupsReadWriteNoDelete`
