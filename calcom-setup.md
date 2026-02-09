# Cal.com Docker Setup Guide

## Prerequisites

- Docker and Docker-compose installed
- The cal.com repo cloned to `~/cal.com`
- An `.env` file (copied from `.env.example`)

## Step 1: Fix DATABASE_URL

Your `.env` has `localhost:5450` but inside docker-compose, containers
talk to each other by service name. Change it to `database:5432`:

```bash
cd ~/cal.com
sed -i 's|postgresql://postgres:@localhost:5450/calendso|postgresql://unicorn_user:unicorn_password@database:5432/calendso|g' .env
```

Replace `unicorn_user` and `unicorn_password` with whatever
`POSTGRES_USER` and `POSTGRES_PASSWORD` are set to in your
`docker-compose.yml`.

Verify:

```bash
grep DATABASE_URL .env
```

Expected output:

```
DATABASE_URL="postgresql://unicorn_user:unicorn_password@database:5432/calendso"
DATABASE_DIRECT_URL="postgresql://unicorn_user:unicorn_password@database:5432/calendso"
```

## Step 2: Generate secrets

Check if they are already set:

```bash
grep NEXTAUTH_SECRET .env
grep CALENDSO_ENCRYPTION_KEY .env
```

If empty, generate and paste them in:

```bash
openssl rand -base64 32
# copy output, set as NEXTAUTH_SECRET in .env

openssl rand -base64 24
# copy output, set as CALENDSO_ENCRYPTION_KEY in .env
```

## Step 3: Set NEXTAUTH_URL

In `.env`, set this to however you access the server:

```
NEXTAUTH_URL=http://localhost:3000
```

Or if accessing remotely, use your server's IP or hostname:

```
NEXTAUTH_URL=http://your-server-ip:3000
```

## Step 4: Start the services

```bash
cd ~/cal.com
docker-compose up -d
```

## Step 5: Check logs

```bash
docker-compose logs -f calcom
```

## Step 6: Access cal.com

Open `http://your-server:3000` in a browser.

## Why localhost doesn't work

Docker-compose creates an internal network (called `stack`).
Inside that network, containers find each other by service name:

- PostgreSQL is at hostname `database` on port `5432`
- Redis is at hostname `redis` on port `6379`

`localhost` inside a container refers to that container itself,
not the host machine or other containers. That's why your
DATABASE_URL must use `database` instead of `localhost`.

## Default docker-compose credentials

These are the defaults from the cal.com docker-compose.yml.
Check your file to confirm:

| Variable          | Default Value    |
|-------------------|------------------|
| POSTGRES_USER     | unicorn_user     |
| POSTGRES_PASSWORD | unicorn_password |
| POSTGRES_DB       | calendso         |
