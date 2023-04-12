#!/bin/bash
set -euo pipefail
ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKIP_PREREQ_CHECK=1 source $ROOT/rc.sh

if [ "${DEBUG:-0}" -gt 0 ]; then
	set -x
	export PS4='+ ${FUNCNAME[0]:+${FUNCNAME[0]}():}line ${LINENO}: '
fi

file="$1"
target="$2"

if [ -f "$2" ]; then
	echo "File $2 exists. Remove it first if you wish to overwrite."
	exit 1
fi
if ! [ -f "$1" ]; then
	echo "File $1 does not exist";
	exit 2
fi

gen_sql() {
	echo "PRAGMA foreign_keys = ON;"
	cat $ROOT/schema.sql;

	jq -r '(.deployments | keys)[]' < $file | while read app_name; do
		echo "INSERT INTO app(name) VALUES('$app_name');";
		if [ "$(jq -r '(.deployments["'$app_name'"])' < $file)" != "*" ]; then
			jq -r '(.deployments["'$app_name'"])|keys[]' < $file | while read env_name; do
				echo "INSERT INTO env(name) VALUES('$env_name') ON CONFLICT DO NOTHING;"
				server_name="$(jq -r '(.deployments["'$app_name'"]["'$env_name'"])' < $file)"
				echo "INSERT INTO server(name) VALUES('${server_name}') ON CONFLICT DO NOTHING;";
				echo "INSERT INTO deployment(app_name, env_name, server_name) VALUES('$app_name', '$env_name', '$server_name');"
			done;
		fi
	done;
	jq -r '(.networks | keys)[]' < $file | while read env_name; do
		ip_prefix="$(jq -r '(.networks["'$env_name'"])' < $file)"
		echo "UPDATE env SET ip_prefix='$ip_prefix' WHERE name='$env_name';"
	done;
	jq -r '(.suffix | keys)[]' < $file | while read app_name; do
		ip_suffix="$(jq -r '(.suffix["'$app_name'"])' < $file)"
		echo "UPDATE app SET ip_suffix='$ip_suffix' WHERE name='$app_name';"
	done;

	awk '{
		if(/Host /) { host=$2 }
		if(/HostName /) { hosts[host]=$2; }
		if(/User /) { users[host]=$2; }
	}
	END {
		for (key in hosts) {
			printf "UPDATE server SET ssh=\"%s@%s\" WHERE name=\"%s\";\n", users[key], hosts[key], key
			printf "UPDATE server SET hostname=\"%s\" WHERE name=\"%s\";\n", hosts[key], key
		}
	}' < $ROOT/../ssh/config
}

gen_sql | $SQLITE -echo -bail $target

