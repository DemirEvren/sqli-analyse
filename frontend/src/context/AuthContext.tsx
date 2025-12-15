// frontend/src/context/AuthContext.tsx
import React, { createContext, useState, useEffect, useContext, ReactNode } from 'react';
import { User, removeToken, getCurrentUser, isAuthenticated } from '../services/authService';

interface AuthContextType {
  user: User | null;
  loading: boolean;
  error: string | null;
  isAuthenticated: boolean;
  login: (user: User) => void;
  logout: () => void;
}

// Create context with default values
const AuthContext = createContext<AuthContextType>({
  user: null,
  loading: true,
  error: null,
  isAuthenticated: false,
  login: () => {},
  logout: () => {},
});

// Provider component
export const AuthProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Load user on initial render if token exists
  useEffect(() => {
    const loadUser = async () => {
      if (!isAuthenticated()) {
        setLoading(false);
        return;
      }

      try {
        const userData = await getCurrentUser();
        setUser(userData);
      } catch (err) {
        console.error('Failed to load user:', err);
        setError('Session expired. Please login again.');
        // Clear invalid token
        removeToken();
      } finally {
        setLoading(false);
      }
    };

    loadUser();
  }, []);

  // Login: store user in state
  const login = (userData: User) => {
    setUser(userData);
    setError(null);
  };

  // Logout: remove token and clear user state
  const logout = () => {
    removeToken();
    setUser(null);
  };

  // Value provided to consumers
  const value = {
    user,
    loading,
    error,
    isAuthenticated: !!user,
    login,
    logout,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
};

// Custom hook for using the auth context
export const useAuth = () => {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};