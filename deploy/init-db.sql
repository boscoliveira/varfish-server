-- Initialize VarFish database with required extensions
-- This script runs automatically when PostgreSQL container starts for the first time

-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- For fuzzy string matching
CREATE EXTENSION IF NOT EXISTS "btree_gin";  -- For better indexing
CREATE EXTENSION IF NOT EXISTS "btree_gist";  -- For better indexing

-- Set default configuration
ALTER DATABASE varfish SET statement_timeout = '300s';
ALTER DATABASE varfish SET lock_timeout = '10s';
ALTER DATABASE varfish SET idle_in_transaction_session_timeout = '10min';

-- Create additional schemas if needed
CREATE SCHEMA IF NOT EXISTS variants;
CREATE SCHEMA IF NOT EXISTS cases;

-- Grant permissions
GRANT ALL PRIVILEGES ON DATABASE varfish TO varfish;
GRANT ALL ON SCHEMA public TO varfish;
GRANT ALL ON SCHEMA variants TO varfish;
GRANT ALL ON SCHEMA cases TO varfish;

-- Performance tuning for genomics workload
ALTER SYSTEM SET shared_buffers = '2GB';
ALTER SYSTEM SET work_mem = '256MB';
ALTER SYSTEM SET maintenance_work_mem = '512MB';
ALTER SYSTEM SET effective_cache_size = '6GB';
ALTER SYSTEM SET random_page_cost = 1.1;

-- Log slow queries for optimization
ALTER SYSTEM SET log_min_duration_statement = 1000;  -- Log queries slower than 1 second

-- Apply configuration changes
SELECT pg_reload_conf();