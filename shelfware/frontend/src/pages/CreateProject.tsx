import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { createProject } from '../services/projectService.ts';
import { ProjectFormData, emptyProjectForm } from '../interfaces/Project.ts';
import { safeJsonParse } from '../utils/formatters.ts';
import './ProjectForm.css';

const CreateProject: React.FC = () => {
  const navigate = useNavigate();
  const [formData, setFormData] = useState<ProjectFormData>(emptyProjectForm);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [submitting, setSubmitting] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  const validate = (): boolean => {
    const newErrors: Record<string, string> = {};
    
    // Title is required
    if (!formData.title.trim()) {
      newErrors.title = 'Title is required';
    }
    
    // Status is required
    if (!formData.status) {
      newErrors.status = 'Status is required';
    }
    
    // Validate hardware info JSON if provided
    if (formData.hardwareInfo.trim()) {
      try {
        safeJsonParse(formData.hardwareInfo);
      } catch (error) {
        newErrors.hardwareInfo = 'Invalid JSON format';
      }
    }
    
    // Validate URLs if provided
    const urlFields = ['githubUrl', 'deployedUrl', 'docsUrl'];
    urlFields.forEach(field => {
      const value = formData[field as keyof ProjectFormData] as string;
      if (value && !isValidUrl(value)) {
        newErrors[field] = 'Please enter a valid URL';
      }
    });
    
    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };
  
  const isValidUrl = (url: string): boolean => {
    if (!url) return true;
    try {
      new URL(url);
      return true;
    } catch (error) {
      return false;
    }
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => {
    const { name, value } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: value
    }));
    
    // Clear field-specific error when user corrects it
    if (errors[name]) {
      setErrors(prev => {
        const newErrors = { ...prev };
        delete newErrors[name];
        return newErrors;
      });
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setFormError(null);
    
    // Validate form
    if (!validate()) {
      return;
    }
    
    setSubmitting(true);
    
    try {
      await createProject(formData);
      navigate('/');
    } catch (error) {
      console.error('Error creating project:', error);
      setFormError('Failed to create project. Please try again.');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="project-form-container">
      <h1>Add New Project</h1>
      
      {formError && (
        <div className="form-error">{formError}</div>
      )}
      
      <form onSubmit={handleSubmit} className="project-form">
        <div className="form-group">
          <label htmlFor="title">
            Title <span className="required">*</span>
          </label>
          <input
            type="text"
            id="title"
            name="title"
            value={formData.title}
            onChange={handleChange}
            disabled={submitting}
          />
          {errors.title && <span className="error-message">{errors.title}</span>}
        </div>
        
        <div className="form-group">
          <label htmlFor="status">
            Status <span className="required">*</span>
          </label>
          <select
            id="status"
            name="status"
            value={formData.status}
            onChange={handleChange}
            disabled={submitting}
          >
            <option value="Planning">Planning</option>
            <option value="In Progress">In Progress</option>
            <option value="Completed">Completed</option>
            <option value="Abandoned">Abandoned</option>
          </select>
          {errors.status && <span className="error-message">{errors.status}</span>}
        </div>
        
        <div className="form-group">
          <label htmlFor="description">Description</label>
          <textarea
            id="description"
            name="description"
            value={formData.description}
            onChange={handleChange}
            rows={3}
            disabled={submitting}
          />
        </div>
        
        <div className="form-group">
          <label htmlFor="githubUrl">GitHub URL</label>
          <input
            type="url"
            id="githubUrl"
            name="githubUrl"
            value={formData.githubUrl}
            onChange={handleChange}
            disabled={submitting}
          />
          {errors.githubUrl && <span className="error-message">{errors.githubUrl}</span>}
        </div>
        
        <div className="form-group">
          <label htmlFor="deployedUrl">Deployed URL</label>
          <input
            type="url"
            id="deployedUrl"
            name="deployedUrl"
            value={formData.deployedUrl}
            onChange={handleChange}
            disabled={submitting}
          />
          {errors.deployedUrl && <span className="error-message">{errors.deployedUrl}</span>}
        </div>
        
        <div className="form-group">
          <label htmlFor="docsUrl">Documentation URL</label>
          <input
            type="url"
            id="docsUrl"
            name="docsUrl"
            value={formData.docsUrl}
            onChange={handleChange}
            disabled={submitting}
          />
          {errors.docsUrl && <span className="error-message">{errors.docsUrl}</span>}
        </div>
        
        <div className="form-group">
          <label htmlFor="hardwareInfo">
            Components <span className="hint">(JSON format)</span>
          </label>
          <textarea
            id="hardwareInfo"
            name="hardwareInfo"
            value={formData.hardwareInfo}
            onChange={handleChange}
            rows={3}
            placeholder='{"cpu": "Raspberry Pi 4", "memory": "4GB"}'
            disabled={submitting}
          />
          {errors.hardwareInfo && <span className="error-message">{errors.hardwareInfo}</span>}
        </div>
        
        <div className="form-actions">
          <button 
            type="button" 
            onClick={() => navigate('/')}
            className="cancel-button"
            disabled={submitting}
          >
            Cancel
          </button>
          <button 
            type="submit" 
            className="submit-button"
            disabled={submitting}
          >
            {submitting ? 'Creating...' : 'Create Project'}
          </button>
        </div>
      </form>
    </div>
  );
};

export default CreateProject;