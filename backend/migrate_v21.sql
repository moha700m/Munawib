ALTER TABLE hospitals ADD COLUMN code TEXT;
ALTER TABLE departments ADD COLUMN min_day INTEGER DEFAULT 2;
ALTER TABLE departments ADD COLUMN min_night INTEGER DEFAULT 1;
CREATE TABLE IF NOT EXISTS audit_log(id TEXT PRIMARY KEY,hospital_id TEXT,department_id TEXT,user_id TEXT,user_name TEXT,action TEXT,detail TEXT,created_at INTEGER);
CREATE UNIQUE INDEX IF NOT EXISTS hosp_code ON hospitals(code);
UPDATE hospitals SET code=upper(substr(hex(randomblob(3)),1,6)) WHERE code IS NULL;
