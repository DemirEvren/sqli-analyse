# Authentication System Documentation

- [Overview](#overview)
  - [Key Features](#key-features)
- [Architecture](#architecture)
- [Setup](#setup)
  - [Environment Variables](#environment-variables)
  - [Database Schema](#database-schema)
- [Backend Implementation](#backend-implementation)
  - [Passport.js Configuration](#passportjs-configuration)
  - [Authentication Strategies](#authentication-strategies)
  - [Authentication Controller](#authentication-controller)
  - [Authentication Middleware](#authentication-middleware)
  - [Route Protection](#route-protection)
  - [Password Security](#password-security)
- [Frontend Implementation](#frontend-implementation)
  - [Authentication Service](#authentication-service)
  - [Authentication Context](#authentication-context)
  - [Protected Routes Component](#protected-routes-component)
  - [Authentication Flow](#authentication-flow)
  - [Token Management](#token-management)
- [Security Best Practices](#security-best-practices)
  - [Implemented Security Measures](#implemented-security-measures)
  - [Recommended Improvements](#recommended-improvements)
- [Testing Authentication](#testing-authentication)
  - [Backend Testing](#backend-testing)
  - [Frontend Testing](#frontend-testing)
- [Common Issues \& Troubleshooting](#common-issues--troubleshooting)
  - [Issue: "Invalid token" errors](#issue-invalid-token-errors)
  - [Issue: User not loading after refresh](#issue-user-not-loading-after-refresh)
  - [Issue: CORS errors](#issue-cors-errors)
  - [Issue: "Unauthorized" on protected routes](#issue-unauthorized-on-protected-routes)
  - [Issue: Password validation fails](#issue-password-validation-fails)
- [API Usage Examples](#api-usage-examples)
  - [Using cURL](#using-curl)
  - [Using JavaScript/TypeScript](#using-javascripttypescript)

## Overview

The PXL Shelfware Tracker uses a JWT-based authentication system built with:

- **Backend**: Passport.js with Local and JWT strategies
- **Frontend**: React Context API for state management
- **Security**: bcrypt for password hashing, JWT tokens with 7-day expiration
- **Storage**: Tokens stored in localStorage

### Key Features
- Stateless authentication using JWT
- Secure password hashing with bcrypt (10 rounds)
- Automatic token inclusion in API requests
- Protected routes on both frontend and backend
- User profile management
- Graceful error handling and loading states

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│   Browser   │────▶│   Frontend   │────▶│   Backend    │
│             │     │   (React)    │     │  (Express)   │
└─────────────┘     └──────────────┘     └──────────────┘
       │                    │                     │
       │              ┌─────▼─────┐         ┌────▼────┐
       └─────────────▶│AuthContext│         │Passport │
         localStorage └───────────┘         └─────────┘
                                                  │
                                            ┌─────▼─────┐
                                            │PostgreSQL │
                                            └───────────┘
```

## Setup

### Environment Variables

**Backend (.env)**
```env
# JWT Secret - REQUIRED: Generate a secure random string for production
JWT_SECRET="your-very-secure-random-string-here"

# CORS Configuration
CORS_ORIGIN=http://localhost:5173

# Other backend configs
DATABASE_URL="postgresql://user:pass@localhost:5432/shelfware?schema=public"
BACKEND_PORT=3001
```

**Frontend (.env)**
```env
# API URL (optional - defaults to http://localhost:3001/api)
VITE_API_URL=http://localhost:3001/api
```

### Database Schema

```prisma
model User {
  id        String   @id @default(cuid())
  email     String   @unique
  password  String   // Hashed with bcrypt
  name      String?
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
  projects  Project[]
}

model Project {
  id          String   @id @default(cuid())
  // ... other fields
  userId      String?
  user        User?    @relation(fields: [userId], references: [id])
}
```

## Backend Implementation

### Passport.js Configuration

Located in `backend/src/config/passport.ts`:

```typescript
// JWT Secret from environment
const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key-change-in-production';

// Local Strategy for email/password login
passport.use(new LocalStrategy({
    usernameField: 'email',
    passwordField: 'password',
  },
  async (email, password, done) => {
    const user = await prisma.user.findUnique({ where: { email } });
    if (!user || !(await bcrypt.compare(password, user.password))) {
      return done(null, false, { message: 'Invalid email or password' });
    }
    const { password: _, ...userWithoutPassword } = user;
    return done(null, userWithoutPassword);
  }
));

// JWT Strategy for token validation
passport.use(new JwtStrategy({
    jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
    secretOrKey: JWT_SECRET,
  },
  async (payload, done) => {
    const user = await prisma.user.findUnique({ where: { id: payload.sub } });
    if (!user) return done(null, false);
    const { password: _, ...userWithoutPassword } = user;
    return done(null, userWithoutPassword);
  }
));
```

### Authentication Strategies

1. **Local Strategy**
   - Used for `/api/auth/login` endpoint
   - Validates email and password
   - Returns user without password field

2. **JWT Strategy**
   - Used for all protected routes
   - Extracts token from Authorization header
   - Validates token and loads user from database

### Authentication Controller

Located in `backend/src/controllers/authController.ts`:

**Key Functions:**

1. **register**: Creates new user account
   - Validates email uniqueness
   - Hashes password with bcrypt (10 rounds)
   - Generates JWT token
   - Returns user data and token

2. **login**: Authenticates existing user
   - Uses Passport local strategy
   - Generates JWT token on success
   - Returns user data and token

3. **getProfile**: Returns current user data
   - Requires valid JWT token
   - Returns user without password

### Authentication Middleware

Located in `backend/src/middleware/authMiddleware.ts`:

```typescript
// Require authentication - blocks access if not authenticated
export const requireAuth = (req, res, next) => {
  passport.authenticate('jwt', { session: false }, (err, user, info) => {
    if (err || !user) {
      return res.status(401).json({ 
        error: 'Unauthorized',
        message: 'You must be logged in to access this resource' 
      });
    }
    req.user = user;
    next();
  })(req, res, next);
};

// Optional authentication - attaches user if token valid
export const optionalAuth = (req, res, next) => {
  passport.authenticate('jwt', { session: false }, (err, user) => {
    if (user) req.user = user;
    next();
  })(req, res, next);
};
```

### Route Protection

**Public Routes:**
- `GET /health` - Health check
- `GET /ready` - Readiness check
- `GET /metrics` - Prometheus metrics
- `POST /api/auth/register` - User registration
- `POST /api/auth/login` - User login

**Protected Routes (require authentication):**
- `GET /api/auth/profile` - Get user profile
- `POST /api/projects` - Create project
- `PUT /api/projects/:id` - Update project
- `DELETE /api/projects/:id` - Delete project
- `GET /api/projects/:id` - Get single project

**Partially Protected:**
- `GET /api/projects` - Uses `optionalAuth`, filters by user if authenticated

### Password Security

- Passwords hashed using bcrypt with cost factor 10
- Original passwords never stored or logged
- Password comparison done using bcrypt.compare()
- Minimum password length enforced by frontend (6 characters)

## Frontend Implementation

### Authentication Service

Located in `frontend/src/services/authService.ts`:

**Core Functions:**

```typescript
// Token management
const setToken = (token: string): void => {
  localStorage.setItem('token', token);
};

export const getToken = (): string | null => {
  return localStorage.getItem('token');
};

export const removeToken = (): void => {
  localStorage.removeItem('token');
};

// API calls
export const register = async (userData: RegisterData): Promise<AuthResponse> => {
  const response = await axios.post(`${AUTH_URL}/register`, userData);
  if (response.data.token) setToken(response.data.token);
  return response.data;
};

export const login = async (credentials: LoginCredentials): Promise<AuthResponse> => {
  const response = await axios.post(`${AUTH_URL}/login`, credentials);
  if (response.data.token) setToken(response.data.token);
  return response.data;
};

// Authenticated axios instance
export const authAxios = axios.create();
authAxios.interceptors.request.use((config) => {
  const token = getToken();
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});
```

### Authentication Context

Located in `frontend/src/context/AuthContext.tsx`:

**Features:**
- Provides authentication state to entire app
- Automatically loads user on app startup
- Handles login/logout operations
- Manages loading and error states

**Context Value:**
```typescript
interface AuthContextType {
  user: User | null;
  loading: boolean;
  error: string | null;
  isAuthenticated: boolean;
  login: (user: User) => void;
  logout: () => void;
}
```

**Key Behaviors:**
1. On mount: Checks for existing token and loads user
2. On login: Stores user in state
3. On logout: Clears token and user state
4. On token expiry: Clears invalid token and shows error

### Protected Routes Component

Located in `frontend/src/components/ProtectedRoute.tsx`:

```typescript
const ProtectedRoute: React.FC<{ children: ReactNode }> = ({ children }) => {
  const { isAuthenticated, loading } = useAuth();
  const location = useLocation();

  if (loading) {
    return <LoadingSpinner message="Checking authentication..." />;
  }

  if (!isAuthenticated) {
    // Save attempted location for redirect after login
    return <Navigate to="/login" state={{ from: location }} replace />;
  }

  return <>{children}</>;
};
```

### Authentication Flow

1. **Registration Flow:**
   ```
   User fills form → Frontend validates → POST /api/auth/register
   → Backend creates user → Returns token → Frontend stores token
   → Updates auth context → Redirects to home
   ```

2. **Login Flow:**
   ```
   User enters credentials → POST /api/auth/login → Backend validates
   → Returns token → Frontend stores token → Updates auth context
   → Redirects to intended page or home
   ```

3. **Logout Flow:**
   ```
   User clicks logout → Frontend removes token → Clears auth context
   → Redirects to home
   ```

4. **Protected Route Access:**
   ```
   User navigates to protected route → ProtectedRoute checks auth
   → If not authenticated, redirect to login → After login, redirect back
   ```

### Token Management

**Storage:**
- Tokens stored in localStorage
- Automatically included in API requests via axios interceptor

**Expiration:**
- Tokens expire after 7 days
- Frontend handles expired tokens by clearing and redirecting to login

**Security Considerations:**
- XSS vulnerability: localStorage accessible to JavaScript
- Consider httpOnly cookies for production
- Implement token refresh mechanism for better UX

## Security Best Practices

### Implemented Security Measures

1. **Password Security:**
   - bcrypt with cost factor 10
   - Passwords never returned in API responses
   - Minimum length validation

2. **JWT Security:**
   - Secure secret key configuration
   - 7-day expiration
   - Token validated on every request

3. **API Security:**
   - CORS properly configured
   - Authorization checks on all protected routes
   - User can only access own resources

4. **Frontend Security:**
   - Protected routes component
   - Automatic logout on token expiry
   - Loading states prevent UI flashing

### Recommended Improvements

1. **Token Storage:**
   ```javascript
   // Consider using httpOnly cookies instead of localStorage
   // Implement refresh tokens for better security
   ```

2. **Rate Limiting:**
   ```javascript
   // Add rate limiting to auth endpoints
   import rateLimit from 'express-rate-limit';
   
   const authLimiter = rateLimit({
     windowMs: 15 * 60 * 1000, // 15 minutes
     max: 5 // limit each IP to 5 requests per windowMs
   });
   
   router.post('/login', authLimiter, login);
   ```

3. **Additional Validation:**
   - Email verification
   - Password strength requirements
   - Two-factor authentication

## Testing Authentication

### Backend Testing

Mock implementations in `backend/tests/auth.test.ts`:

```typescript
// Mock Prisma for user operations
jest.mock('@prisma/client', () => {
  const mPrisma = {
    user: {
      findUnique: jest.fn().mockImplementation(({ where }) => {
        // Return test user data
      }),
      create: jest.fn().mockResolvedValue({
        // New user data
      }),
    },
  };
  return { PrismaClient: jest.fn(() => mPrisma) };
});

// Test JWT token generation
const token = generateTestToken('test-user-id');
```

### Frontend Testing

Test authentication flows:

```typescript
// Test protected route
const { getByText } = render(
  <AuthProvider>
    <ProtectedRoute>
      <div>Protected Content</div>
    </ProtectedRoute>
  </AuthProvider>
);

// Test login flow
await act(async () => {
  fireEvent.click(getByText('Login'));
});
```

## Common Issues & Troubleshooting

### Issue: "Invalid token" errors
**Solution:**
- Verify JWT_SECRET matches between token generation and validation
- Check token hasn't expired (7-day limit)
- Ensure token format is correct: `Bearer <token>`

### Issue: User not loading after refresh
**Solution:**
- Check if token is properly saved in localStorage
- Verify `/api/auth/profile` endpoint is working
- Check for CORS issues

### Issue: CORS errors
**Solution:**
- Ensure CORS_ORIGIN in backend matches frontend URL
- Check for trailing slashes in URLs
- Verify allowed headers include Authorization

### Issue: "Unauthorized" on protected routes
**Solution:**
- Verify token is included in request headers
- Check if user owns the resource (projects)
- Ensure middleware is properly applied to routes

### Issue: Password validation fails
**Solution:**
- Verify bcrypt rounds match (should be 10)
- Check password isn't being trimmed incorrectly
- Ensure comparison uses hashed password from DB

## API Usage Examples

### Using cURL

**Register new user:**
```bash
curl -X POST http://localhost:3001/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123",
    "name": "Test User"
  }'
```

**Login and save token:**
```bash
# Login
RESPONSE=$(curl -X POST http://localhost:3001/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123"
  }')

# Extract token (requires jq)
TOKEN=$(echo $RESPONSE | jq -r '.token')

# Use token for authenticated requests
curl -X GET http://localhost:3001/api/auth/profile \
  -H "Authorization: Bearer $TOKEN"
```

### Using JavaScript/TypeScript

**With the auth service:**
```typescript
import { login, getCurrentUser, authAxios } from './services/authService';

// Login
const { user, token } = await login({
  email: 'test@example.com',
  password: 'password123'
});

// Get current user
const currentUser = await getCurrentUser();

// Make authenticated API call
const projects = await authAxios.get('/projects');
```

**Direct fetch API:**
```javascript
// Login
const loginResponse = await fetch('http://localhost:3001/api/auth/login', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    email: 'test@example.com',
    password: 'password123'
  })
});
const { token } = await loginResponse.json();

// Use token
const projectsResponse = await fetch('http://localhost:3001/api/projects', {
  headers: { 'Authorization': `Bearer ${token}` }
});
const projects = await projectsResponse.json();
```