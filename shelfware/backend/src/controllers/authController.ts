// src/controllers/authController.ts
import { Request, Response } from 'express';
import { PrismaClient } from '@prisma/client';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcrypt';
import { JWT_SECRET } from '../config/passport';
import { User } from '../types';

const prisma = new PrismaClient();

// Register a new user
export const register = async (req: Request, res: Response) => {
  try {
    const { email, password, name } = req.body;

    // Check if required fields are present
    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required' });
    }

    // Check if email is already in use
    const existingUser = await prisma.user.findUnique({
      where: { email },
    });

    if (existingUser) {
      return res.status(400).json({ error: 'Email is already in use' });
    }

    // Hash the password
    const hashedPassword = await bcrypt.hash(password, 10);

    // Create a new user
    const newUser = await prisma.user.create({
      data: {
        email,
        password: hashedPassword,
        name: name || null,
      },
    });

    // Remove password from response
    const { password: _, ...userWithoutPassword } = newUser;

    // Generate JWT token
    const token = jwt.sign({ sub: newUser.id }, JWT_SECRET, {
      expiresIn: '7d',
    });

    res.status(201).json({
      user: userWithoutPassword,
      token,
    });
  } catch (error) {
    console.error('Registration error:', error);
    res.status(500).json({ error: 'Failed to register user' });
  }
};

// Login an existing user
export const login = (req: Request, res: Response) => {
  // Passport's local strategy will have already authenticated the user
  // and attached it to req.user
  const user = req.user as User;

  if (!user) {
    return res.status(401).json({ error: 'Authentication failed' });
  }

  // Generate JWT token
  const token = jwt.sign({ sub: user.id }, JWT_SECRET, {
    expiresIn: '7d',
  });

  res.json({
    user,
    token,
  });
};

// Get the authenticated user's profile
export const getProfile = (req: Request, res: Response) => {
  // Passport's JWT strategy will have already authenticated the user
  // and attached it to req.user
  const user = req.user as User;

  if (!user) {
    return res.status(401).json({ error: 'Not authenticated' });
  }

  res.json(user);
};