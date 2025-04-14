'use client';

import React, { useState } from 'react';
import { getBackendUrl } from '../utils/env';
import Link from 'next/link';

export default function Home() {
  const [healthStatus, setHealthStatus] = useState<null | any>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<null | string>(null);

  const checkBackendHealth = async () => {
    setLoading(true);
    setError(null);
    try {
      // Get backend URL from our utility
      const backendUrl = getBackendUrl();
      if (!backendUrl) {
        throw new Error('Backend URL not configured. Please check your environment settings.');
      }

      const response = await fetch(`${backendUrl}/api/health`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
        },
      });
      
      if (!response.ok) {
        throw new Error(`Error: ${response.status} ${response.statusText}`);
      }
      
      const data = await response.json();
      setHealthStatus(data);
    } catch (err) {
      console.error('Error checking backend health:', err);
      setError(err instanceof Error ? err.message : 'Unknown error occurred');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="flex flex-col items-center justify-center min-h-screen p-4">
      <header className="mb-8">
        <h1 className="text-4xl font-bold text-center">Welcome to Wedge Golf</h1>
        <p className="text-xl text-center mt-2">Your golf companion</p>
      </header>
      
      <main className="flex flex-col items-center max-w-4xl w-full">
        <div className="bg-white shadow-md rounded-lg p-6 w-full mb-6">
          <h2 className="text-2xl font-semibold mb-4">Getting Started</h2>
          <p className="mb-4">
            This is the frontend application for the Wedge Golf project.
          </p>
          <div className="flex justify-center space-x-4 mt-6">
            <Link href="/customers" className="bg-blue-600 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded">
              Manage Customers
            </Link>
            <button className="bg-green-600 hover:bg-green-700 text-white font-bold py-2 px-4 rounded">
              Explore Features
            </button>
          </div>
        </div>

        <div className="bg-white shadow-md rounded-lg p-6 w-full">
          <h2 className="text-2xl font-semibold mb-4">Backend Health Check</h2>
          <p className="mb-4">
            Test the connection to the backend API by checking its health endpoint.
          </p>
          <div className="flex justify-center mt-4">
            <button 
              onClick={checkBackendHealth}
              disabled={loading}
              className={`${loading ? 'bg-gray-400' : 'bg-green-600 hover:bg-green-700'} text-white font-bold py-2 px-4 rounded flex items-center`}
            >
              {loading ? 'Checking...' : 'Check Backend Health'}
            </button>
          </div>
          
          {error && (
            <div className="mt-4 p-3 bg-red-100 border border-red-400 text-red-700 rounded">
              <p className="font-bold">Error</p>
              <p>{error}</p>
            </div>
          )}
          
          {healthStatus && !error && (
            <div className="mt-4 p-4 bg-gray-50 rounded-md">
              <h3 className="font-semibold text-lg mb-2">Health Status:</h3>
              <div className="overflow-x-auto">
                <pre className="bg-gray-100 p-3 rounded text-sm">
                  {JSON.stringify(healthStatus, null, 2)}
                </pre>
              </div>
            </div>
          )}
        </div>
      </main>
      
      <footer className="mt-8 text-center text-sm text-gray-600">
        <p>Wedge Golf - {new Date().getFullYear()}</p>
      </footer>
    </div>
  );
} 