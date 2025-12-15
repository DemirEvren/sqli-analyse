// backend/src/middleware/authMiddleware.ts
import { Request, Response, NextFunction } from 'express';
import passport from '../config/passport';

// Middleware to check if user is authenticated
export const requireAuth = (req: Request, res: Response, next: NextFunction) => {
  passport.authenticate('jwt', { session: false }, (err, user, info) => {
    if (err) {
      return next(err);
    }
    
    if (!user) {
      return res.status(401).json({ 
        error: 'Unauthorized',
        message: 'You must be logged in to access this resource' 
      });
    }
    
    // User is authenticated, attach to request
    req.user = user;
    next();
  })(req, res, next);
};

// Optional authentication - doesn't block but attaches user if token is valid
export const optionalAuth = (req: Request, res: Response, next: NextFunction) => {
  passport.authenticate('jwt', { session: false }, (err, user) => {
    if (err) {
      return next(err);
    }
    
    if (user) {
      req.user = user;
    }
    
    next();
  })(req, res, next);
};