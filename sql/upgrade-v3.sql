-- upgrade 3.0
DELETE FROM ssh_key WHERE server_name NOT IN(SELECT name FROM server);
DELETE FROM ssh_key WHERE key='';
ALTER TABLE ssh_key RENAME TO ssh_key_org;
CREATE TABLE ssh_key(name text, type text, key text, PRIMARY KEY(name), UNIQUE(key));
INSERT INTO ssh_key(name, type, key) SELECT DISTINCT comment, type, key FROM ssh_key_org;
CREATE TABLE server__ssh_key(server_name text references server(name) ON DELETE CASCADE, ssh_key_name text references ssh_key(name) ON DELETE CASCADE, primary key(ssh_key_name, server_name));
INSERT INTO server__ssh_key(ssh_key_name, server_name) select distinct comment, server_name from ssh_key_org;

ALTER TABLE server DROP COLUMN hostname;
