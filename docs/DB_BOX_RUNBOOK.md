# MySQL box runbook — `growoperative-mysql`

Triage + history for when "demo and/or prod API is down." Written after two
outages on 2026-05-21. Read the decision tree first; the two failure modes look
identical from the outside but need **opposite** responses.

## The box

- Lightsail `micro_3_0`, ~914 MB RAM, MySQL **8.0.45**.
- Public IPv4 `35.92.64.94` (NOT static — changes on stop/start), private IPv4
  `172.26.13.168`, public IPv6 `2600:1f14:34c5:8b00:d3a1:f066:ebda:77f`.
- **Hosts FOUR databases:** `growoperative_production`, `growoperative_demo`,
  `foaf_auth_production`, `foaf_auth_demo`. So an outage takes down GrowOperative
  prod + demo **and auth.foaf.io for the whole ecosystem**. Big blast radius.
- App + auth reach it over **private IPv4 3306**. Admin SSH is via **jump through
  the Rails box** (`ubuntu@35.163.185.37`, private `172.26.4.92`), key
  `keys/Growoperative-Rails-2gb.pem`. SSH is key-only (no passwords).

## Triage: API hanging / timing out (curl returns 000)

First confirm it's this box, not the app. The frontend (static) staying up while
`/v1/*` hangs points here. Then pull Lightsail metrics — **no SSH needed**, works
even when the box is unreachable:

```bash
aws lightsail get-instance-metric-data --region us-west-2 \
  --instance-name growoperative-mysql --metric-name CPUUtilization \
  --period 300 --start-time <iso-1h-ago> --end-time <iso-now> \
  --unit Percent --statistics Maximum --query 'metricData[].maximum' --output text
# also: BurstCapacityPercentage, StatusCheckFailed_Instance, StatusCheckFailed_System
```

Then match the pattern:

| Signal | Failure mode | Action |
|---|---|---|
| CPU pegged ~99%, burst draining; SSH banner times out | **OOM / swap thrash** (`dmesg -T \| grep -i oom` shows `Killed process ... mysqld`) | **Self-recovers** in minutes — mysqld restarts + InnoDB crash recovery. Swap (added 2026-05-21) should now prevent it. Don't reboot unless it doesn't recover. |
| CPU idle (~1%), burst 100%, `StatusCheckFailed_Instance=1`, `_System=0`, ports 22+3306 dead | **OS hang** (guest wedged, AWS hardware fine) | **Does NOT self-recover. Reboot:** `aws lightsail reboot-instance --instance-name growoperative-mysql --region us-west-2`. Back in <60s; InnoDB recovery is safe. |
| Box reachable via SSH, but mysqld not running | **MySQL crashed/stopped** | `systemctl status mysql`; check `/var/log/mysql/error.log`; `systemctl restart mysql`. |

SSH is flaky while the box is starved — retry with
`-o ConnectTimeout=60 -o ServerAliveInterval=10`; it usually gets through once RAM
frees. Jump command:

```bash
ssh -o ProxyCommand="ssh -W %h:%p -i keys/Growoperative-Rails-2gb.pem ubuntu@35.163.185.37" \
    -i keys/Growoperative-Rails-2gb.pem ubuntu@172.26.13.168
```

After any recovery, confirm: `mysqladmin ... ping` from the Rails backend container,
and `curl https://demo.growoperative.app/v1/demo/users` + the prod equivalent → 200.

## What's been done (so we don't re-try things that are already in place)

**2026-05-21, incident 1 (OOM, ~06:47 UTC):** mysqld OOM-killed (3rd time; also May 5).
- Added **2 GB swap** (`/swapfile`, in `/etc/fstab`, `vm.swappiness=10`). Box had ZERO swap.
- **Tuned MySQL** in `/etc/mysql/mysql.conf.d/mysqld.cnf` (backup `*.bak.20260521`):
  `performance_schema=OFF`, `max_connections=40`, `table_open_cache=400`,
  `table_definition_cache=400`. Resident RSS **406 MB → 159 MB**; free RAM 73→344 MB.

**2026-05-21, incident 2 (OS hang, ~15:5x UTC):** box wedged, idle CPU, status check
failing. Recovered by **reboot**. Post-mortem found **no kernel trace** — root cause
inconclusive. Disk was fine (6 G/39 G).

**2026-05-21, firewall hardening** (`aws lightsail put-instance-public-ports`):
- 3306 was IPv4-locked to the Rails box but **open to `::/0` on IPv6**, and MySQL
  `bind-address=::` listens on v6 — the DB was reachable from the public IPv6
  internet, behind only the `buddy` password. **Closed: 3306 is now IPv4-only.**
- Port 80 (no web server here) **closed**.
- SSH 22 **left fully open on purpose** — direct emergency access that doesn't
  depend on the Rails jump host being up. Safe because SSH is key-only
  (`passwordauthentication no`, 0 password logins ever). The ~115k brute-force
  attempts in the logs are harmless noise.

**Related work same day:** 11 perf indexes added (migration `20260521120000`, see
`docs/plans/db_index_audit.md`); items-path N+1 plan (`docs/plans/n_plus_one_items_index.md`);
S3 versioning + `growoperative-backups` bucket + backup scripts (`scripts/`, cron
NOT yet installed).

## Open / not yet done

- **Lightsail alarm on `StatusCheckFailed_Instance`** so the next OS hang pages
  someone instead of a user finding it. (Lightsail can notify but can't auto-reboot.)
- **Root cause of the OS hang** — never found; watch for recurrence.
- **Managed DB migration** — deferred (can't justify cost for 1.7 MB), but the
  auth.foaf.io blast radius + two failures in a night argue for revisiting. Decision
  was Lightsail-managed, prod-only; note that leaves auth + demos on this box.
- **DB backup cron** — scripts exist in `scripts/`, not installed on the host.
- **fail2ban** — optional (log noise only, given key-only SSH).
```
