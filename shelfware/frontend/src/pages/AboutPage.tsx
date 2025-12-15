import React from 'react';
import './AboutPage.css';
import pxlLogo from '../assets/pxl-logo.png'; // You'll need to add this logo to your assets folder

const AboutPage: React.FC = () => {
  return (
    <div className="about-container">
      <h1>About Shelfware Tracker</h1>
      
      <div className="about-content">
        <section className="about-section">
          <h2>Project Overview</h2>
          <p>
            Shelfware Tracker is an educational project developed by PXL Hogeschool 
            to demonstrate modern web development techniques and practices. This application 
            serves as a practical example for students learning full-stack development 
            with React, TypeScript, Node.js, and PostgreSQL.
          </p>
          <p>
            The application allows users to track side projects by managing details 
            such as project status, descriptions, repository links, and hardware components.
          </p>
        </section>
        
        <section className="about-section">
          <h2>Educational Purpose</h2>
          <p>
            This application is designed as a learning tool for students to understand:
          </p>
          <ul>
            <li>React component architecture and state management</li>
            <li>TypeScript interfaces and type safety</li>
            <li>RESTful API design and integration</li>
            <li>Database modeling and queries with Prisma ORM</li>
            <li>Responsive UI design with CSS</li>
            <li>Light/dark theme implementation</li>
          </ul>
          <p>
            Students can explore the code structure, examine the implementation of 
            features, and extend the application with their own enhancements.
          </p>
        </section>
        
        <section className="about-section">
          <h2>Technologies Used</h2>
          <div className="tech-grid">
            <div className="tech-item">
              <h3>Frontend</h3>
              <ul>
                <li>React</li>
                <li>TypeScript</li>
                <li>React Router</li>
                <li>CSS</li>
              </ul>
            </div>
            <div className="tech-item">
              <h3>Backend</h3>
              <ul>
                <li>Node.js</li>
                <li>Express</li>
                <li>Prisma ORM</li>
                <li>PostgreSQL</li>
              </ul>
            </div>
          </div>
        </section>
      </div>
      
      <div className="pxl-info">
        <div className="pxl-logo-container">
          <a href="https://www.pxl.be/" target="_blank" rel="noopener noreferrer">
            <img src={pxlLogo} alt="PXL Hogeschool Logo" className="pxl-logo" />
          </a>
        </div>
        <p>
          This web application is created by 
          <a href="https://www.pxl.be/" target="_blank" rel="noopener noreferrer"> PXL Hogeschool </a> 
          for educational purposes. It demonstrates best practices in modern web development 
          and serves as a learning resource for students in programming and application development courses.
        </p>
      </div>
    </div>
  );
};

export default AboutPage;