// frontend/src/services/authService.ts
import axios from 'axios';

// frontend/src/services/authService.ts
const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:3001/api';
const AUTH_URL = `${API_URL}/auth`;  // This should be just /auth, not /projects/auth

// Types for authentication
export interface LoginCredentials {
  email: string;
  password: string;
}

export interface RegisterData {
  email: string;
  password: string;
  name?: string;
}

export interface AuthResponse {
  user: {
    id: string;
    email: string;
    name?: string;
  };
  token: string;
}

export interface User {
  id: string;
  email: string;
  name?: string;
}

// Store token in localStorage
const setToken = (token: string): void => {
  localStorage.setItem('token', token);
};

// Get stored token
export const getToken = (): string | null => {
  return localStorage.getItem('token');
};

// Remove token (logout)
export const removeToken = (): void => {
  localStorage.removeItem('token');
};

// Register a new user
export const register = async (userData: RegisterData): Promise<AuthResponse> => {
  const response = await axios.post<AuthResponse>(`${AUTH_URL}/register`, userData);
  if (response.data.token) {
    setToken(response.data.token);
  }
  return response.data;
};

// Login user
export const login = async (credentials: LoginCredentials): Promise<AuthResponse> => {
  const response = await axios.post<AuthResponse>(`${AUTH_URL}/login`, credentials);
  if (response.data.token) {
    setToken(response.data.token);
  }
  return response.data;
};

// Get current user profile
export const getCurrentUser = async (): Promise<User> => {
  const token = getToken();
  if (!token) {
    throw new Error('Not authenticated');
  }
  
  const response = await axios.get<User>(`${AUTH_URL}/profile`, {
    headers: {
      Authorization: `Bearer ${token}`
    }
  });
  
  return response.data;
};

// Check if user is authenticated
export const isAuthenticated = (): boolean => {
  return getToken() !== null;
};

// Create an axios instance with auth header
export const authAxios = axios.create();

// Add interceptor to add token to requests
authAxios.interceptors.request.use((config) => {
  const token = getToken();
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});