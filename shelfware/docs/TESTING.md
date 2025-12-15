# Testing Guide

- [Overview](#overview)
  - [Test Philosophy](#test-philosophy)
- [Test Environment Setup](#test-environment-setup)
  - [Prerequisites](#prerequisites)
  - [Configuration Files](#configuration-files)
- [Running Tests](#running-tests)
  - [Backend Tests](#backend-tests)
  - [Frontend Tests](#frontend-tests)
- [Test Structure](#test-structure)
- [Testing Strategy](#testing-strategy)
  - [Unit Tests](#unit-tests)
  - [Integration Tests](#integration-tests)
  - [End-to-End Tests](#end-to-end-tests)
- [Mock Strategy](#mock-strategy)
  - [Mocking Prisma Client](#mocking-prisma-client)
  - [Mocking Authentication](#mocking-authentication)
  - [Mocking External Services](#mocking-external-services)
- [Testing Authentication](#testing-authentication)
  - [Testing Registration](#testing-registration)
  - [Testing Login](#testing-login)
  - [Testing Protected Routes](#testing-protected-routes)
- [Testing Projects API](#testing-projects-api)
  - [Testing CRUD Operations](#testing-crud-operations)
  - [Testing Authorization](#testing-authorization)
  - [Testing Validation](#testing-validation)
- [Testing Health \& Monitoring](#testing-health--monitoring)
- [Manual Testing](#manual-testing)
  - [Using cURL](#using-curl)
  - [Using Postman](#using-postman)
  - [Browser Testing](#browser-testing)
- [Writing New Tests](#writing-new-tests)
  - [Backend Test Template](#backend-test-template)
  - [Frontend Test Template](#frontend-test-template)
- [Code Coverage](#code-coverage)
  - [Running Coverage](#running-coverage)
  - [Coverage Goals](#coverage-goals)
  - [Improving Coverage](#improving-coverage)
- [CI/CD Integration](#cicd-integration)
  - [GitHub Actions Example](#github-actions-example)
- [Best Practices](#best-practices)
  - [1. Test Organization](#1-test-organization)
  - [2. Mock Management](#2-mock-management)
  - [3. Async Testing](#3-async-testing)
  - [4. Error Testing](#4-error-testing)
  - [5. Parameterized Tests](#5-parameterized-tests)
- [Common Testing Patterns](#common-testing-patterns)
  - [Testing with Different User Roles](#testing-with-different-user-roles)
  - [Testing Pagination](#testing-pagination)
  - [Testing File Uploads](#testing-file-uploads)
- [Troubleshooting](#troubleshooting)
  - [Common Issues](#common-issues)
  - [Debug Tips](#debug-tips)

## Overview

The PXL Shelfware Tracker uses a comprehensive testing strategy:

- **Backend**: Jest with Supertest for API testing
- **Frontend**: Jest with React Testing Library (future implementation)
- **Mocking**: Database and external services are mocked
- **Coverage**: Track coverage metrics to ensure quality

### Test Philosophy
- Test behavior, not implementation
- Mock external dependencies
- Keep tests independent and isolated
- Use descriptive test names
- Follow AAA pattern: Arrange, Act, Assert

## Test Environment Setup

### Prerequisites
```bash
# Backend dependencies
cd backend
npm install --save-dev jest ts-jest @types/jest supertest @types/supertest

# Frontend dependencies (future)
cd frontend
npm install --save-dev @testing-library/react @testing-library/jest-dom
```

### Configuration Files

**Backend Jest Configuration (`backend/jest.config.js`):**
```javascript
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  testMatch: ['**/tests/**/*.test.ts'],
  collectCoverageFrom: [
    'src/**/*.ts',
    '!src/**/*.d.ts',
    '!src/**/index.ts'
  ],
  coverageThreshold: {
    global: {
      branches: 70,
      functions: 80,
      lines: 80,
      statements: 80
    }
  }
};
```

## Running Tests

### Backend Tests

```bash
cd backend

# Run all tests
npm test

# Run tests in watch mode
npm test -- --watch

# Run tests with coverage
npm test -- --coverage

# Run specific test file
npm test -- tests/auth.test.ts

# Run tests matching pattern
npm test -- --testNamePattern="should register"

# Run tests with verbose output
npm test -- --verbose
```

### Frontend Tests

```bash
cd frontend

# Run all tests (when implemented)
npm test

# Run tests with coverage
npm test -- --coverage --watchAll=false
```

## Test Structure

```
backend/
├── tests/
│   ├── auth.test.ts        # Authentication endpoint tests
│   ├── server.test.ts      # API endpoint tests
│   ├── helpers/            # Test utilities
│   │   ├── setup.ts        # Test setup/teardown
│   │   └── fixtures.ts     # Test data fixtures
│   └── mocks/              # Mock implementations
│       ├── prisma.ts       # Prisma client mock
│       └── auth.ts         # Auth utilities mock

frontend/
├── src/
│   ├── __tests__/          # Component tests
│   ├── services/__tests__/ # Service tests
│   └── utils/__tests__/    # Utility tests
```

## Testing Strategy

### Unit Tests
Test individual functions and components in isolation:
- Utility functions
- Service methods
- React components
- Middleware functions

### Integration Tests
Test how different parts work together:
- API endpoints with middleware
- Database operations
- Authentication flow
- React component interactions

### End-to-End Tests
Test complete user workflows (future implementation):
- User registration and login
- Creating and managing projects
- Navigation flows

## Mock Strategy

### Mocking Prisma Client

Located in test files or `tests/mocks/prisma.ts`:

```typescript
jest.mock('@prisma/client', () => {
  const mockPrismaClient = {
    user: {
      findUnique: jest.fn(),
      findMany: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
    },
    project: {
      findUnique: jest.fn(),
      findMany: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
    },
    $disconnect: jest.fn(),
    $queryRaw: jest.fn(),
  };
  
  return { PrismaClient: jest.fn(() => mockPrismaClient) };
});
```

**Usage in tests:**
```typescript
const { PrismaClient } = require('@prisma/client');
const prismaMock = new PrismaClient();

// Set up mock responses
prismaMock.user.findUnique.mockResolvedValue({
  id: 'test-user-id',
  email: 'test@example.com',
  name: 'Test User',
  password: '$2b$10$hashedPassword',
  createdAt: new Date(),
  updatedAt: new Date()
});
```

### Mocking Authentication

**Mock bcrypt:**
```typescript
jest.mock('bcrypt', () => ({
  compare: jest.fn().mockImplementation((password, hash) => {
    return Promise.resolve(password === 'password123');
  }),
  hash: jest.fn().mockResolvedValue('$2b$10$hashedPassword')
}));
```

**Generate test tokens:**
```typescript
import jwt from 'jsonwebtoken';
import { JWT_SECRET } from '../src/config/passport';

const generateTestToken = (userId = 'test-user-id') => {
  return jwt.sign({ sub: userId }, JWT_SECRET, { expiresIn: '1h' });
};
```

### Mocking External Services

**Mock axios for external API calls:**
```typescript
jest.mock('axios');
const mockedAxios = axios as jest.Mocked<typeof axios>;

mockedAxios.get.mockResolvedValue({
  data: { /* mock response */ }
});
```

## Testing Authentication

### Testing Registration

```typescript
describe('POST /api/auth/register', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('should register a new user and return token', async () => {
    const response = await request(app)
      .post('/api/auth/register')
      .send({ 
        email: 'new@example.com', 
        password: 'password123', 
        name: 'New User' 
      });
    
    expect(response.status).toBe(201);
    expect(response.body).toHaveProperty('token');
    expect(response.body.user).toHaveProperty('email', 'new@example.com');
    expect(response.body.user).not.toHaveProperty('password');
    
    // Verify token structure
    const decoded = jwt.verify(response.body.token, JWT_SECRET);
    expect(decoded).toHaveProperty('sub');
  });

  it('should return 400 if email already exists', async () => {
    prismaMock.user.findUnique.mockResolvedValueOnce({
      id: 'existing-id',
      email: 'test@example.com',
      password: 'hashedPassword',
    });

    const response = await request(app)
      .post('/api/auth/register')
      .send({ 
        email: 'test@example.com', 
        password: 'password123' 
      });
    
    expect(response.status).toBe(400);
    expect(response.body.error).toBe('Email is already in use');
  });

  // Test validation
  it.each([
    { payload: { password: 'pass123' }, field: 'email' },
    { payload: { email: 'test@example.com' }, field: 'password' },
    { payload: {}, field: 'email and password' }
  ])('should return 400 if $field is missing', async ({ payload }) => {
    const response = await request(app)
      .post('/api/auth/register')
      .send(payload);
    
    expect(response.status).toBe(400);
    expect(response.body).toHaveProperty('error');
  });
});
```

### Testing Login

```typescript
describe('POST /api/auth/login', () => {
  it('should login with valid credentials', async () => {
    // Mock user exists
    prismaMock.user.findUnique.mockResolvedValue({
      id: 'test-user-id',
      email: 'test@example.com',
      password: '$2b$10$validHashedPassword',
      name: 'Test User'
    });

    const response = await request(app)
      .post('/api/auth/login')
      .send({ 
        email: 'test@example.com', 
        password: 'password123' 
      });
    
    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty('token');
    expect(response.body.user).toHaveProperty('email', 'test@example.com');
  });

  it('should return 401 with invalid password', async () => {
    const response = await request(app)
      .post('/api/auth/login')
      .send({ 
        email: 'test@example.com', 
        password: 'wrongpassword' 
      });
    
    expect(response.status).toBe(401);
  });

  it('should return 401 with non-existent email', async () => {
    prismaMock.user.findUnique.mockResolvedValue(null);

    const response = await request(app)
      .post('/api/auth/login')
      .send({ 
        email: 'nonexistent@example.com', 
        password: 'password123' 
      });
    
    expect(response.status).toBe(401);
  });
});
```

### Testing Protected Routes

```typescript
describe('Protected Routes', () => {
  let token: string;

  beforeEach(() => {
    token = generateTestToken('test-user-id');
  });

  describe('GET /api/auth/profile', () => {
    it('should return user profile with valid token', async () => {
      prismaMock.user.findUnique.mockResolvedValue({
        id: 'test-user-id',
        email: 'test@example.com',
        name: 'Test User'
      });

      const response = await request(app)
        .get('/api/auth/profile')
        .set('Authorization', `Bearer ${token}`);
      
      expect(response.status).toBe(200);
      expect(response.body).toHaveProperty('email', 'test@example.com');
      expect(response.body).not.toHaveProperty('password');
    });

    it('should return 401 without token', async () => {
      const response = await request(app)
        .get('/api/auth/profile');
      
      expect(response.status).toBe(401);
      expect(response.body.error).toBe('Unauthorized');
    });

    it('should return 401 with invalid token', async () => {
      const response = await request(app)
        .get('/api/auth/profile')
        .set('Authorization', 'Bearer invalid-token');
      
      expect(response.status).toBe(401);
    });

    it('should return 401 with expired token', async () => {
      const expiredToken = jwt.sign(
        { sub: 'test-user-id' }, 
        JWT_SECRET, 
        { expiresIn: '-1h' }
      );

      const response = await request(app)
        .get('/api/auth/profile')
        .set('Authorization', `Bearer ${expiredToken}`);
      
      expect(response.status).toBe(401);
    });
  });
});
```

## Testing Projects API

### Testing CRUD Operations

```typescript
describe('Projects API', () => {
  let token: string;

  beforeEach(() => {
    token = generateTestToken('test-user-id');
    jest.clearAllMocks();
  });

  describe('GET /api/projects', () => {
    it('should return user projects when authenticated', async () => {
      const mockProjects = [
        { id: '1', title: 'Project 1', userId: 'test-user-id' },
        { id: '2', title: 'Project 2', userId: 'test-user-id' }
      ];

      prismaMock.project.findMany.mockResolvedValue(mockProjects);

      const response = await request(app)
        .get('/api/projects')
        .set('Authorization', `Bearer ${token}`);
      
      expect(response.status).toBe(200);
      expect(response.body).toHaveLength(2);
      expect(prismaMock.project.findMany).toHaveBeenCalledWith({
        where: { userId: 'test-user-id' },
        orderBy: { createdAt: 'desc' }
      });
    });

    it('should return empty array when not authenticated', async () => {
      prismaMock.project.findMany.mockResolvedValue([]);

      const response = await request(app)
        .get('/api/projects');
      
      expect(response.status).toBe(200);
      expect(response.body).toEqual([]);
    });
  });

  describe('POST /api/projects', () => {
    const validProject = {
      title: 'New Project',
      status: 'Planning',
      description: 'Test description',
      hardwareInfo: { cpu: 'Intel i7' }
    };

    it('should create project when authenticated', async () => {
      const mockCreated = { 
        id: 'new-id', 
        ...validProject, 
        userId: 'test-user-id',
        createdAt: new Date(),
        updatedAt: new Date()
      };

      prismaMock.project.create.mockResolvedValue(mockCreated);

      const response = await request(app)
        .post('/api/projects')
        .set('Authorization', `Bearer ${token}`)
        .send(validProject);
      
      expect(response.status).toBe(201);
      expect(response.body).toHaveProperty('id');
      expect(response.body.userId).toBe('test-user-id');
    });

    it('should return 401 when not authenticated', async () => {
      const response = await request(app)
        .post('/api/projects')
        .send(validProject);
      
      expect(response.status).toBe(401);
    });

    it('should validate required fields', async () => {
      const response = await request(app)
        .post('/api/projects')
        .set('Authorization', `Bearer ${token}`)
        .send({ description: 'Missing required fields' });
      
      expect(response.status).toBe(400);
      expect(response.body.error).toBe('Title and status are required');
    });
  });
});
```

### Testing Authorization

```typescript
describe('Project Authorization', () => {
  let userToken: string;
  let otherUserToken: string;

  beforeEach(() => {
    userToken = generateTestToken('user-1');
    otherUserToken = generateTestToken('user-2');
  });

  it('should prevent access to other user projects', async () => {
    prismaMock.project.findUnique.mockResolvedValue({
      id: 'project-1',
      title: 'Private Project',
      userId: 'user-2' // Different user
    });

    const response = await request(app)
      .get('/api/projects/project-1')
      .set('Authorization', `Bearer ${userToken}`);
    
    expect(response.status).toBe(403);
    expect(response.body.error).toBe('You do not have permission to access this project');
  });

  it('should allow access to own projects', async () => {
    prismaMock.project.findUnique.mockResolvedValue({
      id: 'project-1',
      title: 'My Project',
      userId: 'user-1' // Same user
    });

    const response = await request(app)
      .get('/api/projects/project-1')
      .set('Authorization', `Bearer ${userToken}`);
    
    expect(response.status).toBe(200);
    expect(response.body.title).toBe('My Project');
  });

  it('should prevent updating other user projects', async () => {
    prismaMock.project.findUnique.mockResolvedValue({
      id: 'project-1',
      userId: 'user-2'
    });

    const response = await request(app)
      .put('/api/projects/project-1')
      .set('Authorization', `Bearer ${userToken}`)
      .send({ title: 'Updated', status: 'Completed' });
    
    expect(response.status).toBe(403);
  });

  it('should prevent deleting other user projects', async () => {
    prismaMock.project.findUnique.mockResolvedValue({
      id: 'project-1',
      userId: 'user-2'
    });

    const response = await request(app)
      .delete('/api/projects/project-1')
      .set('Authorization', `Bearer ${userToken}`);
    
    expect(response.status).toBe(403);
  });
});
```

### Testing Validation

```typescript
describe('Input Validation', () => {
  let token: string;

  beforeEach(() => {
    token = generateTestToken();
  });

  describe('Project Validation', () => {
    it('should handle invalid project ID format', async () => {
      const response = await request(app)
        .get('/api/projects/invalid-id')
        .set('Authorization', `Bearer ${token}`);
      
      expect(response.status).toBe(400);
      expect(response.body.error).toBe('Invalid project ID format');
    });

    it('should handle missing required fields on update', async () => {
      prismaMock.project.findUnique.mockResolvedValue({
        id: '1',
        userId: 'test-user-id'
      });

      const response = await request(app)
        .put('/api/projects/1')
        .set('Authorization', `Bearer ${token}`)
        .send({ description: 'Only description' });
      
      expect(response.status).toBe(400);
      expect(response.body.error).toBe('Title and status are required');
    });

    it('should accept valid status values', async () => {
      const validStatuses = ['Planning', 'In Progress', 'Completed', 'Abandoned'];
      
      for (const status of validStatuses) {
        prismaMock.project.create.mockResolvedValue({
          id: 'new-id',
          title: 'Test',
          status,
          userId: 'test-user-id'
        });

        const response = await request(app)
          .post('/api/projects')
          .set('Authorization', `Bearer ${token}`)
          .send({ title: 'Test', status });
        
        expect(response.status).toBe(201);
      }
    });
  });
});
```

## Testing Health & Monitoring

```typescript
describe('Health & Monitoring Endpoints', () => {
  describe('GET /health', () => {
    it('should return UP status', async () => {
      const response = await request(app).get('/health');
      
      expect(response.status).toBe(200);
      expect(response.body).toEqual({ status: 'UP' });
    });
  });

  describe('GET /ready', () => {
    it('should return READY when database is connected', async () => {
      prismaMock.$queryRaw.mockResolvedValue([1]);

      const response = await request(app).get('/ready');
      
      expect(response.status).toBe(200);
      expect(response.body).toEqual({
        status: 'READY',
        checks: { database: 'OK' }
      });
    });

    it('should return UNAVAILABLE when database fails', async () => {
      prismaMock.$queryRaw.mockRejectedValue(new Error('Connection failed'));

      const response = await request(app).get('/ready');
      
      expect(response.status).toBe(503);
      expect(response.body).toEqual({
        status: 'UNAVAILABLE',
        checks: { database: 'FAILING' },
        error: 'Database connection failed'
      });
    });
  });

  describe('GET /metrics', () => {
    it('should return Prometheus metrics', async () => {
      const response = await request(app).get('/metrics');
      
      expect(response.status).toBe(200);
      expect(response.text).toContain('http_request_duration_ms');
      expect(response.text).toContain('http_requests_total');
    });
  });
});
```

## Manual Testing

### Using cURL

**Complete test workflow:**
```bash
# 1. Health check
curl http://localhost:3001/health

# 2. Register user
curl -X POST http://localhost:3001/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123","name":"Test User"}'

# 3. Login (save response)
RESPONSE=$(curl -X POST http://localhost:3001/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}')

# 4. Extract token (requires jq)
TOKEN=$(echo $RESPONSE | jq -r '.token')

# 5. Create project
curl -X POST http://localhost:3001/api/projects \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"title":"Test Project","status":"Planning","description":"Testing via cURL"}'

# 6. Get all projects
curl -X GET http://localhost:3001/api/projects \
  -H "Authorization: Bearer $TOKEN"

# 7. Update project (replace PROJECT_ID)
curl -X PUT http://localhost:3001/api/projects/PROJECT_ID \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"title":"Updated Project","status":"In Progress"}'

# 8. Delete project
curl -X DELETE http://localhost:3001/api/projects/PROJECT_ID \
  -H "Authorization: Bearer $TOKEN"
```

### Using Postman

1. **Import Collection:**
   - Create a new collection "Shelfware API"
   - Add environment variables: `baseUrl`, `token`

2. **Pre-request Script for Auth:**
   ```javascript
   if (pm.request.url.path.includes('auth')) return;
   
   const token = pm.environment.get('token');
   if (token) {
     pm.request.headers.add({
       key: 'Authorization',
       value: `Bearer ${token}`
     });
   }
   ```

3. **Login Test Script:**
   ```javascript
   pm.test("Status is 200", () => {
     pm.response.to.have.status(200);
   });
   
   pm.test("Has token", () => {
     const response = pm.response.json();
     pm.expect(response).to.have.property('token');
     pm.environment.set('token', response.token);
   });
   ```

### Browser Testing

1. **Test Authentication Flow:**
   - Open developer tools
   - Check localStorage for token after login
   - Verify token is included in API requests
   - Test logout clears token

2. **Test Protected Routes:**
   - Try accessing /create without login
   - Verify redirect to login
   - After login, verify redirect back

3. **Test Project Operations:**
   - Create project with various inputs
   - Test validation messages
   - Verify only own projects visible

## Writing New Tests

### Backend Test Template

```typescript
import request from 'supertest';
import app from '../src/server';

// Mock dependencies
jest.mock('@prisma/client', () => {
  // Mock implementation
});

describe('Feature Name', () => {
  // Setup
  let token: string;
  
  beforeEach(() => {
    jest.clearAllMocks();
    token = generateTestToken();
  });
  
  afterEach(() => {
    // Cleanup if needed
  });

  describe('GET /api/feature', () => {
    it('should return expected result', async () => {
      // Arrange
      const mockData = { /* ... */ };
      prismaMock.model.method.mockResolvedValue(mockData);
      
      // Act
      const response = await request(app)
        .get('/api/feature')
        .set('Authorization', `Bearer ${token}`);
      
      // Assert
      expect(response.status).toBe(200);
      expect(response.body).toEqual(/* expected */);
    });
    
    it('should handle errors gracefully', async () => {
      // Arrange
      prismaMock.model.method.mockRejectedValue(new Error('DB Error'));
      
      // Act & Assert
      const response = await request(app)
        .get('/api/feature')
        .set('Authorization', `Bearer ${token}`);
        
      expect(response.status).toBe(500);
      expect(response.body).toHaveProperty('error');
    });
  });
});
```

### Frontend Test Template

```typescript
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { AuthProvider } from '../context/AuthContext';
import Component from '../Component';

// Mock services
jest.mock('../services/projectService');

describe('Component', () => {
  const renderWithAuth = (component: React.ReactElement) => {
    return render(
      <AuthProvider>
        {component}
      </AuthProvider>
    );
  };

  it('should render correctly', () => {
    renderWithAuth(<Component />);
    
    expect(screen.getByText('Expected Text')).toBeInTheDocument();
  });

  it('should handle user interaction', async () => {
    renderWithAuth(<Component />);
    
    const button = screen.getByRole('button', { name: 'Click Me' });
    fireEvent.click(button);
    
    await waitFor(() => {
      expect(screen.getByText('Result')).toBeInTheDocument();
    });
  });
});
```

## Code Coverage

### Running Coverage

```bash
# Backend coverage
cd backend
npm test -- --coverage

# View coverage report
open coverage/lcov-report/index.html
```

### Coverage Goals
- Statements: 80%
- Branches: 70%
- Functions: 80%
- Lines: 80%

### Improving Coverage

1. **Identify gaps:**
   ```bash
   npm test -- --coverage --coverageReporters=text
   ```

2. **Focus on critical paths:**
   - Authentication flows
   - Data validation
   - Error handling

3. **Exclude non-testable code:**
   ```javascript
   /* istanbul ignore next */
   if (process.env.NODE_ENV === 'production') {
     // Production-only code
   }
   ```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test-backend:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'
          
      - name: Install dependencies
        run: |
          cd backend
          npm ci
          
      - name: Run tests
        run: |
          cd backend
          npm test -- --coverage
        env:
          DATABASE_URL: postgresql://postgres:postgres@localhost:5432/test
          JWT_SECRET: test-secret
          
      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          directory: ./backend/coverage
```

## Best Practices

### 1. Test Organization
- Group related tests using `describe` blocks
- Use clear, descriptive test names
- Follow AAA pattern: Arrange, Act, Assert
- One assertion per test when possible

### 2. Mock Management
- Clear mocks between tests
- Use `beforeEach` for common setup
- Don't over-mock - test real behavior when possible
- Mock at the boundary (database, external APIs)

### 3. Async Testing
```typescript
// Good - properly awaited
it('should handle async operations', async () => {
  const result = await asyncFunction();
  expect(result).toBe(expected);
});

// Bad - missing await
it('should handle async operations', () => {
  const result = asyncFunction(); // Missing await!
  expect(result).toBe(expected);
});
```

### 4. Error Testing
```typescript
// Test both success and failure paths
it('should handle success', async () => {
  mockService.method.mockResolvedValue(data);
  // Test success
});

it('should handle failure', async () => {
  mockService.method.mockRejectedValue(new Error('Failed'));
  // Test error handling
});
```

### 5. Parameterized Tests
```typescript
// Test multiple scenarios efficiently
it.each([
  { input: 'valid', expected: 200 },
  { input: '', expected: 400 },
  { input: null, expected: 400 },
])('should return $expected for input $input', async ({ input, expected }) => {
  const response = await request(app)
    .post('/api/endpoint')
    .send({ data: input });
    
  expect(response.status).toBe(expected);
});
```

## Common Testing Patterns

### Testing with Different User Roles
```typescript
describe('Role-based access', () => {
  const users = {
    owner: generateTestToken('owner-id'),
    other: generateTestToken('other-id'),
    admin: generateTestToken('admin-id')
  };

  it.each([
    { role: 'owner', expected: 200 },
    { role: 'other', expected: 403 },
    { role: 'admin', expected: 200 },
  ])('$role should get $expected status', async ({ role, expected }) => {
    const response = await request(app)
      .get('/api/protected')
      .set('Authorization', `Bearer ${users[role]}`);
      
    expect(response.status).toBe(expected);
  });
});
```

### Testing Pagination
```typescript
describe('Pagination', () => {
  it('should return paginated results', async () => {
    const mockProjects = Array(25).fill(null).map((_, i) => ({
      id: `project-${i}`,
      title: `Project ${i}`
    }));
    
    prismaMock.project.findMany.mockImplementation(({ take, skip }) => {
      return mockProjects.slice(skip || 0, (skip || 0) + (take || 10));
    });

    const page1 = await request(app)
      .get('/api/projects?page=1&limit=10')
      .set('Authorization', `Bearer ${token}`);
      
    expect(page1.body).toHaveLength(10);
    expect(page1.body[0].title).toBe('Project 0');
  });
});
```

### Testing File Uploads
```typescript
describe('File Upload', () => {
  it('should handle file upload', async () => {
    const response = await request(app)
      .post('/api/upload')
      .set('Authorization', `Bearer ${token}`)
      .attach('file', 'tests/fixtures/test-file.json')
      .field('projectId', 'project-1');
      
    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty('fileUrl');
  });
});
```

## Troubleshooting

### Common Issues

1. **"Cannot find module" errors**
   - Check import paths
   - Ensure TypeScript paths are configured
   - Clear jest cache: `npm test -- --clearCache`

2. **Mock not working**
   - Ensure mock is before imports
   - Check mock path matches import
   - Use `jest.clearAllMocks()` in `beforeEach`

3. **Async test timeout**
   ```typescript
   // Increase timeout for slow operations
   it('should handle slow operation', async () => {
     // test code
   }, 10000); // 10 second timeout
   ```

4. **Database connection in tests**
   - Ensure database is properly mocked
   - Don't use real database in unit tests
   - Use test database for integration tests

5. **Token verification fails**
   - Check JWT_SECRET is consistent
   - Verify token format includes "Bearer "
   - Check token hasn't expired

### Debug Tips

1. **Verbose logging:**
   ```bash
   npm test -- --verbose --no-coverage
   ```

2. **Run single test:**
   ```bash
   npm test -- --testNamePattern="should create project"
   ```

3. **Debug mode:**
   ```json
   // In package.json
   "scripts": {
     "test:debug": "node --inspect-brk ./node_modules/.bin/jest --runInBand"
   }
   ```

4. **Print mock calls:**
   ```typescript
   console.log(mockFunction.mock.calls);
   console.log(mockFunction.mock.results);
   ```