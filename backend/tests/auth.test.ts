// tests/auth.test.ts
import request from 'supertest';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcrypt';
import app from '../src/server';
import { JWT_SECRET } from '../src/config/passport';

// Mock the Prisma client
jest.mock('@prisma/client', () => {
  const mPrisma = {
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
      findMany: jest.fn().mockResolvedValue([]),
      findUnique: jest.fn().mockResolvedValue(null),
    },
    $disconnect: jest.fn(),
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

describe('Authentication Endpoints', () => {
  describe('POST /api/auth/register', () => {
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
      expect(response.body.user).not.toHaveProperty('password'); // Password should not be returned
      
      // Verify token can be decoded
      const decoded = jwt.verify(response.body.token, JWT_SECRET);
      expect(decoded).toHaveProperty('sub', 'new-user-id');
    });

    it('should return 400 if email is missing', async () => {
      const response = await request(app)
        .post('/api/auth/register')
        .send({ password: 'password123' });
      
      expect(response.status).toBe(400);
      expect(response.body).toHaveProperty('error', 'Email and password are required');
    });

    it('should return 400 if password is missing', async () => {
      const response = await request(app)
        .post('/api/auth/register')
        .send({ email: 'new@example.com' });
      
      expect(response.status).toBe(400);
      expect(response.body).toHaveProperty('error', 'Email and password are required');
    });

    it('should return 400 if email already exists', async () => {
      // Mock the Prisma findUnique to return an existing user
      const { PrismaClient } = require('@prisma/client');
      const prismaMock = new PrismaClient();
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
      expect(response.body).toHaveProperty('error', 'Email is already in use');
    });
  });

  describe('POST /api/auth/login', () => {
    // These tests will depend on how you've implemented Passport.js
    // You may need to make adjustments based on your implementation
    
    it('should return 401 with invalid credentials', async () => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({ 
          email: 'test@example.com', 
          password: 'wrongpassword' 
        });
      
      expect(response.status).toBe(401);
    });

    it('should return token with valid credentials', async () => {
      // This test will likely need changes depending on your Passport setup
      const response = await request(app)
        .post('/api/auth/login')
        .send({ 
          email: 'test@example.com', 
          password: 'password123' 
        });
      
      // Once your Passport authentication is properly mocked, this should pass
      expect(response.status).toBe(200);
      expect(response.body).toHaveProperty('token');
      expect(response.body.user).toHaveProperty('email', 'test@example.com');
    });
  });

  describe('GET /api/auth/profile', () => {
    it('should return 401 without token', async () => {
      const response = await request(app)
        .get('/api/auth/profile');
      
      expect(response.status).toBe(401);
    });

    it('should return user profile with valid token', async () => {
      // Generate a valid token for testing
      const token = jwt.sign({ sub: 'test-user-id' }, JWT_SECRET, { expiresIn: '1h' });
      
      const response = await request(app)
        .get('/api/auth/profile')
        .set('Authorization', `Bearer ${token}`);
      
      expect(response.status).toBe(200);
      expect(response.body).toHaveProperty('id', 'test-user-id');
      expect(response.body).toHaveProperty('email', 'test@example.com');
      expect(response.body).not.toHaveProperty('password');
    });

    it('should return 401 with invalid token', async () => {
      const response = await request(app)
        .get('/api/auth/profile')
        .set('Authorization', 'Bearer invalid-token');
      
      expect(response.status).toBe(401);
    });
  });

  // Add tests for token expiration, invalid token format, etc. if needed
});