/**
 * Customer data model
 */
export interface Customer {
  id: string;
  first_name: string;
  last_name: string;
  email?: string;
  created_at?: string;
  updated_at?: string;
}

/**
 * Health check response type
 */
export interface HealthStatus {
  status: string;
  timestamp: string;
  version?: string;
  environment: string;
  system_info: {
    python_version: string;
    platform: string;
    cpu_usage: number;
    memory_usage: number;
    disk_usage: number;
    [key: string]: any;
  };
}

/**
 * API Error response
 */
export interface ApiError {
  detail: string;
  status_code?: number;
  [key: string]: any;
} 