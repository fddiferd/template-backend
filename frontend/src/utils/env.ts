/**
 * Environment utility functions for handling backend URLs and environment settings
 */

/**
 * Get the backend URL from environment variables with fallback to local development
 */
export const getBackendUrl = (): string => {
  // First check for environment variable
  const envUrl = process.env.NEXT_PUBLIC_BACKEND_URL;
  if (envUrl) return envUrl;

  // For local development fallback
  if (typeof window !== 'undefined' && window.location.hostname === 'localhost') {
    return 'http://localhost:8080';
  }

  // If everything fails, return empty string (will be caught by error handling)
  return '';
};

/**
 * Get the current environment (development, staging, production)
 */
export const getEnvironment = (): string => {
  return process.env.NODE_ENV || 'development';
};

/**
 * Check if we're running in development mode
 */
export const isDevelopment = (): boolean => {
  return getEnvironment() === 'development';
};

export default {
  getBackendUrl,
  getEnvironment,
  isDevelopment,
}; 