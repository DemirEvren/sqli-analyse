import React from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import './Navbar.css';
import logo from '../assets/logo.png';

const Navbar: React.FC = () => {
  const location = useLocation();
  const navigate = useNavigate();
  const { isAuthenticated, user, logout } = useAuth();
  
  const handleLogout = () => {
    logout();
    navigate('/');
  };
  
  return (
    <nav className="navbar">
      {/* Modified structure to better control layout */}
      <div className="navbar-left">
        <div className="navbar-logo">
          <Link to="/">
            <img src={logo} alt="Shelfware Tracker Logo" className="logo-image" />
            <span className="logo-text">PXL Shelfware Tracker</span>
          </Link>
        </div>
      </div>
    
    
      
      <div className="navbar-right">
        <ul className="navbar-links">
          <li className={location.pathname === '/' ? 'active' : ''}>
            <Link to="/">Projects</Link>
          </li>
          <li className={location.pathname === '/about' ? 'active' : ''}>
            <Link to="/about">About</Link>
          </li>
          {isAuthenticated ? (
            <>
              <li className={location.pathname === '/profile' ? 'active' : ''}>
                <Link to="/profile">{user?.name || user?.email}</Link>
              </li>
              <li>
                <button onClick={handleLogout} className="logout-button">Logout</button>
              </li>
            </>
          ) : (
            <>
              <li className={location.pathname === '/login' ? 'active' : ''}>
                <Link to="/login">Login</Link>
              </li>
              <li className={location.pathname === '/register' ? 'active' : ''}>
                <Link to="/register">Register</Link>
              </li>
            </>
          )}
        </ul>
      </div>
    </nav>
  );
};

export default Navbar;