// tests/server.test.ts
import request from 'supertest';
import jwt from 'jsonwebtoken';
import app from '../src/server';
import { JWT_SECRET } from '../src/config/passport';

// MOCKING PRISMA
// We use jest.mock to simulate database interactions so that our tests
// do not depend on an actual PostgreSQL instance.
jest.mock('@prisma/client', () => {
  const mPrisma = {
    $queryRaw: jest.fn().mockResolvedValue([1]), // used in /ready endpoint
    user: {
      findUnique: jest.fn().mockImplementation(({ where }) => {
        if (where.email === 'test@example.com') {
          return Promise.resolve({
            id: 'test-user-id',
            email: 'test@example.com',
            password: '$2b$10$testHashedPassword',
            name: 'Test User',
            createdAt: new Date(),
            updatedAt: new Date()
          });
        }
        if (where.id === 'test-user-id') {
          return Promise.resolve({
            id: 'test-user-id',
            email: 'test@example.com',
            name: 'Test User',
            createdAt: new Date(),
            updatedAt: new Date()
          });
        }
        return Promise.resolve(null);
      }),
      create: jest.fn().mockResolvedValue({
        id: 'new-user-id',
        email: 'new@example.com',
        name: 'New User',
        createdAt: new Date(),
        updatedAt: new Date()
      }),
    },
    project: {
      // GET /api/projects returns an array with one sample project.
      findMany: jest.fn().mockImplementation((params) => {
        const projects = [
          { id: '1', title: 'Test Project', status: 'Active', userId: 'test-user-id', createdAt: new Date() },
          { id: '2', title: 'Another Project', status: 'Planning', userId: 'other-user-id', createdAt: new Date() }
        ];
        
        // Filter by userId if provided
        if (params?.where?.userId) {
          return Promise.resolve(projects.filter(p => p.userId === params.where.userId));
        }
        
        return Promise.resolve(projects);
      }),
      // GET /api/projects/:id returns a project if id === '1'; otherwise, null.
      findUnique: jest.fn().mockImplementation(({ where: { id } }) => {
        if (id === '1') {
          return Promise.resolve({ id: '1', title: 'Test Project', status: 'Active', userId: 'test-user-id', createdAt: new Date() });
        }
        return Promise.resolve(null);
      }),
      // POST /api/projects simulates creation of a new project.
      create: jest.fn().mockImplementation(({ data }) => {
        return Promise.resolve({ 
          id: 'new-project', 
          ...data,
          createdAt: new Date(),
          updatedAt: new Date()
        });
      }),
      // PUT /api/projects/:id simulates updating a project.
      update: jest.fn().mockResolvedValue({ id: '1', title: 'Updated Project', status: 'Active', userId: 'test-user-id' }),
      // DELETE /api/projects/:id simulates deletion.
      delete: jest.fn().mockResolvedValue({ id: '1', title: 'Deleted Project', status: 'Active', userId: 'test-user-id' }),
    },
  };
  return { PrismaClient: jest.fn(() => mPrisma) };
});

// Mock bcrypt
jest.mock('bcrypt', () => ({
  compare: jest.fn().mockImplementation((password, hash) => {
    // In tests, 'password123' will be considered valid
    return Promise.resolve(password === 'password123');
  }),
  hash: jest.fn().mockResolvedValue('$2b$10$hashedPassword')
}));

// Helper to create test tokens
const generateTestToken = (userId = 'test-user-id') => {
  return jwt.sign({ sub: userId }, JWT_SECRET, { expiresIn: '1h' });
};

// Group our tests for clarity
describe('API Endpoints Unit Tests', () => {
  describe('GET /health', () => {
    it('should return a 200 status and a status message "UP"', async () => {
      const response = await request(app).get('/health');
      expect(response.status).toBe(200);
      expect(response.body).toEqual({ status: 'UP' });
    });
  });

  describe('GET /', () => {
    it('should return the running API message', async () => {
      const response = await request(app).get('/');
      expect(response.status).toBe(200);
      expect(response.text).toBe('Shelfware API is running');
    });
  });

  describe('GET /metrics', () => {
    it('should return Prometheus metrics data', async () => {
      const response = await request(app).get('/metrics');
      expect(response.status).toBe(200);
      // Verify that one of our metric names is present in the output.
      expect(response.text).toContain('http_request_duration_ms');
    });
  });

  describe('GET /ready', () => {
    it('should indicate readiness when the DB query is successful', async () => {
      const response = await request(app).get('/ready');
      expect(response.status).toBe(200);
      expect(response.body).toHaveProperty('status', 'READY');
    });

    it('should return 503 when the DB query fails', async () => {
      // Override the $queryRaw method for this test to simulate a DB failure.
      const { PrismaClient } = require('@prisma/client');
      const prismaMock = new PrismaClient();
      prismaMock.$queryRaw.mockRejectedValueOnce(new Error("DB failure"));

      const response = await request(app).get('/ready');
      expect(response.status).toBe(503);
      expect(response.body).toHaveProperty('status', 'UNAVAILABLE');
    });
  });

  // Authentication Tests
  describe('Authentication Endpoints', () => {
    describe('POST /api/auth/register', () => {
      it('should register a new user and return token', async () => {
        const response = await request(app)
          .post('/api/auth/register')
          .send({ email: 'new@example.com', password: 'password123', name: 'New User' });
        
        expect(response.status).toBe(201);
        expect(response.body).toHaveProperty('token');
        expect(response.body.user).toHaveProperty('email', 'new@example.com');
      });

      it('should return 400 if email is missing', async () => {
        const response = await request(app)
          .post('/api/auth/register')
          .send({ password: 'password123' });
        
        expect(response.status).toBe(400);
        expect(response.body).toHaveProperty('error');
      });
    });

    describe('POST /api/auth/login', () => {
      it('should login successfully with valid credentials', async () => {
        // Your mock for passport will need to be set up to handle this
        const response = await request(app)
          .post('/api/auth/login')
          .send({ email: 'test@example.com', password: 'password123' });
        expect(response.status).toBe(200);
        expect(response.body).toHaveProperty('token');
        expect(response.body).toHaveProperty('user');
        expect(response.body.user).toHaveProperty('email', 'test@example.com');
      });
    });

    describe('GET /api/auth/profile', () => {
      it('should return user profile when authenticated', async () => {
        const token = generateTestToken();
        const response = await request(app)
          .get('/api/auth/profile')
          .set('Authorization', `Bearer ${token}`);
        expect(response.status).toBe(200);
        expect(response.body).toHaveProperty('id');
        expect(response.body).toHaveProperty('email', 'test@example.com');
      });
    });
  });

  describe('GET /api/projects', () => {
    it('should return all projects when not authenticated', async () => {
      const response = await request(app).get('/api/projects');
      expect(response.status).toBe(200);
      expect(Array.isArray(response.body)).toBe(true);
      expect(response.body.length).toBeGreaterThan(0);
    });

    it('should return only user projects when authenticated', async () => {
      const token = generateTestToken();
      const response = await request(app)
        .get('/api/projects')
        .set('Authorization', `Bearer ${token}`);
      
      expect(response.status).toBe(200);
      expect(Array.isArray(response.body)).toBe(true);
      // Should only return projects for the authenticated user
      response.body.forEach(project => {
        expect(project.userId).toBe('test-user-id');
      });
    });
  });

  describe('GET /api/projects/:id', () => {
    it('should return 401 if not authenticated', async () => {
      const response = await request(app).get('/api/projects/1');
      expect(response.status).toBe(401);
    });

    it('should return a project if found and user is authenticated', async () => {
      const token = generateTestToken();
      const response = await request(app)
        .get('/api/projects/1')
        .set('Authorization', `Bearer ${token}`);
      
      expect(response.status).toBe(200);
      expect(response.body).toHaveProperty('id', '1');
      expect(response.body).toHaveProperty('title', 'Test Project');
    });

    it('should return 404 if project not found', async () => {
      const token = generateTestToken();
      const response = await request(app)
        .get('/api/projects/unknown')
        .set('Authorization', `Bearer ${token}`);
      
      expect(response.status).toBe(404);
      expect(response.body.error).toBe('Project not found');
    });
  });

  describe('POST /api/projects', () => {
    it('should return 401 if not authenticated', async () => {
      const response = await request(app)
        .post('/api/projects')
        .send({ title: 'New Project', status: 'Active' });
      
      expect(response.status).toBe(401);
    });

    it('should return 400 if "title" is missing', async () => {
      const token = generateTestToken();
      const response = await request(app)
        .post('/api/projects')
        .set('Authorization', `Bearer ${token}`)
        .send({ status: 'Active' });
      
      expect(response.status).toBe(400);
      expect(response.body.error).toBe('Title and status are required');
    });

    it('should return 400 if "status" is missing', async () => {
      const token = generateTestToken();
      const response = await request(app)
        .post('/api/projects')
        .set('Authorization', `Bearer ${token}`)
        .send({ title: 'Test Project' });
      
      expect(response.status).toBe(400);
      expect(response.body.error).toBe('Title and status are required');
    });

    it('should create a new project when authenticated with required fields', async () => {
      const token = generateTestToken();
      const response = await request(app)
        .post('/api/projects')
        .set('Authorization', `Bearer ${token}`)
        .send({ title: 'New Project', status: 'Active' });
      
      expect(response.status).toBe(201);
      expect(response.body).toHaveProperty('id');
      expect(response.body).toHaveProperty('title', 'New Project');
      // Should associate with the authenticated user
      expect(response.body).toHaveProperty('userId', 'test-user-id');
    });
  });

  describe('PUT /api/projects/:id', () => {
    it('should return 401 if not authenticated', async () => {
      const response = await request(app)
        .put('/api/projects/1')
        .send({ title: 'Updated Project', status: 'Active' });
      
      expect(response.status).toBe(401);
    });

    it('should update a project when authenticated with valid data', async () => {
      const token = generateTestToken();
      const payload = {
        title: 'Updated Project',
        status: 'Active',
        description: 'Updated description',
        githubUrl: 'https://github.com/example/repo',
        deployedUrl: 'https://example.com',
        docsUrl: 'https://docs.example.com',
        hardwareInfo: 'Raspberry Pi'
      };
      
      const response = await request(app)
        .put('/api/projects/1')
        .set('Authorization', `Bearer ${token}`)
        .send(payload);
      
      expect(response.status).toBe(200);
      expect(response.body).toHaveProperty('id', '1');
      expect(response.body.title).toEqual('Updated Project');
    });

    it('should return 400 when "title" is missing', async () => {
      const token = generateTestToken();
      const payload = {
        status: 'Active',
        description: 'Missing title'
      };
      
      const response = await request(app)
        .put('/api/projects/1')
        .set('Authorization', `Bearer ${token}`)
        .send(payload);
      
      expect(response.status).toBe(400);
      expect(response.body.error).toBe('Title and status are required');
    });
  });

  describe('DELETE /api/projects/:id', () => {
    it('should return 401 if not authenticated', async () => {
      const response = await request(app).delete('/api/projects/1');
      expect(response.status).toBe(401);
    });

    it('should delete a project and return 204 when authenticated', async () => {
      const token = generateTestToken();
      const response = await request(app)
        .delete('/api/projects/1')
        .set('Authorization', `Bearer ${token}`);
      
      expect(response.status).toBe(204);
    });

    it('should return 404 when attempting to delete a non-existent project', async () => {
      const token = generateTestToken();
      
      // Override the project.delete method for this test to simulate a "not found" error.
      const { PrismaClient } = require('@prisma/client');
      const prismaMock = new PrismaClient();
      // Simulate a rejection with an error object that has a code property.
      prismaMock.project.delete.mockRejectedValueOnce(
        Object.assign(new Error('Not found'), { code: 'P2025' })
      );

      const response = await request(app)
        .delete('/api/projects/unknown')
        .set('Authorization', `Bearer ${token}`);
      
      expect(response.status).toBe(404);
      expect(response.body.error).toBe('Project not found');
    });
  });
});