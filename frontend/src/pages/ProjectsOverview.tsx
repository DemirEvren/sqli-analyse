import React, { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import ProjectCard from '../components/ProjectCard';
import LoadingSpinner from '../components/LoadingSpinner.tsx';
import ConfirmDialog from '../components/ConfirmDialog.tsx';
import { getProjects, deleteProject } from '../services/projectService.ts';
import { Project } from '../interfaces/Project.ts';
import { useAuth } from '../context/AuthContext';
import './ProjectsOverview.css';

const ProjectsOverview: React.FC = () => {
  const [projects, setProjects] = useState<Project[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [projectToDelete, setProjectToDelete] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState('All');
  
  const { isAuthenticated } = useAuth();

  useEffect(() => {
    if (isAuthenticated) {
      fetchProjects();
    } else {
      setProjects([]);
      setLoading(false);
    }
  }, [isAuthenticated]);

  const fetchProjects = async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await getProjects();
      setProjects(data);
    } catch (err) {
      console.error('Error fetching projects:', err);
      setError('Failed to load projects. Please try again later.');
    } finally {
      setLoading(false);
    }
  };

  const handleDeleteClick = (id: string) => {
    setProjectToDelete(id);
    setDeleteDialogOpen(true);
  };

  const handleDeleteConfirm = async () => {
    if (projectToDelete === null) return;
    
    try {
      await deleteProject(projectToDelete);
      setProjects(projects.filter(project => project.id !== projectToDelete));
      setDeleteDialogOpen(false);
      setProjectToDelete(null);
    } catch (err) {
      console.error('Error deleting project:', err);
      setError('Failed to delete project. Please try again.');
    }
  };

  const handleDeleteCancel = () => {
    setDeleteDialogOpen(false);
    setProjectToDelete(null);
  };

  // Filter projects based on search term and status filter
  const filteredProjects = projects.filter(project => {
    const matchesSearch = project.title.toLowerCase().includes(searchTerm.toLowerCase()) ||
                          (project.description && project.description.toLowerCase().includes(searchTerm.toLowerCase()));
    
    const matchesStatus = statusFilter === 'All' || project.status === statusFilter;
    
    return matchesSearch && matchesStatus;
  });

  if (loading) return <LoadingSpinner message="Loading projects..." />;

  if (!isAuthenticated) {
    return (
      <div className="projects-overview">
        <div className="auth-prompt">
          <p>Please <Link to="/login">login</Link> or <Link to="/register">register</Link> to start tracking your projects.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="projects-overview">
      <div className="overview-header">
        <h1>My Projects</h1>
        <Link to="/create" className="add-project-button">
          Add New Project
        </Link>
      </div>

      {error && <div className="error-message">{error}</div>}

      <div className="filters">
        <div className="search-box">
          <input
            type="text"
            placeholder="Search projects..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
          />
        </div>
        
        <div className="status-filter">
          <label htmlFor="status-select">Status:</label>
          <select 
            id="status-select"
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
          >
            <option value="All">All</option>
            <option value="Planning">Planning</option>
            <option value="In Progress">In Progress</option>
            <option value="Completed">Completed</option>
            <option value="Abandoned">Abandoned</option>
          </select>
        </div>
      </div>

      {filteredProjects.length === 0 ? (
        <div className="empty-state">
          <p>No projects found. Get started by adding your first project!</p>
          <Link to="/create" className="empty-add-button">
            Add Project
          </Link>
        </div>
      ) : (
        <div className="projects-grid">
          {filteredProjects.map(project => (
            <ProjectCard 
              key={project.id} 
              project={project} 
              onDelete={handleDeleteClick} 
            />
          ))}
        </div>
      )}

      <ConfirmDialog
        isOpen={deleteDialogOpen}
        title="Delete Project"
        message="Are you sure you want to delete this project? This action cannot be undone."
        onConfirm={handleDeleteConfirm}
        onCancel={handleDeleteCancel}
      />
    </div>
  );
};

export default ProjectsOverview;