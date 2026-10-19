ALTER TABLE hospitals ADD COLUMN code TEXT;
ALTER TABLE departments ADD COLUMN min_day INTEGER DEFAULT 2;
ALTER TABLE departments ADD COLUMN min_night INTEGER DEFAULT 1;
CREATE TABLE IF NOT EXISTS audit_log(id TEXT PRIMARY KEY,hospital_id TEXT,department_id TEXT,user_id TEXT,user_name TEXT,action TEXT,detail TEXT,created_at INTEGER);
CREATE UNIQUE INDEX IF NOT EXISTS hosp_code ON hospitals(code);
UPDATE hospitals SET code=upper(substr(hex(randomblob(3)),1,6)) WHERE code IS NULL;

CREATE TABLE IF NOT EXISTS login_attempts(k TEXT PRIMARY KEY,fails INTEGER,locked_until INTEGER,updated_at INTEGER);
ALTER TABLE users ADD COLUMN token_version INTEGER DEFAULT 1;
