DO $$ BEGIN
 IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='inspector') THEN
  CREATE ROLE inspector LOGIN PASSWORD 'NetoSQL2025';
 ELSE
  ALTER ROLE inspector WITH LOGIN PASSWORD 'NetoSQL2025';
 END IF;
END $$;
GRANT ALL PRIVILEGES ON SCHEMA sakharov_food TO inspector;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA sakharov_food TO inspector;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA sakharov_food TO inspector;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA sakharov_food TO inspector;
GRANT USAGE ON SCHEMA exts TO inspector;
GRANT USAGE ON SCHEMA information_schema TO inspector;
GRANT USAGE ON SCHEMA pg_catalog TO inspector;
ALTER ROLE inspector SET search_path TO sakharov_food, public;
