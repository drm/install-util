CREATE TABLE _deployment(
    app_name text,
    env_name text,
    server_name text,
    node_id int not null default 1 CHECK (node_id >= 1),

    foreign key(app_name) references app(name),
    foreign key(env_name) references env(name),
    foreign key(server_name) references server(name),

    primary key(app_name, env_name, node_id)
);
INSERT INTO _deployment(app_name, env_name, server_name) select app_name, env_name, server_name FROM deployment;
DROP VIEW IF EXISTS vw_app;
DROP TABLE deployment;
ALTER TABLE _deployment RENAME TO deployment;
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
