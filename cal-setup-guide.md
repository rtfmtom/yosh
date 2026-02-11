# Cal.com Self-Hosted Setup Guide (Security-First)

## Overview

This guide walks through deploying a self-hosted Cal.com instance on a fresh 3GB RAM VM,
designed to be exposed to the internet from day one. Every step prioritizes security:
secrets are generated before anything runs, internal services are never exposed to the
network, TLS is enforced via a reverse proxy, and the host OS is hardened against common
attacks.

**Stack**: Cal.com (pre-built image) + PostgreSQL 16 + Redis 7 + Caddy (automatic HTTPS)

**Approach**: Pull pre-built images only — no building on the host. This keeps RAM usage
manageable on a 3GB VM and avoids shipping build tooling to production.

---

## Prerequisites

- A fresh VM (Ubuntu 22.04+ or Debian 12+ recommended) with 3GB+ RAM
- A domain name with DNS pointed at the VM's public IP (e.g. `cal.example.com`)
- SSH access via key-based authentication

---

## Phase 1: Harden the Host OS

### 1.1 Update the system

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

Select "Yes" when prompted to enable automatic security updates.

### 1.2 Create a non-root deploy user

```bash
sudo adduser deploy
sudo usermod -aG sudo deploy
```

Copy your SSH key to the new user:

```bash
sudo mkdir -p /home/deploy/.ssh
sudo cp ~/.ssh/authorized_keys /home/deploy/.ssh/
sudo chown -R deploy:deploy /home/deploy/.ssh
sudo chmod 700 /home/deploy/.ssh
sudo chmod 600 /home/deploy/.ssh/authorized_keys
```

### 1.3 Lock down SSH

Edit `/etc/ssh/sshd_config`:

```
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
AllowUsers deploy
```

Restart SSH:

```bash
sudo systemctl restart sshd
```

**Important**: Before closing your current session, open a *second* terminal and confirm
you can SSH in as `deploy`. If you lock yourself out, you'll need console access.

### 1.4 Configure the firewall

```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

Only three ports are open: SSH (22), HTTP (80, for ACME challenges and redirect to HTTPS),
and HTTPS (443). PostgreSQL, Redis, and Cal.com's port 3000 are *not* exposed.

### 1.5 Install fail2ban

```bash
sudo apt install -y fail2ban
```

Create `/etc/fail2ban/jail.local`:

```ini
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
findtime = 600
```

```bash
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

### 1.6 Kernel hardening (sysctl)

Append to `/etc/sysctl.d/99-hardening.conf`:

```ini
# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0

# Ignore source-routed packets
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Enable SYN flood protection
net.ipv4.tcp_syncookies = 1

# Log suspicious packets
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Disable IP forwarding (only needed if not using Docker's default bridge)
# Note: Docker enables this automatically; leave commented if using Docker
# net.ipv4.ip_forward = 0
```

```bash
sudo sysctl --system
```

---

## Phase 2: Install Docker

### 2.1 Install Docker Engine

Follow the official instructions (do not use the distro's potentially outdated package):

```bash
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

### 2.2 Add deploy user to docker group

```bash
sudo usermod -aG docker deploy
```

Log out and back in as `deploy` for the group change to take effect.

### 2.3 Harden the Docker daemon

Create `/etc/docker/daemon.json`:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "no-new-privileges": true,
  "userns-remap": "default"
}
```

This enables:
- **Log rotation**: Prevents logs from filling the disk (critical on a small VM).
- **No new privileges**: Containers cannot gain additional privileges via setuid/setgid.
- **User namespace remapping**: Container root maps to an unprivileged host UID.

> **Note on userns-remap**: If you encounter permission issues with volume mounts after
> enabling this, you may need to adjust directory ownership or remove `"userns-remap": "default"`
> and rely on the other mitigations instead. Test this early.

```bash
sudo systemctl restart docker
```

---

## Phase 3: Generate Secrets

Do this *before* creating any config files. Every secret is generated once and stored in a
single `.env` file with restricted permissions.

```bash
# Work in the deploy user's home
mkdir -p ~/calcom && cd ~/calcom

# Generate secrets
NEXTAUTH_SECRET=$(openssl rand -base64 32)
CALENDSO_ENCRYPTION_KEY=$(openssl rand -base64 24)
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d '=+/' | head -c 32)
REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d '=+/' | head -c 32)

# Write .env file
cat > .env << EOF
# Cal.com secrets — generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Permissions on this file must be 0600. Do not commit to version control.

# Domain
NEXT_PUBLIC_WEBAPP_URL=https://cal.example.com
NEXTAUTH_URL=https://cal.example.com/api/auth

# Database
POSTGRES_USER=calcom
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=calendso
DATABASE_HOST=database
DATABASE_URL=postgresql://calcom:${POSTGRES_PASSWORD}@database:5432/calendso

# Redis
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_URL=redis://default:${REDIS_PASSWORD}@redis:6379

# Auth & encryption
NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
CALENDSO_ENCRYPTION_KEY=${CALENDSO_ENCRYPTION_KEY}

# Telemetry (opt out)
CALCOM_TELEMETRY_DISABLED=1

# Content Security Policy
CSP_POLICY=non-strict

# License consent (required to run)
NEXT_PUBLIC_LICENSE_CONSENT=agree
EOF

# Lock down file permissions
chmod 600 .env
```

**Replace `cal.example.com`** with your actual domain in the two URL variables.

---

## Phase 4: Docker Compose Configuration

Create `~/calcom/docker-compose.yml`:

```yaml
networks:
  internal:
    driver: bridge
    internal: true
  web:
    driver: bridge

services:
  database:
    image: postgres:16-alpine
    restart: unless-stopped
    networks:
      - internal
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_INITDB_ARGS: "--auth-host=scram-sha-256"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          memory: 512M

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    networks:
      - internal
    volumes:
      - redis_data:/data
    command: >
      redis-server
      --requirepass ${REDIS_PASSWORD}
      --maxmemory 128mb
      --maxmemory-policy allkeys-lru
      --rename-command FLUSHALL ""
      --rename-command FLUSHDB ""
      --rename-command DEBUG ""
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          memory: 192M

  calcom:
    image: calcom/cal.com:latest
    restart: unless-stopped
    networks:
      - internal
      - web
    expose:
      - "3000"
    env_file: .env
    environment:
      DATABASE_URL: ${DATABASE_URL}
      DATABASE_DIRECT_URL: ${DATABASE_URL}
      REDIS_URL: ${REDIS_URL}
      NEXTAUTH_SECRET: ${NEXTAUTH_SECRET}
      CALENDSO_ENCRYPTION_KEY: ${CALENDSO_ENCRYPTION_KEY}
      NEXT_PUBLIC_WEBAPP_URL: ${NEXT_PUBLIC_WEBAPP_URL}
      NEXTAUTH_URL: ${NEXTAUTH_URL}
      CALCOM_TELEMETRY_DISABLED: ${CALCOM_TELEMETRY_DISABLED}
      CSP_POLICY: ${CSP_POLICY}
      NEXT_PUBLIC_LICENSE_CONSENT: ${NEXT_PUBLIC_LICENSE_CONSENT}
      NODE_ENV: production
    depends_on:
      database:
        condition: service_healthy
      redis:
        condition: service_healthy
    deploy:
      resources:
        limits:
          memory: 1536M

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    networks:
      - web
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - calcom
    deploy:
      resources:
        limits:
          memory: 128M

volumes:
  postgres_data:
  redis_data:
  caddy_data:
  caddy_config:
```

### Key security decisions in this compose file

| Decision | Why |
|----------|-----|
| **Two networks (`internal` + `web`)** | `database` and `redis` are on `internal` only — they have no route to the internet or to the host. Only `calcom` bridges both networks. `caddy` is on `web` only. |
| **No `ports:` on database/redis** | Nothing is published to the host. These services are only reachable from other containers on the `internal` network. |
| **`expose: "3000"` on calcom** | Makes port 3000 visible to other containers on shared networks, but does *not* publish it to the host. Only Caddy can reach it. |
| **Pinned image tags** | `postgres:16-alpine`, `redis:7-alpine`, `caddy:2-alpine`. Avoid `:latest` for infrastructure images to prevent unexpected breaking changes. Cal.com uses `:latest` because they don't publish stable semver tags for the Docker image — pin to a specific digest once you've verified a working version (see Phase 7). |
| **Health checks** | Compose waits for database and Redis to be healthy before starting Cal.com, preventing startup crashes. |
| **Memory limits** | Total ~2.4GB, leaving headroom for the OS and Docker overhead on a 3GB VM. |
| **Redis hardened** | Password required, dangerous commands renamed away, memory capped with LRU eviction. |
| **Postgres SCRAM-SHA-256** | Uses the stronger password hashing algorithm instead of the older MD5 default. |
| **No Prisma Studio** | Prisma Studio is a database admin UI with no authentication. It must not run in production. If you need to inspect the database, use `docker compose exec database psql` over SSH. |

---

## Phase 5: Configure the Reverse Proxy (Caddy)

Create `~/calcom/Caddyfile`:

```
cal.example.com {
    reverse_proxy calcom:3000

    header {
        # HSTS — tell browsers to always use HTTPS
        Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"

        # Prevent clickjacking
        X-Frame-Options "SAMEORIGIN"

        # Prevent MIME-type sniffing
        X-Content-Type-Options "nosniff"

        # Referrer policy
        Referrer-Policy "strict-origin-when-cross-origin"

        # Permissions policy — disable unused browser features
        Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()"

        # Remove server identification
        -Server
    }

    # Rate limit login/auth endpoints (requires caddy-ratelimit plugin, optional)
    # If using the standard Caddy image without plugins, remove this block
    # rate_limit {
    #     zone auth_zone {
    #         key {remote_host}
    #         events 10
    #         window 1m
    #     }
    #     match path /api/auth/*
    # }

    log {
        output file /data/access.log {
            roll_size 10mb
            roll_keep 5
        }
    }
}
```

**Replace `cal.example.com`** with your actual domain.

Caddy automatically obtains and renews TLS certificates from Let's Encrypt. No manual
certificate management is needed. It also automatically redirects HTTP to HTTPS.

---

## Phase 6: Deploy

### 6.1 Pull images first

```bash
cd ~/calcom
docker compose pull
```

This downloads all images before starting anything, so you can verify disk space and
image integrity.

### 6.2 Start the stack

```bash
docker compose up -d
```

### 6.3 Verify

```bash
# All containers should be "Up" and healthy
docker compose ps

# Check Cal.com logs for startup errors
docker compose logs calcom --tail 100

# Test HTTPS (from your local machine, not the VM)
curl -I https://cal.example.com
```

You should see a `200` response with the security headers from the Caddyfile.

### 6.4 Create your admin account

Navigate to `https://cal.example.com` in a browser. Cal.com will present the setup wizard
on first launch. Create your admin account with a strong, unique password.

---

## Phase 7: Post-Deployment Hardening

### 7.1 Pin the Cal.com image digest

Once you've verified the deployment works, pin the exact image to prevent supply-chain
drift:

```bash
# Get the current digest
docker inspect --format='{{index .RepoDigests 0}}' $(docker compose images calcom -q)
```

Update `docker-compose.yml` to use the digest:

```yaml
  calcom:
    image: calcom/cal.com@sha256:<the-digest-you-got>
```

### 7.2 Set up automated backups

Create `~/calcom/backup.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="$HOME/calcom/backups"
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
RETENTION_DAYS=14

mkdir -p "$BACKUP_DIR"

# Dump database
docker compose -f "$HOME/calcom/docker-compose.yml" exec -T database \
  pg_dump -U "${POSTGRES_USER:-calcom}" -d "${POSTGRES_DB:-calendso}" --no-password \
  | gzip > "$BACKUP_DIR/db-${TIMESTAMP}.sql.gz"

# Encrypt the backup (uses your GPG key — set this up first)
# gpg --encrypt --recipient your-email@example.com "$BACKUP_DIR/db-${TIMESTAMP}.sql.gz"
# rm "$BACKUP_DIR/db-${TIMESTAMP}.sql.gz"

# Prune old backups
find "$BACKUP_DIR" -name "db-*.sql.gz*" -mtime +${RETENTION_DAYS} -delete

echo "Backup completed: db-${TIMESTAMP}.sql.gz"
```

```bash
chmod 700 ~/calcom/backup.sh
```

Add a cron job (as the `deploy` user):

```bash
crontab -e
```

```
0 3 * * * /home/deploy/calcom/backup.sh >> /home/deploy/calcom/backups/cron.log 2>&1
```

For off-site backup, copy the encrypted dumps to a remote location (rsync over SSH,
S3-compatible storage, etc.).

### 7.3 Set up log monitoring

Check container health and resource usage:

```bash
# Resource usage
docker stats --no-stream

# Check for OOM kills
docker compose ps
docker inspect --format='{{.State.OOMKilled}}' $(docker compose ps -q)
```

### 7.4 Updates procedure

```bash
cd ~/calcom

# Pull new images
docker compose pull

# Note the new digest before deploying
docker compose images

# Deploy
docker compose up -d

# Verify
docker compose ps
docker compose logs calcom --tail 50
```

If something breaks, roll back by specifying the previous pinned digest in
`docker-compose.yml` and running `docker compose up -d` again.

---

## Phase 8: Ongoing Maintenance Checklist

- [ ] **Weekly**: Check `docker compose ps` and `docker stats` for health
- [ ] **Weekly**: Review Caddy access logs for anomalies (`~/calcom/caddy_data/` or via `docker compose logs caddy`)
- [ ] **Monthly**: Run `sudo apt update && sudo apt upgrade` for OS patches
- [ ] **Monthly**: Pull and test updated Cal.com images
- [ ] **Monthly**: Verify backups by restoring to a test database
- [ ] **Quarterly**: Rotate `POSTGRES_PASSWORD` and `REDIS_PASSWORD` (update `.env`, restart services)
- [ ] **Quarterly**: Review `fail2ban-client status sshd` for brute-force trends

---

## Architecture Diagram

```
Internet
    │
    ▼
┌──────────────────────────────────────────┐
│  Host VM (UFW: only 22, 80, 443 open)   │
│                                          │
│  ┌─────────────────────────────────────┐ │
│  │  Docker                             │ │
│  │                                     │ │
│  │  ┌──────┐    "web" network          │ │
│  │  │Caddy │◄──── :80, :443 ──────────►│─┼──► Internet
│  │  └──┬───┘                           │ │
│  │     │ reverse_proxy :3000           │ │
│  │  ┌──▼─────┐                         │ │
│  │  │Cal.com │  "web" + "internal"     │ │
│  │  └──┬──┬──┘                         │ │
│  │     │  │     "internal" network     │ │
│  │  ┌──▼──┴──┐  (no external access)   │ │
│  │  │  PG  Redis                       │ │
│  │  └────────┘                         │ │
│  └─────────────────────────────────────┘ │
└──────────────────────────────────────────┘
```

---

## Security Summary

| Layer | Measure |
|-------|---------|
| **SSH** | Key-only auth, root login disabled, fail2ban |
| **Firewall** | UFW: only 22/80/443 open; DB and Redis unreachable from network |
| **TLS** | Caddy auto-provisions Let's Encrypt certs; HSTS enabled |
| **Secrets** | Generated with `openssl rand`; stored in `.env` with `chmod 600` |
| **Network isolation** | Two Docker networks; DB and Redis on `internal` only |
| **Database** | SCRAM-SHA-256 auth; no port published; strong random password |
| **Redis** | Password required; dangerous commands disabled; memory capped |
| **Docker** | No-new-privileges; log rotation; memory limits per container |
| **Headers** | HSTS, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy |
| **Updates** | Unattended OS security updates; image pinning with controlled upgrade path |
| **Backups** | Daily automated `pg_dump` with retention policy; encryption-ready |
| **No Prisma Studio** | Database admin UI removed; use `psql` over SSH if needed |

---

## Troubleshooting

### Cal.com won't start / restarts in a loop

```bash
docker compose logs calcom --tail 200
```

Common causes:
- Database not ready yet (health check should prevent this, but check)
- Missing or malformed environment variables in `.env`
- Encryption key not exactly 24 base64 characters (32 bytes)

### Can't reach the site over HTTPS

1. Verify DNS resolves: `dig cal.example.com`
2. Check Caddy logs: `docker compose logs caddy`
3. Verify UFW allows 80+443: `sudo ufw status`
4. Check that Caddy can reach calcom: `docker compose exec caddy wget -qO- http://calcom:3000`

### Out of memory

Check which container is using the most:

```bash
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}"
```

If Cal.com exceeds its limit, increase the memory limit in `docker-compose.yml` or add
swap space to the VM:

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### Need to inspect the database

Do **not** run Prisma Studio in production. Instead:

```bash
docker compose exec database psql -U calcom -d calendso
```
