import express, { Request, Response, NextFunction } from 'express';
import { PrismaClient } from '@prisma/client';
import cors from 'cors';
import promClient from 'prom-client';
import passport from './config/passport';
import authRoutes from './routes/authRoutes';
import { requireAuth, optionalAuth } from './middleware/authMiddleware';
//import corsMiddleware from 'cors-anywhere';

// --- Prometheus Setup (Monitoring) ---
promClient.collectDefaultMetrics();

const httpRequestDurationMicroseconds = new promClient.Histogram({
  name: 'http_request_duration_ms',
  help: 'Duration of HTTP requests in ms',
  labelNames: ['method', 'route', 'code'],
  buckets: [50, 100, 200, 500, 1000, 2500, 5000]
});
const httpRequestsTotal = new promClient.Counter({
    name: 'http_requests_total',
    help: 'Total number of HTTP requests',
    labelNames: ['method', 'route', 'code']
});

// --- Prisma Client Setup ---
const prisma = new PrismaClient({
  datasources: {
    db: {
      url: process.env.DATABASE_URL || "postgresql://postgres:postgres@localhost:5432/shelfware?schema=public"
    }
  }
});

// Create an Express application instance.
const app = express();

// Define the server port. Use environment variable or default to 3001.
const PORT: number = parseInt(process.env.BACKEND_PORT || '3001', 10);

const defaultOrigins = [
  'http://localhost:5173',
  'http://localhost:3001'
];

const allowedOrigins = process.env.CORS_ORIGIN
  ? process.env.CORS_ORIGIN.split(',').map(origin => origin.trim())
  : defaultOrigins;

app.use(cors({
  origin: (origin, callback) => {
    if (!origin || allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      callback(new Error(`CORS blocked for origin: ${origin}`));
    }
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

app.use(express.json());

// Initialize Passport
app.use(passport.initialize());

// --- Prometheus Request Tracking Middleware ---
app.use((req: Request, res: Response, next: NextFunction) => {
  const end = httpRequestDurationMicroseconds.startTimer();
  res.on('finish', () => {
    const route = req.route ? req.route.path : req.path.replace(/\/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}|^\/[0-9]+$/g, '/:id');
    const labels = { method: req.method, route: route, code: res.statusCode.toString() };
    end(labels);
    httpRequestsTotal.inc(labels);
  });
  next();
});

// --- Health & Readiness Routes ---
app.get('/health', (req: Request, res: Response) => {
  res.status(200).json({ status: 'UP' });
});

app.get('/ready', async (req: Request, res: Response) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.status(200).json({ status: 'READY', checks: { database: 'OK' } });
  } catch (error) {
    console.error("Readiness check failed:", error);
    res.status(503).json({
      status: 'UNAVAILABLE',
      checks: { database: 'FAILING' },
      error: 'Database connection failed'
    });
  }
});

// --- Prometheus Metrics Route ---
app.get('/metrics', async (req: Request, res: Response) => {
  try {
    res.set('Content-Type', promClient.register.contentType);
    res.end(await promClient.register.metrics());
  } catch (error) {
    console.error("Failed to retrieve metrics:", error);
    res.status(500).json({ error: 'Failed to retrieve metrics' });
  }
});

// --- Authentication Routes ---
app.use('/api/auth', authRoutes);

// --- API Routes ---
// Root route
app.get('/', (req: Request, res: Response) => {
  res.send('Shelfware API is running');
});

// GET /api/projects: Retrieve all projects.
// Uses optionalAuth to attach user but doesn't require login
app.get('/api/projects', optionalAuth, async (req: Request, res: Response) => {
  try {
    // If user is authenticated, filter by their user ID
    const whereClause = req.user 
      ? { userId: (req.user as any).id } 
      : {};
      
    const projects = await prisma.project.findMany({
      where: whereClause,
      orderBy: { createdAt: 'desc' }
    });
    res.json(projects);
  } catch (error) {
    console.error("Failed to retrieve projects:", error);
    res.status(500).json({ error: 'Failed to retrieve projects' });
  }
});

// GET /api/projects/:id: Retrieve a single project by its ID.
// Uses requireAuth to ensure only authenticated users can access
app.get('/api/projects/:id', requireAuth, async (req: Request, res: Response) => {
  const { id } = req.params;
  try {
    const project = await prisma.project.findUnique({
      where: { id }
    });
    
    if (!project) {
      return res.status(404).json({ error: 'Project not found' });
    }
    
    // Check if project belongs to the authenticated user
    if (project.userId && project.userId !== (req.user as any).id) {
      return res.status(403).json({ error: 'You do not have permission to access this project' });
    }
    
    res.json(project);
  } catch (error) {
    console.error("Failed to retrieve project:", error);
    if (error instanceof Error && 'code' in error && error.code === 'P2023') {
      return res.status(400).json({ error: 'Invalid project ID format' });
    }
    res.status(500).json({ error: 'Failed to retrieve project' });
  }
});

// POST /api/projects: Create a new project.
// Requires authentication
app.post('/api/projects', requireAuth, async (req: Request, res: Response) => {
  const { title, status, description, githubUrl, deployedUrl, docsUrl, hardwareInfo } = req.body;

  if (!title || !status) {
    return res.status(400).json({ error: 'Title and status are required' });
  }

  try {
    const newProject = await prisma.project.create({
      data: {
        title,
        status,
        description,
        githubUrl,
        deployedUrl,
        docsUrl,
        hardwareInfo,
        // Associate with the authenticated user
        userId: (req.user as any).id
      },
    });
    res.status(201).json(newProject);
  } catch (error) {
    console.error("Failed to create project:", error);
    res.status(500).json({ error: 'Failed to create project' });
  }
});

// PUT /api/projects/:id: Update an existing project by ID.
// Requires authentication
app.put('/api/projects/:id', requireAuth, async (req: Request, res: Response) => {
  const { id } = req.params;
  const { title, status, description, githubUrl, deployedUrl, docsUrl, hardwareInfo } = req.body;

  if (!title || !status) {
    return res.status(400).json({ error: 'Title and status are required' });
  }

  try {
    // First check if the project exists and belongs to the user
    const existingProject = await prisma.project.findUnique({
      where: { id }
    });
    
    if (!existingProject) {
      return res.status(404).json({ error: 'Project not found' });
    }
    
    // Check if project belongs to the authenticated user
    if (existingProject.userId && existingProject.userId !== (req.user as any).id) {
      return res.status(403).json({ error: 'You do not have permission to modify this project' });
    }
    
    const updatedProject = await prisma.project.update({
      where: { id },
      data: {
        title,
        status,
        description,
        githubUrl,
        deployedUrl,
        docsUrl,
        hardwareInfo
      }
    });
    res.json(updatedProject);
  } catch (error) {
    console.error("Failed to update project:", error);
    if (error instanceof Error && 'code' in error && error.code === 'P2025') {
      return res.status(404).json({ error: 'Project not found' });
    }
    if (error instanceof Error && 'code' in error && error.code === 'P2023') {
      return res.status(400).json({ error: 'Invalid project ID format' });
    }
    res.status(500).json({ error: 'Failed to update project' });
  }
});

// DELETE /api/projects/:id: Delete a project by ID.
// Requires authentication
app.delete('/api/projects/:id', requireAuth, async (req: Request, res: Response) => {
  const { id } = req.params;

  try {
    // First check if the project exists and belongs to the user
    const existingProject = await prisma.project.findUnique({
      where: { id }
    });
    
    if (!existingProject) {
      return res.status(404).json({ error: 'Project not found' });
    }
    
    // Check if project belongs to the authenticated user
    if (existingProject.userId && existingProject.userId !== (req.user as any).id) {
      return res.status(403).json({ error: 'You do not have permission to delete this project' });
    }
    
    await prisma.project.delete({
      where: { id }
    });
    res.status(204).send();
  } catch (error) {
    console.error("Failed to delete project:", error);
    if (error instanceof Error && 'code' in error && error.code === 'P2025') {
      return res.status(404).json({ error: 'Project not found' });
    }
    if (error instanceof Error && 'code' in error && error.code === 'P2023') {
      return res.status(400).json({ error: 'Invalid project ID format' });
    }
    res.status(500).json({ error: 'Failed to delete project' });
  }
});

// --- Global Error Handling Middleware ---
app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
    console.error("Unhandled error:", err);
    const errorMessage = process.env.NODE_ENV === 'production' ? 'An internal server error occurred' : err.message;
    res.status(500).json({ error: errorMessage });
});

// --- Start Server ---
if (require.main === module) {
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Backend server running at http://0.0.0.0:${PORT}`);
    console.log(`Using database: ${process.env.DATABASE_URL ? 'DATABASE_URL env var' : 'Default local PostgreSQL'}`);
    console.log(`CORS enabled for: ${Array.isArray(allowedOrigins) ? allowedOrigins.join(', ') : String(allowedOrigins)}`);
    console.log(`Health endpoint: http://localhost:${PORT}/health`);
    console.log(`Readiness endpoint: http://localhost:${PORT}/ready`);
    console.log(`Metrics endpoint: http://localhost:${PORT}/metrics`);
  });
}

export default app;