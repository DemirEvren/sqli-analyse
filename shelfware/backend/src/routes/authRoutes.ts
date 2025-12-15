// backend/src/routes/authRoutes.ts
import express from 'express';
import passport from '../config/passport';
import * as authController from '../controllers/authController';

const router = express.Router();

// Register route
router.post('/register', authController.register);

// Login route - uses passport local strategy
router.post('/login', passport.authenticate('local', { session: false }), authController.login);

// Get user profile - requires JWT authentication
router.get('/profile', passport.authenticate('jwt', { session: false }), authController.getProfile);

export default router;