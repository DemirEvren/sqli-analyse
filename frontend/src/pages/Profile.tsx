// frontend/src/pages/Profile.tsx
import React, { useEffect, useState } from 'react';
import { useAuth } from '../context/AuthContext';
import { getCurrentUser } from '../services/authService';
import LoadingSpinner from '../components/LoadingSpinner';
import './Profile.css';

const Profile: React.FC = () => {
  const { user: authUser, isAuthenticated } = useAuth();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [userDetails, setUserDetails] = useState(authUser);

  useEffect(() => {
    const fetchUserDetails = async () => {
      if (!isAuthenticated) {
        setLoading(false);
        return;
      }

      try {
        const userData = await getCurrentUser();
        setUserDetails(userData);
        setError(null);
      } catch (err) {
        console.error('Failed to load user details:', err);
        setError('Could not load profile information');
      } finally {
        setLoading(false);
      }
    };

    fetchUserDetails();
  }, [isAuthenticated]);

  if (loading) {
    return <LoadingSpinner message="Loading profile..." />;
  }

  if (error) {
    return (
      <div className="profile-container">
        <div className="profile-error">
          <h2>Error Loading Profile</h2>
          <p>{error}</p>
        </div>
      </div>
    );
  }

  if (!userDetails) {
    return (
      <div className="profile-container">
        <div className="profile-error">
          <h2>Not Authenticated</h2>
          <p>Please login to view your profile</p>
        </div>
      </div>
    );
  }

  return (
    <div className="profile-container">
      <div className="profile-card">
        <h1>User Profile</h1>
        
        <div className="profile-info">
          <div className="profile-section">
            <h2>Account Information</h2>
            <div className="profile-field">
              <span className="field-label">Email:</span>
              <span className="field-value">{userDetails.email}</span>
            </div>
            {userDetails.name && (
              <div className="profile-field">
                <span className="field-label">Name:</span>
                <span className="field-value">{userDetails.name}</span>
              </div>
            )}
            <div className="profile-field">
              <span className="field-label">Account ID:</span>
              <span className="field-value">{userDetails.id}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Profile;