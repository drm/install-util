#!/usr/bin/env bash

## Runs tests
##
## Usage:
## 	./test.sh
##

# These are generated for local installs.
trap 'rm -rf '"$ROOT"'/scripts' EXIT;

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT";
rm -f "$ROOT/config.db" && touch "$ROOT/config.db"
# shellcheck disable=SC1091
source "$ROOT/../rc.sh"

init-db() {
	_query < "$ROOT/../schema.sql"

	for app in "$ROOT"/apps/*; do
		if [ -f "$app/install.sh" ]; then
			_query <<< "INSERT INTO app(name) VALUES('$(basename "$app")')";
		fi
	done;

	_query <<-EOF
		INSERT INTO env(name) VALUES('local'), ('remote');
		INSERT INTO server(name) VALUES('local_server'), ('remote_server');
		UPDATE server SET ssh='install-util-remote' WHERE server.name='remote_server';
		INSERT INTO
			deployment(app_name, server_name, env_name)
		SELECT
			app.name, server.name, env.name
		FROM
			app
				CROSS JOIN server
				INNER JOIN env ON server.name=env.name || '_server'
		WHERE true
		ON CONFLICT DO NOTHING
		;
	EOF
}

generate-ssh-env() {
	trap 'docker rm -f install-util-remote >/dev/null 2>&1' EXIT
	./install.sh local remote-docker
	  
	docker cp "install-util-remote:/root/.ssh/id_rsa" "$ROOT/ssh/id_rsa"
	rm -f "$ROOT/ssh/known_hosts"
	cat <<-EOF > "$ROOT"/ssh/config
	Host install-util-remote
	  HostName 127.0.0.1
	  Port 22220
	  User root
	  IdentityFile $ROOT/ssh/id_rsa
	  UserKnownHostsFile $ROOT/ssh/known_hosts
	EOF
	
	# Just creating/testing the first connection to accept the host key.
	ssh -F "$ROOT/ssh/config" -o StrictHostKeyChecking=accept-new install-util-remote true 
}

run-tests() {
	pwd
#	./shell.sh <<< "apps"
#	./shell.sh <<< "deployments"

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
}

init-db
generate-ssh-env
run-tests

echo "All good!"
