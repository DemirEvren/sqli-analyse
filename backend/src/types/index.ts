// backend/src/types/index.ts
export interface User {
    id: string;
    email: string;
    name?: string;
    password?: string;
    createdAt?: Date;
    updatedAt?: Date;
  }
  
  // Extend Express Request to include user
  declare global {
    namespace Express {
      interface Request {
        user?: User;
      }
    }
  }