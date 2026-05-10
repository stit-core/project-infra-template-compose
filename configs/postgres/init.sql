-- Runs once on volume init. POSTGRES_USER/DB created by entrypoint
-- before this; here we only add extensions backend tends to want.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
