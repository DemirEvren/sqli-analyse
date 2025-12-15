# API Documentation

- [Base URL](#base-url)
- [Authentication](#authentication)
  - [Authentication Flow:](#authentication-flow)
  - [Authentication Strategies:](#authentication-strategies)
- [Response Format](#response-format)
  - [Success Response](#success-response)
  - [Error Response](#error-response)
- [Authentication Endpoints](#authentication-endpoints)
  - [Register User](#register-user)
  - [Login](#login)
  - [Get User Profile](#get-user-profile)
- [Project Endpoints](#project-endpoints)
  - [Get All Projects](#get-all-projects)
  - [Get Project by ID](#get-project-by-id)
  - [Create Project](#create-project)
  - [Update Project](#update-project)
  - [Delete Project](#delete-project)
- [Health \& Monitoring Endpoints](#health--monitoring-endpoints)
  - [Health Check](#health-check)
  - [Readiness Check](#readiness-check)
  - [Metrics](#metrics)
- [Error Handling](#error-handling)
  - [Status Codes](#status-codes)
  - [Error Response Format](#error-response-format)
  - [Prisma-Specific Error Codes](#prisma-specific-error-codes)
- [CORS Configuration](#cors-configuration)
- [Rate Limiting](#rate-limiting)
- [Examples](#examples)
  - [Complete Workflow Example](#complete-workflow-example)
  - [cURL Examples](#curl-examples)
  - [JavaScript/Axios Examples](#javascriptaxios-examples)

This document provides a comprehensive reference for the PXL Shelfware Tracker API endpoints.

## Base URL

All API endpoints are relative to:

```
Development: http://localhost:3001/api
Production: https://your-api-domain.com/api
```

The API base URL can be configured via the `VITE_API_URL` environment variable in the frontend.

## Authentication

The API uses JWT (JSON Web Tokens) for authentication. Most endpoints require authentication.

### Authentication Flow:
1. Register or login to obtain a JWT token
2. Include the token in the Authorization header for subsequent requests:
   ```
   Authorization: Bearer YOUR_JWT_TOKEN
   ```
3. Tokens expire after 7 days

### Authentication Strategies:
- **Local Strategy**: Email/password authentication for login
- **JWT Strategy**: Token-based authentication for API access

## Response Format

All responses are in JSON format with consistent structure.

### Success Response
```json
{
  "id": "clXXXXXXXXXXXXX",
  "title": "Project Example",
  "status": "In Progress",
  "description": "Project description",
  "githubUrl": "https://github.com/example/repo",
  "deployedUrl": "https://example.com",
  "docsUrl": "https://docs.example.com",
  "hardwareInfo": {
    "cpu": "Intel i7",
    "ram": "16GB"
  },
  "createdAt": "2023-01-01T00:00:00.000Z",
  "updatedAt": "2023-01-01T00:00:00.000Z",
  "userId": "clXXXXXXXXXXXXX"
}
```

### Error Response
```json
{
  "error": "Error message",
  "message": "Additional details (optional)"
}
```

## Authentication Endpoints

### Register User

Creates a new user account and returns a JWT token.

```
POST /auth/register
```

**Request Body**
```json
{
  "email": "user@example.com",
  "password": "password123",
  "name": "User Name"  // Optional
}
```

**Response (201 Created)**
```json
{
  "user": {
    "id": "clXXXXXXXXXXXXX",
    "email": "user@example.com",
    "name": "User Name",
    "createdAt": "2023-01-01T00:00:00.000Z",
    "updatedAt": "2023-01-01T00:00:00.000Z"
  },
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Error Responses**
- `400 Bad Request`: Email or password missing
- `400 Bad Request`: Email already in use
- `500 Internal Server Error`: Server error

**Validation Rules**
- Email must be valid format
- Password must be at least 6 characters (enforced by frontend)
- Email must be unique

### Login

Authenticates a user and returns a JWT token.

```
POST /auth/login
```

**Request Body**
```json
{
  "email": "user@example.com",
  "password": "password123"
}
```

**Response (200 OK)**
```json
{
  "user": {
    "id": "clXXXXXXXXXXXXX",
    "email": "user@example.com",
    "name": "User Name",
    "createdAt": "2023-01-01T00:00:00.000Z",
    "updatedAt": "2023-01-01T00:00:00.000Z"
  },
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Error Responses**
- `401 Unauthorized`: Invalid email or password

### Get User Profile

Returns the authenticated user's profile.

```
GET /auth/profile
```

**Headers**
```
Authorization: Bearer YOUR_JWT_TOKEN
```

**Response (200 OK)**
```json
{
  "id": "clXXXXXXXXXXXXX",
  "email": "user@example.com",
  "name": "User Name",
  "createdAt": "2023-01-01T00:00:00.000Z",
  "updatedAt": "2023-01-01T00:00:00.000Z"
}
```

**Error Responses**
- `401 Unauthorized`: Missing or invalid token

## Project Endpoints

### Get All Projects

Returns projects based on authentication status:
- **Authenticated**: Returns only the user's projects
- **Not authenticated**: Returns empty array (frontend handles this)

```
GET /projects
```

**Headers (Optional)**
```
Authorization: Bearer YOUR_JWT_TOKEN
```

**Query Parameters**
None currently implemented. Frontend handles filtering and search.

**Response (200 OK)**
```json
[
  {
    "id": "clXXXXXXXXXXXXX",
    "title": "Project 1",
    "description": "Project description",
    "status": "In Progress",
    "githubUrl": "https://github.com/user/project1",
    "deployedUrl": "https://project1.example.com",
    "docsUrl": "https://docs.project1.example.com",
    "hardwareInfo": { 
      "cpu": "Intel i7", 
      "ram": "16GB" 
    },
    "createdAt": "2023-01-01T00:00:00.000Z",
    "updatedAt": "2023-01-01T00:00:00.000Z",
    "userId": "clXXXXXXXXXXXXX"
  }
  // More projects...
]
```

**Notes**
- Uses `optionalAuth` middleware
- If authenticated, returns only projects where `userId` matches the authenticated user
- Results are ordered by `createdAt` in descending order (newest first)

### Get Project by ID

Returns a specific project. Authentication is required, and users can only access their own projects.

```
GET /projects/:id
```

**Headers**
```
Authorization: Bearer YOUR_JWT_TOKEN
```

**URL Parameters**
- `id`: Project ID (cuid format)

**Response (200 OK)**
```json
{
  "id": "clXXXXXXXXXXXXX",
  "title": "Project 1",
  "description": "Project description",
  "status": "In Progress",
  "githubUrl": "https://github.com/user/project1",
  "deployedUrl": "https://project1.example.com",
  "docsUrl": "https://docs.project1.example.com",
  "hardwareInfo": { 
    "cpu": "Intel i7", 
    "ram": "16GB" 
  },
  "createdAt": "2023-01-01T00:00:00.000Z",
  "updatedAt": "2023-01-01T00:00:00.000Z",
  "userId": "clXXXXXXXXXXXXX"
}
```

**Error Responses**
- `400 Bad Request`: Invalid project ID format
- `401 Unauthorized`: Not authenticated
- `403 Forbidden`: Project belongs to another user
- `404 Not Found`: Project not found

### Create Project

Creates a new project for the authenticated user.

```
POST /projects
```

**Headers**
```
Authorization: Bearer YOUR_JWT_TOKEN
Content-Type: application/json
```

**Request Body**
```json
{
  "title": "New Project",              // Required
  "status": "Planning",                // Required: Planning|In Progress|Completed|Abandoned
  "description": "Project description", // Optional
  "githubUrl": "https://github.com/user/project", // Optional
  "deployedUrl": "https://project.example.com",   // Optional
  "docsUrl": "https://docs.project.example.com",  // Optional
  "hardwareInfo": {                    // Optional: JSON object
    "cpu": "Intel i7",
    "ram": "16GB"
  }
}
```

**Response (201 Created)**
```json
{
  "id": "clXXXXXXXXXXXXX",
  "title": "New Project",
  "status": "Planning",
  "description": "Project description",
  "githubUrl": "https://github.com/user/project",
  "deployedUrl": "https://project.example.com",
  "docsUrl": "https://docs.project.example.com",
  "hardwareInfo": {
    "cpu": "Intel i7",
    "ram": "16GB"
  },
  "createdAt": "2023-01-01T00:00:00.000Z",
  "updatedAt": "2023-01-01T00:00:00.000Z",
  "userId": "clXXXXXXXXXXXXX"
}
```

**Error Responses**
- `400 Bad Request`: Missing required fields (title or status)
- `401 Unauthorized`: Not authenticated
- `500 Internal Server Error`: Server error

**Validation Notes**
- URLs are validated by frontend
- Hardware info must be valid JSON object
- Project is automatically associated with authenticated user

### Update Project

Updates an existing project. Authentication required, users can only update their own projects.

```
PUT /projects/:id
```

**Headers**
```
Authorization: Bearer YOUR_JWT_TOKEN
Content-Type: application/json
```

**URL Parameters**
- `id`: Project ID to update

**Request Body**
```json
{
  "title": "Updated Project",          // Required
  "status": "In Progress",             // Required
  "description": "Updated description", // Optional
  "githubUrl": "https://github.com/user/updated-project", // Optional
  "deployedUrl": "https://updated-project.example.com",   // Optional
  "docsUrl": "https://docs.updated-project.example.com",  // Optional
  "hardwareInfo": {                    // Optional
    "cpu": "Intel i9",
    "ram": "32GB"
  }
}
```

**Response (200 OK)**
Returns the updated project object (same format as GET /projects/:id)

**Error Responses**
- `400 Bad Request`: Missing required fields or invalid ID format
- `401 Unauthorized`: Not authenticated
- `403 Forbidden`: Project belongs to another user
- `404 Not Found`: Project not found

### Delete Project

Deletes a project. Authentication required, users can only delete their own projects.

```
DELETE /projects/:id
```

**Headers**
```
Authorization: Bearer YOUR_JWT_TOKEN
```

**URL Parameters**
- `id`: Project ID to delete

**Response (204 No Content)**
No response body on successful deletion.

**Error Responses**
- `400 Bad Request`: Invalid project ID format
- `401 Unauthorized`: Not authenticated
- `403 Forbidden`: Project belongs to another user
- `404 Not Found`: Project not found

## Health & Monitoring Endpoints

These endpoints are used for monitoring application health and do not require authentication.

### Health Check

Basic liveness check to verify the application is running.

```
GET /health
```

**Response (200 OK)**
```json
{
  "status": "UP"
}
```

### Readiness Check

Checks if the application is ready to handle requests, including database connectivity.

```
GET /ready
```

**Response (200 OK)**
```json
{
  "status": "READY",
  "checks": { 
    "database": "OK" 
  }
}
```

**Error Response (503 Service Unavailable)**
```json
{
  "status": "UNAVAILABLE",
  "checks": { 
    "database": "FAILING" 
  },
  "error": "Database connection failed"
}
```

### Metrics

Exposes Prometheus metrics for monitoring.

```
GET /metrics
```

**Response (200 OK)**
Returns Prometheus-formatted metrics including:
- Default Node.js metrics (memory, CPU, garbage collection)
- Custom metrics:
  - `http_request_duration_ms`: Request duration histogram
  - `http_requests_total`: Total request counter

**Response Format**
```
# HELP http_request_duration_ms Duration of HTTP requests in ms
# TYPE http_request_duration_ms histogram
http_request_duration_ms_bucket{le="50",method="GET",route="/api/projects",code="200"} 45
...
```

## Error Handling

The API uses standard HTTP status codes and consistent error response format.

### Status Codes

| Status Code | Description |
|-------------|-------------|
| 200 | OK - Request successful |
| 201 | Created - Resource created successfully |
| 204 | No Content - Request successful, no content to return |
| 400 | Bad Request - Invalid request format or parameters |
| 401 | Unauthorized - Authentication required or failed |
| 403 | Forbidden - Authenticated but not authorized for resource |
| 404 | Not Found - Resource not found |
| 500 | Internal Server Error - Server error |
| 503 | Service Unavailable - Service temporarily unavailable |

### Error Response Format

All errors follow this format:
```json
{
  "error": "Brief error message",
  "message": "Detailed explanation (optional)"
}
```

### Prisma-Specific Error Codes
- `P2023`: Invalid ID format
- `P2025`: Record not found

## CORS Configuration

CORS is configured to accept requests from allowed origins:

**Default Origins (Development)**
- `http://localhost:5173` (Frontend dev server)
- `http://localhost:3001` (Backend)

**Configuration**
Set via `CORS_ORIGIN` environment variable. Multiple origins can be comma-separated:
```
CORS_ORIGIN=http://localhost:5173,https://app.example.com
```

**Allowed Methods**: GET, POST, PUT, DELETE
**Allowed Headers**: Content-Type, Authorization

## Rate Limiting

Currently, no rate limiting is implemented. For production, consider adding rate limiting middleware.

## Examples

### Complete Workflow Example

1. **Register a new user**
```bash
curl -X POST http://localhost:3001/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "newuser@example.com",
    "password": "securepassword123",
    "name": "New User"
  }'
```

2. **Login (if already registered)**
```bash
curl -X POST http://localhost:3001/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "newuser@example.com",
    "password": "securepassword123"
  }'

# Save the token from the response
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

3. **Create a project**
```bash
curl -X POST http://localhost:3001/api/projects \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "title": "My Awesome Project",
    "status": "In Progress",
    "description": "Building something amazing",
    "githubUrl": "https://github.com/user/awesome-project",
    "hardwareInfo": {
      "platform": "Raspberry Pi 4",
      "sensors": "DHT22, PIR"
    }
  }'
```

4. **Get all your projects**
```bash
curl -X GET http://localhost:3001/api/projects \
  -H "Authorization: Bearer $TOKEN"
```

5. **Update a project**
```bash
curl -X PUT http://localhost:3001/api/projects/PROJECT_ID \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "title": "My Awesome Project v2",
    "status": "Completed",
    "description": "Successfully built something amazing!"
  }'
```

### cURL Examples

**Check API health**
```bash
curl http://localhost:3001/health
```

**Get metrics**
```bash
curl http://localhost:3001/metrics
```

**Get user profile**
```bash
curl -X GET http://localhost:3001/api/auth/profile \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### JavaScript/Axios Examples

**Using the auth service**
```javascript
import { login, getProjects } from './services';

// Login
const { token, user } = await login({
  email: 'user@example.com',
  password: 'password123'
});

// Get projects (token is automatically included)
const projects = await getProjects();
```

**Direct API call with fetch**
```javascript
const response = await fetch('http://localhost:3001/api/projects', {
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  }
});
const projects = await response.json();
```