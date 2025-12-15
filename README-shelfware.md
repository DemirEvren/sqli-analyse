# PXL Shelfware Tracker

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A full-stack application designed to help developers and creators track their personal projects, side ventures, and brilliant ideas that might otherwise end up on the "shelf". Never forget about your half-finished projects again!

![Screenshot](assets/screenshot1.png)

## Motivation

How many great ideas or side projects have you started, only to forget the details, lose the links, or abandon them halfway? Shelfware Tracker provides a simple, centralized place to manage your project portfolio, keeping all the essential information organized and accessible.

## Features

- Project management dashboard
- Status tracking (Planning, In Progress, Completed, Abandoned)
- User authentication with JWT
- Project links to GitHub, deployed apps, and documentation
- Hardware/component information storage (JSON)
- Search and filter capabilities
- RESTful API
- Responsive design
- Light/dark theme

## Contents

- [Motivation](#motivation)
- [Features](#features)
- [Contents](#contents)
- [Tech Stack](#tech-stack)
  - [Backend](#backend)
  - [Database](#database)
  - [Frontend](#frontend)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Environment Variables Setup](#environment-variables-setup)
    - [Backend Environment Variables](#backend-environment-variables)
    - [Frontend Environment Variables](#frontend-environment-variables)
  - [1. Database Setup](#1-database-setup)
  - [2. Backend Setup](#2-backend-setup)
  - [3. Frontend Setup](#3-frontend-setup)
  - [4. Verifying Setup](#4-verifying-setup)
- [Authentication](#authentication)
- [API Endpoints](#api-endpoints)
  - [Authentication Endpoints](#authentication-endpoints)
  - [Project Endpoints](#project-endpoints)
  - [Health \& Monitoring](#health--monitoring)
- [Monitoring with Prometheus Metrics](#monitoring-with-prometheus-metrics)
- [Production Deployment](#production-deployment)
  - [Using Docker Compose](#using-docker-compose)
  - [Manual Deployment](#manual-deployment)
    - [Backend](#backend-1)
    - [Frontend](#frontend-1)
    - [Database](#database-1)
- [Testing the API](#testing-the-api)
  - [Using cURL](#using-curl)
- [Project Structure](#project-structure)
- [Environment Variables in Production](#environment-variables-in-production)
- [Running Tests](#running-tests)
  - [Backend Tests](#backend-tests)
- [Deployment Notes](#deployment-notes)
- [License](#license)


## Tech Stack

### Backend
- [Node.js](https://nodejs.org/) with [Express](https://expressjs.com/)
- [TypeScript](https://www.typescriptlang.org/)
- [Prisma ORM](https://www.prisma.io/) for database interaction
- [Passport.js](https://www.passportjs.org/) for authentication
- [JWT](https://jwt.io/) for secure tokens
- [Prometheus Client](https://github.com/siimon/prom-client) for metrics

### Database
- [PostgreSQL](https://www.postgresql.org/)

### Frontend
- [React](https://reactjs.org/)
- [TypeScript](https://www.typescriptlang.org/)
- [React Router](https://reactrouter.com/) for navigation
- [Axios](https://axios-http.com/) for API communication
- CSS for styling

## Getting Started

### Prerequisites

- [Node.js](https://nodejs.org/) (v18 or later recommended)
- [npm](https://www.npmjs.com/) or [yarn](https://yarnpkg.com/)
- [Docker](https://www.docker.com/) and [Docker Compose](https://docs.docker.com/compose/) (for database setup)

### Environment Variables Setup

This project uses environment variables for configuration. Here's what you need to know:

#### Backend Environment Variables

The backend **requires** a `.env` file. An example is provided:

```bash
cd backend
cp .env.example .env
```

Required variables in `.env`:
- `DATABASE_URL` - PostgreSQL connection string
- `JWT_SECRET` - Secret key for JWT tokens (**Change this in production!**)
- `BACKEND_PORT` - Port for the backend server (default: 3001)
- `CORS_ORIGIN` - Allowed origins for CORS (default: http://localhost:5173)

#### Frontend Environment Variables

The frontend has optional environment variables. If not provided, it defaults to `http://localhost:3001` for the API:

```bash
cd frontend
# Optional: Create .env file
echo "VITE_API_URL=http://localhost:3001/api" > .env
```

You only need to create this file if:
- Your backend runs on a different port
- You're deploying to production with a different API URL

### 1. Database Setup

The quickest way to get started is using Docker to set up PostgreSQL:

```bash
# Start the PostgreSQL container
docker compose up -d
```

This will start a PostgreSQL instance with the following configuration:
- Port: 5432
- Username: postgres
- Password: postgres
- Database: shelfware

### 2. Backend Setup

```bash
# Navigate to backend directory
cd backend

# Install dependencies
npm install

# Create .env file from example (REQUIRED)
cp .env.example .env
```

Edit the `.env` file if needed. The default values work with the Docker setup:
```env
# Database connection (works with Docker setup)
DATABASE_URL="postgresql://postgres:postgres@localhost:5432/shelfware?schema=public"

# JWT Secret - IMPORTANT: Generate a secure random string for production!
# However, for PXL exam assignments, this hardcoded value can stay
JWT_SECRET="c3a68d7c-dc34-4e5f-bf1a-705062c81c53"

# Server configuration
BACKEND_PORT=3001

# CORS - Frontend URL
CORS_ORIGIN=http://localhost:5173
```

Then continue with setup:

```bash
# Generate Prisma client
npx prisma generate

# Run database migrations
npx prisma migrate dev

# Seed the database with demo data (creates users AND projects)
npm run seed

# Start the development server
npm run dev

# For production deployment (no TypeScript compilation needed):
npx ts-node src/server.ts
```

The backend should now be running at http://localhost:3001.

**Note:** The backend runs TypeScript directly using `ts-node`. There's no build/compilation step needed for the backend.

### 3. Frontend Setup

```bash
# Navigate to frontend directory
cd ../frontend

# Install dependencies
npm install

# Create .env file if using non-default API URL
# For local development (backend on same machine):
echo "VITE_API_URL=http://localhost:3001/api" > .env

# For Docker development (e.g. if backend runs in container):
echo "VITE_API_URL=http://backend:3001/api" > .env

# Start the development server
npm run dev

# For production build:
npm run build
# This creates a 'dist' folder with static files to serve via nginx
```

The frontend will be available at http://localhost:5173 (development) or needs to be served via nginx (production).

**Note:** The frontend includes an `nginx.conf` file for production deployments.

### 4. Verifying Setup

To verify everything is working correctly:

1. **Check backend health**: Open http://localhost:3001/health - should show `{"status":"UP"}`
2. **Check database connection**: Open http://localhost:3001/ready - should show `{"status":"READY","checks":{"database":"OK"}}`
3. **Check frontend**: Open http://localhost:5173 - should display the PXL Shelfware Tracker application
4. **Try logging in** with the demo account (created by `npm run seed`):
   - Email: `demo@example.com`
   - Password: `password123`

## Authentication

The application implements token-based authentication using JWT. Demo accounts are created when you run the seed script:

```bash
# From the backend directory
npm run seed
```

This creates the following test accounts:
- **Demo User**
  - Email: `demo@example.com`
  - Password: `password123`

- **Admin User**
  - Email: `admin@example.com`
  - Password: `admin123`

The seed script also creates sample projects assigned to the `demo` user.

## API Endpoints

### Authentication Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | /api/auth/register | Register a new user |
| POST | /api/auth/login | Login and get JWT token |
| GET | /api/auth/profile | Get the current user's profile |

### Project Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /api/projects | Get all projects (authenticated users see only their own) |
| GET | /api/projects/:id | Get a specific project by ID |
| POST | /api/projects | Create a new project |
| PUT | /api/projects/:id | Update an existing project |
| DELETE | /api/projects/:id | Delete a project |

### Health & Monitoring

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /health | Liveness check (application is running) |
| GET | /ready | Readiness check (database is connected) |
| GET | /metrics | Prometheus metrics |

## Monitoring with Prometheus Metrics

The `/metrics` endpoint exposes application metrics in Prometheus format for monitoring and alerting. These include:

**Default Metrics:**
- Process metrics (CPU usage, memory usage, heap statistics)
- Node.js runtime metrics (active handles, garbage collection stats)
- System metrics (load average, uptime)

**Custom Application Metrics:**
- `http_request_duration_ms` - Histogram tracking request latency in milliseconds
  - Buckets: 50ms, 100ms, 200ms, 500ms, 1s, 2.5s, 5s
  - Labels: method, route, status code
- `http_requests_total` - Counter for total HTTP requests
  - Labels: method, route, status code

These metrics can be scraped by a Prometheus server to monitor application performance, track error rates, and set up alerts for anomalies.

## Production Deployment

### Using Docker Compose

The easiest way to deploy all components:

```bash
# Start all services
docker compose up -d

# The application will be available at:
# - Frontend: http://localhost:8080
# - Backend API: http://localhost:3001
# - Database: localhost:5432
```

### Manual Deployment

#### Backend
```bash
cd backend
npm install
npx prisma generate
npx prisma migrate deploy  # For production
npx ts-node src/server.ts   # No build step needed
```

#### Frontend
```bash
cd frontend
npm install
npm run build              # Creates 'dist' folder
# Serve the 'dist' folder with nginx using the provided nginx.conf
```

#### Database
- Ensure PostgreSQL is running
- Run migrations: `npx prisma migrate deploy`
- (Optional) Seed data: `npm run seed`

## Testing the API

### Using cURL

Register a new user:
```bash
curl -X POST http://localhost:3001/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123","name":"Test User"}'
```

Login to get a token:
```bash
curl -X POST http://localhost:3001/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}'
```

Create a project (replace YOUR_TOKEN with the token from login):
```bash
curl -X POST http://localhost:3001/api/projects \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{"title":"API Test Project","description":"Created via API","status":"Planning","hardwareInfo":{"platform":"Node.js","database":"PostgreSQL"}}'
```

## Project Structure

```
shelfware/
├── backend/              # Node.js/Express API Server
│   ├── prisma/           # Prisma schema, migrations, seed script
│   │   ├── migrations/
│   │   ├── schema.prisma # Database schema
│   │   └── seed.ts       # Seeds both users and projects
│   ├── src/
│   │   ├── config/       # Configuration (passport, JWT)
│   │   ├── controllers/  # Request handlers
│   │   ├── middleware/   # Authentication middleware
│   │   ├── routes/       # Route definitions
│   │   └── server.ts     # Main server file
│   ├── tests/            # Unit and integration tests
│   ├── Dockerfile        # Docker configuration for backend
│   ├── .env.example      # Environment variables template
│   └── .env              # Your local environment variables (create from .env.example)
│
├── frontend/             # React Frontend Application
│   ├── public/           # Static assets including favicon
│   ├── src/
│   │   ├── assets/       # Images and other assets
│   │   ├── components/   # Reusable UI components
│   │   ├── context/      # React context (authentication)
│   │   ├── interfaces/   # TypeScript interfaces
│   │   ├── pages/        # Application pages
│   │   ├── services/     # API communication
│   │   └── utils/        # Helper functions
│   ├── nginx.conf        # Nginx configuration for production
│   ├── Dockerfile        # Docker configuration for frontend
│   ├── index.html        # HTML entry point
│   └── .env              # (Optional) Frontend environment variables
│
├── compose.yml           # Docker Compose configuration
├── docs/                 # Additional documentation
└── README.md             # This file
```

## Environment Variables in Production

For production deployments (non-Docker), adjust the environment variables:

**Backend `.env`:**
```env
DATABASE_URL="postgresql://user:password@your-db-host:5432/shelfware?schema=public"
BACKEND_PORT=3001
CORS_ORIGIN=https://your-frontend-domain.com
JWT_SECRET="generate-a-secure-random-string"
```

**Frontend `.env`:**
```env
VITE_API_URL=https://your-api-domain.com/api
```

**Security Note:** The JWT_SECRET in `.env.example` is for development only. Always generate a new secure secret for production deployments.

## Running Tests

### Backend Tests

```bash
# Make sure you're in the backend directory
cd backend

# Run all tests
npm test

# Run tests with coverage report
npm test -- --coverage
```

For more details on testing, including how to write tests for authenticated endpoints, see the test files in the `backend/tests` directory.

## Deployment Notes

- **Backend**: Runs TypeScript directly with ts-node, no compilation needed
- **Frontend**: Must be built with `npm run build` before deployment
- **Database**: Use `npx prisma migrate deploy` for production migrations
- **Docker**: Full stack can be deployed with `docker compose up -d`
- **Ports**: Backend runs on `3001`, Frontend dev server on `5173`, Frontend production (nginx) on `80`/`8080`

## License

This project is licensed under the MIT License - see the LICENSE file for details.
