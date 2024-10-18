PRAGMA foreign_keys=ON; 

CREATE TABLE IF NOT EXISTS app(
	name text,
	ip_suffix text,
	ordinal int,

	primary key(name)

);

CREATE TABLE IF NOT EXISTS env(
	name text,
	ip_prefix text,

	primary key(name)
);

CREATE TABLE IF NOT EXISTS server(
	name text,
	ssh text,
	hostname text,
	ip text,

	primary key(name)
);

CREATE TABLE IF NOT EXISTS ssh_key(
	server_name text,
	type text,
	key text,
	comment text,

	primary key(server_name, key)
);

CREATE TABLE IF NOT EXISTS deployment(
	app_name text,
	env_name text,
	server_name text,

	foreign key(app_name) references app(name),
	foreign key(env_name) references env(name),
	foreign key(server_name) references server(name),

	primary key(app_name, env_name)
);

DROP VIEW IF EXISTS vw_app;
CREATE VIEW vw_app AS
SELECT
	app_name,
	server_name,
	env_name,
   (env.ip_prefix || '.' || app.ip_suffix) ip
FROM
	deployment
	    INNER JOIN app ON app_name=app.name
	    INNER JOIN server ON server_name=server.name
	    INNER JOIN env ON env_name=env.name
;

-- upgrade 3.0
DELETE FROM ssh_key WHERE server_name NOT IN(SELECT name FROM server);
DELETE FROM ssh_key WHERE key='';
ALTER TABLE ssh_key RENAME TO ssh_key_org;
CREATE TABLE ssh_key(name text, type text, key text, PRIMARY KEY(name), UNIQUE(key));
INSERT INTO ssh_key(name, type, key) SELECT DISTINCT comment, type, key FROM ssh_key_org;
CREATE TABLE server__ssh_key(server_name text references server(name) ON DELETE CASCADE, ssh_key_name text references ssh_key(name) ON DELETE CASCADE, primary key(ssh_key_name, server_name));
INSERT INTO server__ssh_key(ssh_key_name, server_name) select distinct comment, server_name from ssh_key_org;
