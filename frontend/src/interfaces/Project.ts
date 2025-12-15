// Project interface - represents a project in the system
export interface Project {
    id: string;  // Changed from number to string
    title: string;
    status: 'Planning' | 'In Progress' | 'Completed' | 'Abandoned';
    description?: string;
    githubUrl?: string;
    deployedUrl?: string;
    docsUrl?: string;
    hardwareInfo?: any;
    createdAt?: string;
    updatedAt?: string;
  }
  
  // ProjectFormData - used for creating/editing projects
  export interface ProjectFormData {
    title: string;
    status: string;
    description: string;
    githubUrl: string;
    deployedUrl: string;
    docsUrl: string;
    hardwareInfo: string; // JSON string
  }
  
  // Initial empty form data
  export const emptyProjectForm: ProjectFormData = {
    title: '',
    status: 'Planning',
    description: '',
    githubUrl: '',
    deployedUrl: '',
    docsUrl: '',
    hardwareInfo: ''
  };