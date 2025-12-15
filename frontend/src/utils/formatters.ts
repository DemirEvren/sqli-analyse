// Format date to a readable string
export const formatDate = (dateString: string): string => {
    const date = new Date(dateString);
    return date.toLocaleDateString('en-US', { 
      year: 'numeric', 
      month: 'short', 
      day: 'numeric' 
    });
  };
  
  // Get status color based on project status
  export const getStatusColor = (status: string): string => {
    switch (status) {
      case 'Planning':
        return '#FFC107'; // amber
      case 'In Progress':
        return '#2196F3'; // blue
      case 'Completed':
        return '#4CAF50'; // green
      case 'Abandoned':
        return '#F44336'; // red
      default:
        return '#9E9E9E'; // grey
    }
  };
  
  // Format hardware info for display
  export const formatHardwareInfo = (hardwareInfo: any): string => {
    if (!hardwareInfo) return '';
    
    try {
      if (typeof hardwareInfo === 'string') {
        return hardwareInfo;
      }
      return JSON.stringify(hardwareInfo, null, 2);
    } catch (error) {
      console.error('Error formatting hardware info:', error);
      return String(hardwareInfo);
    }
  };
  
  // Validate URL format
  export const isValidUrl = (url: string): boolean => {
    if (!url) return true; // Empty URLs are considered valid
    
    try {
      new URL(url);
      return true;
    } catch (error) {
      return false;
    }
  };
  
  // Safely parse JSON with error handling
  export const safeJsonParse = (jsonString: string): any | null => {
    if (!jsonString.trim()) return null;
    
    try {
      return JSON.parse(jsonString);
    } catch (error) {
      throw new Error('Invalid JSON format');
    }
  };