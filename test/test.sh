#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
trap 'rm -rf '"$ROOT"'/scripts' EXIT;
cd "$ROOT";
rm -f "$ROOT/config.db"
touch "$ROOT/config.db"
# shellcheck disable=SC1091
source "$ROOT/../rc.sh"

_query < "$ROOT/../schema.sql"

for app in "$ROOT"/apps/*; do
	_query <<< "INSERT INTO app(name) VALUES('$(basename "$app")')";
done;

_query <<-EOF
	INSERT INTO env(name) VALUES('local'), ('remote');
	INSERT INTO server(name) VALUES('local_server'), ('remote_server');
	UPDATE server SET ssh='$(whoami)@localhost' WHERE server.name='remote_server';
 	INSERT INTO
 		deployment(app_name, server_name, env_name)
 	SELECT
 		app.name, server.name, env.name
	FROM
		app
			CROSS JOIN server
			INNER JOIN env ON server.name=env.name || '_server'
	;
EOF

for f in "$ROOT"/apps/*/expect*.txt; do
	filename="$(basename "$f" .txt)"
	ENV="${filename/expect./}"
	app="$(basename "$(dirname "$f")")";
	output=$(ENV="$ENV" install "$app" 2>&1)
	if ! diff <(echo "$output") "$f"; then
		echo "Failure!"
		exit 2;
	fi
done;

echo "All good!"
