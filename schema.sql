CREATE TABLE IF NOT EXISTS app(
	name text,
	ip_suffix text,

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
