import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { Project } from '../interfaces/Project.ts';
import { formatDate, getStatusColor } from '../utils/formatters.ts';
import { useAuth } from '../context/AuthContext';
import './ProjectCard.css';

interface ProjectCardProps {
  project: Project;
  onDelete: (id: string) => void;
}

const ProjectCard: React.FC<ProjectCardProps> = ({ project, onDelete }) => {
  const [isComponentsExpanded, setIsComponentsExpanded] = useState(false);
  const { isAuthenticated } = useAuth();
  
  const statusStyle = {
    backgroundColor: getStatusColor(project.status)
  };

  // Parse and render hardware/components info in a clean way
  const renderComponents = () => {
    if (!project.hardwareInfo) return null;
    
    let componentsData;
    try {
      // If it's already an object, use it directly
      componentsData = typeof project.hardwareInfo === 'string' 
        ? JSON.parse(project.hardwareInfo) 
        : project.hardwareInfo;
    } catch (error) {
      // If parsing fails, just return the string
      return (
        <div className="component-raw">
          {String(project.hardwareInfo)}
        </div>
      );
    }
    
    // If it's an empty object or not an object, return null
    if (!componentsData || typeof componentsData !== 'object' || Array.isArray(componentsData)) {
      return null;
    }
    
    // If components data is small or expanded, show all items
    const entries = Object.entries(componentsData);
    const shouldShowAll = isComponentsExpanded || entries.length <= 3;
    const displayedEntries = shouldShowAll ? entries : entries.slice(0, 3);
    
    return (
      <div className="components-container">
        <ul className="components-list">
          {displayedEntries.map(([key, value]) => (
            <li key={key} className="component-item">
              <span className="component-name">{key}:</span>
              <span className="component-value">{String(value)}</span>
            </li>
          ))}
        </ul>
        
        {!shouldShowAll && entries.length > 3 && (
          <button 
            className="components-expand-button"
            onClick={(e) => {
              e.preventDefault(); // Prevent navigating away
              setIsComponentsExpanded(true);
            }}
          >
            Show {entries.length - 3} more...
          </button>
        )}
        
        {isComponentsExpanded && entries.length > 3 && (
          <button 
            className="components-collapse-button"
            onClick={(e) => {
              e.preventDefault(); // Prevent navigating away
              setIsComponentsExpanded(false);
            }}
          >
            Show less
          </button>
        )}
      </div>
    );
  };

  return (
    <div className="project-card">
      <div className="project-header">
        <h3>{project.title}</h3>
        <span className="project-status" style={statusStyle}>
          {project.status}
        </span>
      </div>
      
      {project.description && (
        <p className="project-description">{project.description}</p>
      )}
      
      <div className="project-links">
        {project.githubUrl && (
          <a href={project.githubUrl} target="_blank" rel="noopener noreferrer" className="link-github">
            GitHub
          </a>
        )}
        
        {project.deployedUrl && (
          <a href={project.deployedUrl} target="_blank" rel="noopener noreferrer" className="link-demo">
            Live Demo
          </a>
        )}
        
        {project.docsUrl && (
          <a href={project.docsUrl} target="_blank" rel="noopener noreferrer" className="link-docs">
            Docs
          </a>
        )}
      </div>
      
      {project.hardwareInfo && (
        <div className="components-info">
          <h4>Components:</h4>
          {renderComponents()}
        </div>
      )}
      
      {project.createdAt && (
        <div className="project-metadata">
          <span>Created: {formatDate(project.createdAt)}</span>
          {project.updatedAt && project.updatedAt !== project.createdAt && (
            <span>Updated: {formatDate(project.updatedAt)}</span>
          )}
        </div>
      )}
      
      <div className="project-actions">
        <Link to={`/project/${project.id}`} className="btn btn-view">
          View Details
        </Link>
        
        {isAuthenticated && (
          <>
            <Link to={`/edit/${project.id}`} className="btn btn-edit">
              Edit
            </Link>
            <button 
              onClick={() => onDelete(project.id)} 
              className="btn btn-delete"
            >
              Delete
            </button>
          </>
        )}
      </div>
    </div>
  );
};

export default ProjectCard;