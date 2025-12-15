// backend/src/config/passport.ts
import { PrismaClient } from '@prisma/client';
import passport from 'passport';
import { Strategy as LocalStrategy } from 'passport-local';
import { Strategy as JwtStrategy, ExtractJwt } from 'passport-jwt';
import bcrypt from 'bcrypt';

const prisma = new PrismaClient();

// Environment variables should be properly configured
const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key-change-in-production';

// Local Strategy for username/password login
passport.use(
    new LocalStrategy(
      {
        usernameField: 'email',
        passwordField: 'password',
      },
      async (email, password, done) => {
        try {
          // Find the user by email
          const user = await prisma.user.findUnique({
            where: { email },
          });
  
          // If user doesn't exist or password doesn't match
          if (!user || !(await bcrypt.compare(password, user.password))) {
            return done(null, false, { message: 'Invalid email or password' });
          }
  
          // Remove the password from the user object before returning
          const { password: _, ...userWithoutPassword } = user;
          return done(null, userWithoutPassword);
        } catch (error) {
          return done(error);
        }
      }
    )
  );

passport.use(
    new JwtStrategy(
      {
        jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
        secretOrKey: JWT_SECRET,
      },
      async (payload, done) => {
        try {
          // Find the user by id in the JWT payload
          const user = await prisma.user.findUnique({
            where: { id: payload.sub },
          });
  
          if (!user) {
            return done(null, false);
          }
  
          // Remove the password from the user object before returning
          const { password: _, ...userWithoutPassword } = user;
          return done(null, userWithoutPassword);
        } catch (error) {
          return done(error);
        }
      }
    )
  );

export default passport;
export { JWT_SECRET };