'use client';

import React, { useState, useEffect } from 'react';
import { getBackendUrl } from '../../utils/env';
import Link from 'next/link';

// Customer type definition
interface Customer {
  id: string;
  first_name: string;
  last_name: string;
  email?: string;
  created_at?: string;
}

export default function CustomersPage() {
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');
  const [email, setEmail] = useState('');
  const [editMode, setEditMode] = useState(false);
  const [currentCustomerId, setCurrentCustomerId] = useState<string | null>(null);

  const fetchCustomers = async () => {
    setLoading(true);
    setError(null);
    try {
      const backendUrl = getBackendUrl();
      if (!backendUrl) {
        throw new Error('Backend URL not configured');
      }

      const response = await fetch(`${backendUrl}/api/customers/`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
        },
      });

      if (!response.ok) {
        throw new Error(`Error: ${response.status} ${response.statusText}`);
      }

      const data = await response.json();
      setCustomers(data);
    } catch (err) {
      console.error('Error fetching customers:', err);
      setError(err instanceof Error ? err.message : 'Unknown error occurred');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchCustomers();
  }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError(null);

    try {
      const backendUrl = getBackendUrl();
      if (!backendUrl) {
        throw new Error('Backend URL not configured');
      }

      const customerData = {
        first_name: firstName,
        last_name: lastName,
        email: email || undefined, // Only include if not empty
      };

      const url = editMode 
        ? `${backendUrl}/api/customers/${currentCustomerId}`
        : `${backendUrl}/api/customers/`;
      
      const method = editMode ? 'PUT' : 'POST';

      const response = await fetch(url, {
        method,
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(customerData),
      });

      if (!response.ok) {
        throw new Error(`Error: ${response.status} ${response.statusText}`);
      }

      // Clear form and reset state
      setFirstName('');
      setLastName('');
      setEmail('');
      setEditMode(false);
      setCurrentCustomerId(null);

      // Refresh the customer list
      fetchCustomers();
    } catch (err) {
      console.error('Error saving customer:', err);
      setError(err instanceof Error ? err.message : 'Unknown error occurred');
    } finally {
      setLoading(false);
    }
  };

  const startEdit = (customer: Customer) => {
    setFirstName(customer.first_name);
    setLastName(customer.last_name);
    setEmail(customer.email || '');
    setEditMode(true);
    setCurrentCustomerId(customer.id);
  };

  const cancelEdit = () => {
    setFirstName('');
    setLastName('');
    setEmail('');
    setEditMode(false);
    setCurrentCustomerId(null);
  };

  return (
    <div className="flex flex-col items-center min-h-screen p-4">
      <header className="mb-8 w-full max-w-4xl">
        <div className="flex justify-between items-center">
          <h1 className="text-3xl font-bold">Customer Management</h1>
          <Link 
            href="/" 
            className="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded"
          >
            Back to Home
          </Link>
        </div>
      </header>

      <main className="flex flex-col items-center w-full max-w-4xl">
        {/* Customer Form */}
        <div className="bg-white shadow-md rounded-lg p-6 w-full mb-6">
          <h2 className="text-xl font-semibold mb-4">
            {editMode ? 'Edit Customer' : 'Add New Customer'}
          </h2>
          
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700">First Name</label>
              <input
                type="text"
                value={firstName}
                onChange={(e) => setFirstName(e.target.value)}
                required
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring focus:ring-blue-500 focus:ring-opacity-50"
              />
            </div>
            
            <div>
              <label className="block text-sm font-medium text-gray-700">Last Name</label>
              <input
                type="text"
                value={lastName}
                onChange={(e) => setLastName(e.target.value)}
                required
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring focus:ring-blue-500 focus:ring-opacity-50"
              />
            </div>
            
            <div>
              <label className="block text-sm font-medium text-gray-700">Email (Optional)</label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring focus:ring-blue-500 focus:ring-opacity-50"
              />
            </div>
            
            <div className="flex space-x-2">
              <button
                type="submit"
                disabled={loading}
                className={`${loading ? 'bg-gray-400' : 'bg-green-600 hover:bg-green-700'} text-white py-2 px-4 rounded`}
              >
                {loading ? 'Saving...' : editMode ? 'Update Customer' : 'Add Customer'}
              </button>
              
              {editMode && (
                <button
                  type="button"
                  onClick={cancelEdit}
                  className="bg-gray-500 hover:bg-gray-600 text-white py-2 px-4 rounded"
                >
                  Cancel
                </button>
              )}
            </div>
          </form>
          
          {error && (
            <div className="mt-4 p-3 bg-red-100 border border-red-400 text-red-700 rounded">
              {error}
            </div>
          )}
        </div>

        {/* Customer List */}
        <div className="bg-white shadow-md rounded-lg p-6 w-full">
          <h2 className="text-xl font-semibold mb-4">Customer List</h2>
          
          {loading && <p>Loading customers...</p>}
          
          {customers.length === 0 && !loading ? (
            <p className="text-gray-500">No customers found. Add one above!</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="min-w-full divide-y divide-gray-200">
                <thead className="bg-gray-50">
                  <tr>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Name</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Email</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Created</th>
                    <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
                  </tr>
                </thead>
                <tbody className="bg-white divide-y divide-gray-200">
                  {customers.map((customer) => (
                    <tr key={customer.id}>
                      <td className="px-6 py-4 whitespace-nowrap">
                        {customer.first_name} {customer.last_name}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        {customer.email || '-'}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        {customer.created_at 
                          ? new Date(customer.created_at).toLocaleDateString() 
                          : '-'}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-right">
                        <button
                          onClick={() => startEdit(customer)}
                          className="text-blue-600 hover:text-blue-900"
                        >
                          Edit
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </main>
    </div>
  );
} 