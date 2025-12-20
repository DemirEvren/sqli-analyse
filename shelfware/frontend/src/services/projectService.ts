// frontend/src/services/projectService.ts
import { Project, ProjectFormData } from '../interfaces/Project';
import { authAxios } from './authService';

// Use relative path for API - will be proxied through nginx
const API_URL = '/api';
const PROJECTS_URL = `${API_URL}/projects`;

// Get all projects - uses the authenticated axios instance
export const getProjects = async (): Promise<Project[]> => {
  const response = await authAxios.get(PROJECTS_URL);
  return response.data;
};

// Get a single project by ID
export const getProjectById = async (id: string): Promise<Project> => {
  const response = await authAxios.get(`${PROJECTS_URL}/${id}`);
  return response.data;
};

// Create a new project
export const createProject = async (projectData: ProjectFormData): Promise<Project> => {
  // Process hardware info from string to JSON if provided
  const processedData = {
    ...projectData,
    hardwareInfo: projectData.hardwareInfo ? JSON.parse(projectData.hardwareInfo) : undefined
  };
  
  const response = await authAxios.post(PROJECTS_URL, processedData);
  return response.data;
};

// Update an existing project
export const updateProject = async (id: string, projectData: ProjectFormData): Promise<Project> => {
  // Process hardware info from string to JSON if provided
  const processedData = {
    ...projectData,
    hardwareInfo: projectData.hardwareInfo ? JSON.parse(projectData.hardwareInfo) : undefined
  };
  
  const response = await authAxios.put(`${PROJECTS_URL}/${id}`, processedData);
  return response.data;
};

// Delete a project
export const deleteProject = async (id: string): Promise<void> => {
  await authAxios.delete(`${PROJECTS_URL}/${id}`);
};