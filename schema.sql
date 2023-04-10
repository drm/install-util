CREATE TABLE app(
	name text,
	ip_suffix text,

	primary key(name)
);

CREATE TABLE env(
    name text,
    ip_prefix text,

    primary key(name)
);

CREATE TABLE server(
    name text,

    primary key(name)
);


CREATE TABLE deployment(
	app_name text,
	env_name text,
	server_name text,

	foreign key(app_name) references app(name),
	foreign key(env_name) references env(name),
	foreign key(server_name) references server(name),

	primary key(app_name, env_name, server_name)
);
