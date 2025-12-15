# Deployment Guide

- [Overview](#overview)
  - [Architecture](#architecture)
- [Prerequisites](#prerequisites)
  - [Required Software](#required-software)
  - [System Requirements](#system-requirements)
- [Environment Configuration](#environment-configuration)
  - [Backend Environment Variables](#backend-environment-variables)
  - [Frontend Environment Variables](#frontend-environment-variables)
- [Development Deployment](#development-deployment)
  - [Local Development](#local-development)
- [Production Deployment](#production-deployment)
  - [Using Docker Compose](#using-docker-compose)
  - [Building Docker Images](#building-docker-images)
  - [Manual Deployment](#manual-deployment)
    - [Backend Deployment](#backend-deployment)
    - [Frontend Deployment](#frontend-deployment)
- [Database Setup](#database-setup)
  - [Running Migrations](#running-migrations)
  - [Seeding Data](#seeding-data)
- [Nginx Configuration](#nginx-configuration)
- [SSL/TLS Setup](#ssltls-setup)
  - [Using Let's Encrypt](#using-lets-encrypt)
  - [SSL Security Configuration](#ssl-security-configuration)
- [Monitoring](#monitoring)
  - [Health Checks](#health-checks)
  - [Prometheus Metrics](#prometheus-metrics)
- [Backup \& Recovery](#backup--recovery)
  - [Database Backup](#database-backup)


## Overview

The PXL Shelfware Tracker can be deployed using several methods:
- **Manual**: For custom setups or specific requirements
- **Docker Compose**: Recommended for easy deployment
- **Kubernetes** :^)
- **Cloud Platforms**: AWS, Azure, Google Cloud, etc.

### Architecture
```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│   Nginx     │---->│   Frontend   │---->│   Backend    │
│  (Reverse   │     │   (React)    │     │  (Express)   │
│   Proxy)    │     │   Port 80    │     │  Port 3001   │
└─────────────┘     └──────────────┘     └──────────────┘
                                                 |
                                          ┌──────▼──────┐
                                          │ PostgreSQL  │
                                          │ Port 5432   │
                                          └─────────────┘
```

## Prerequisites

### Required Software
- Docker & Docker Compose (for containerized deployment)
- Node.js 18+ (for manual deployment)
- PostgreSQL 15+ (for database)
- Nginx (for reverse proxy)

### System Requirements
- **Minimum**: 1 CPU, 2GB RAM, 10GB storage

## Environment Configuration

### Backend Environment Variables

Create a `.env` file in the backend directory:

```env
[deleted]
```

**Production JWT Secret Generation:**
```bash
# Generate a secure random string
openssl rand -base64 32
# or
node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
```

### Frontend Environment Variables

Create a `.env` file in the frontend directory:

```env
[deleted]
```

## Development Deployment

### Local Development

1. **Start the database:**
   ```bash
   docker compose up -d db
   ```

2. **Backend DEV setup:**
   ```bash
   cd backend
   npm install
   npx prisma generate
   npx prisma migrate dev
   npm run seed  # Optional: add demo data
   npm run dev
   ```

3. **Frontend DEV setup:**
   ```bash
   cd frontend
   npm install
   npm run dev
   ```

4. **Access the application:**
   - Frontend: http://localhost:5173
   - Backend API: http://localhost:3001
   - Database: localhost:5432

## Production Deployment

### Using Docker Compose

1. **Create production compose file (`compose.prod.yml`):**
   ```yaml
   [deleted]
   ```

2. **Create `.env.prod` file:**
   ```env
   [deleted]
   ```

3. **Deploy:**
   ```bash
   docker compose -f compose.prod.yml --env-file .env.prod up -d
   ```

### Building Docker Images

**Backend Dockerfile:**
```dockerfile
[deleted]
```

**Frontend Dockerfile:**
```dockerfile
[deleted]
```

### Manual Deployment

#### Backend Deployment

1. **Server setup (Ubuntu/Debian):**
   ```bash
   [deleted]
   ```

2. **Deploy backend:**
   ```bash
   [deleted]
   ```

#### Frontend Deployment

1. **Build frontend:**
   ```bash
   [deleted]
   ```

2. **Setup Nginx:**
   ```bash
   [deleted]
   ```

## Database Setup

### Running Migrations

**Development:**
```bash
# Create new migration
npx prisma migrate dev --name migration_name

# Apply migrations
npx prisma migrate dev
```

**Production:**
```bash
# Apply migrations only (no schema changes)
npx prisma migrate deploy

# Check migration status
npx prisma migrate status
```

### Seeding Data

**Development seed:**
```bash
npm run seed
```

**Production seed (if needed):**
```bash
# Be careful - this adds demo data
NODE_ENV=production npm run seed
```

**Custom seed script:**
```typescript
// prisma/seed-production.ts
import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcrypt';

const prisma = new PrismaClient();

async function main() {
  // Create admin user
  const adminPassword = process.env.ADMIN_PASSWORD || 'changeme';
  const hashedPassword = await bcrypt.hash(adminPassword, 10);
  
  await prisma.user.create({
    data: {
      email: 'admin@yourdomain.com',
      password: hashedPassword,
      name: 'Administrator'
    }
  });
  
  console.log('Admin user created');
}

main()
  .catch(console.error)
  .finally(() => prisma.$disconnect());
```

## Nginx Configuration

**Basic configuration (`/etc/nginx/sites-available/shelfware`):**
```nginx
[deleted]
```

## SSL/TLS Setup

### Using Let's Encrypt

```bash
[deleted]
```

### SSL Security Configuration

Add to Nginx configuration:
```nginx
[deleted]
```

## Monitoring

### Health Checks

**Backend health endpoint:**
```bash
# Check if service is up
curl http://localhost:3001/health
# Response: {"status":"UP"}

# Check if ready (database connected)
curl http://localhost:3001/ready
# Response: {"status":"READY","checks":{"database":"OK"}}
```

### Prometheus Metrics

1. **Configure Prometheus (`prometheus.yml`):**
   ```yaml
   [deleted]
   ```

2. **Useful metrics to monitor:**
   - Request duration: `http_request_duration_ms`
   - Request count: `http_requests_total`
   - Error rate: `rate(http_requests_total{code=~"5.."}[5m])`
   - Memory usage: `process_resident_memory_bytes`
   - CPU usage: `process_cpu_user_seconds_total`

3. **Grafana dashboard example:**
   ```json
   [deleted]
   ```

## Backup & Recovery

### Database Backup

**Automated backup script:**
```bash
[deleted]
```

**Restore from backup:**
```bash
[deleted]
```
