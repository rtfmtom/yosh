# Cal.com Docker Setup Guide

## Overview
This guide walks through setting up Cal.com (calendso) using Docker Compose with PostgreSQL and Redis.

## Prerequisites
- Docker and Docker Compose installed
- Ports 3000, 5432, 5555, 6379 available

## Setup Steps

### 1. Create docker-compose.yml

```yaml
version: '3.8'

services:
  database:
    image: postgres:16
    restart: always
    environment:
      POSTGRES_USER: unicorn_user
      POSTGRES_PASSWORD: magical_password
      POSTGRES_DB: calendso
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:alpine
    restart: always
    ports:
      - "6379:6379"

  calendso:
    image: calcom/cal.com:latest
    restart: always
    ports:
      - "3000:3000"
    environment:
      DATABASE_URL: "postgresql://unicorn_user:magical_password@database:5432/calendso"
      REDIS_URL: "redis://redis:6379"
      NEXTAUTH_SECRET: "change-this-to-a-random-string"
      CALENDSO_ENCRYPTION_KEY: "change-this-too"
    depends_on:
      - database
      - redis

  prisma-studio:
    image: calcom/cal.com:latest
    restart: always
    ports:
      - "5555:5555"
    environment:
      DATABASE_URL: "postgresql://unicorn_user:magical_password@database:5432/calendso"
    command: npx prisma studio
    depends_on:
      - database

volumes:
  postgres_data:
```

### 2. Deploy the Stack

```bash
# Start all services
docker-compose up -d

# Check status
docker ps

# View logs
docker-compose logs -f
```

### 3. Verify Deployment

```bash
# Check if Cal.com is responding
curl http://localhost:3000

# Check container stats
docker stats
```

### 4. Access Services

- **Cal.com**: http://localhost:3000
- **Prisma Studio**: http://localhost:5555 (database management UI)

### 5. Management Commands

```bash
# Stop all services
docker-compose down

# Stop and remove volumes (fresh start)
docker-compose down -v

# View logs for specific service
docker logs database
docker logs calendso
```

## Database Details

- **Host**: localhost:5432
- **Database**: calendso
- **User**: unicorn_user
- **Password**: magical_password

## Notes

- Change NEXTAUTH_SECRET and CALENDSO_ENCRYPTION_KEY in production
- Prisma Studio (port 5555) is optional for production environments
- Data persists in the `postgres_data` Docker volume
