import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import Navbar from './components/Navbar.tsx';
import ThemeToggle from './components/ThemeToggle.tsx';
import ProjectsOverview from './pages/ProjectsOverview.tsx';
import CreateProject from './pages/CreateProject.tsx';
import EditProject from './pages/EditProject.tsx';
import ProjectDetails from './pages/ProjectDetails.tsx';
import AboutPage from './pages/AboutPage.tsx';
import Login from './pages/Login.tsx';
import Register from './pages/Register.tsx';
import Profile from './pages/Profile.tsx';
import ProtectedRoute from './components/ProtectedRoute.tsx';
import { AuthProvider, useAuth } from './context/AuthContext.tsx';
import './App.css';

const App: React.FC = () => {
  return (
    <BrowserRouter>
      <AuthProvider>
        <AppContent />
      </AuthProvider>
    </BrowserRouter>
  );
};

const AppContent: React.FC = () => {
  const { isAuthenticated } = useAuth();
  
  return (
    <div className="app">
      <Navbar />
      <main className="main-content">
        <Routes>
          {/* Public routes */}
          <Route path="/login" element={
            isAuthenticated ? <Navigate to="/" /> : <Login />
          } />
          <Route path="/register" element={
            isAuthenticated ? <Navigate to="/" /> : <Register />
          } />
          <Route path="/about" element={<AboutPage />} />
          
          {/* Protected routes */}
          <Route path="/" element={<ProjectsOverview />} />
          <Route path="/create" element={
            <ProtectedRoute>
              <CreateProject />
            </ProtectedRoute>
          } />
          <Route path="/edit/:id" element={
            <ProtectedRoute>
              <EditProject />
            </ProtectedRoute>
          } />
          <Route path="/project/:id" element={
            <ProtectedRoute>
              <ProjectDetails />
            </ProtectedRoute>
          } />
          <Route path="/profile" element={
            <ProtectedRoute>
              <Profile />
            </ProtectedRoute>
          } />
        </Routes>
      </main>
      <ThemeToggle />
      <footer className="footer">
        <p>&copy; {new Date().getFullYear()} PXL Shelfware Tracker - Track your side projects</p>
      </footer>
    </div>
  );
};

export default App;