## Verify configurations
ssh_verify() {
	local app;
	local d;
	_query <<< "SELECT ssh FROM server WHERE ssh IS NOT NULL" | while read -r s; do
		ssh -n "$s" echo "Hello from $s";
	done;
	for d in "$ROOT/apps/"*; do
		app="$(basename "$d")"
		echo "App '${app}' is configured in db: $(_query <<<"SELECT CASE WHEN COUNT(1) > 0 THEN 'YES' ELSE 'NO' END FROM app WHERE name='${app}'")";
	done
	_query <<< "SELECT app_name, env_name FROM deployment" | while IFS="|" read -r app_name env_name; do
		shell="$(_cfg_get_shell "$app_name" "$env_name")"
		$shell <<<"echo 'Hello from $shell'";
		DEBUG=9 install "$app_name" "$env_name"
	done;
}

## Download SSH keys from each server into local database.
ssh_fetch_keys() {
	local where
	if [ "${1:-}" != "" ]; then
		where="name='$1'";
	else
		where="name <> 'local'"
	fi
	_query <<< "SELECT name FROM server WHERE $where" | while IFS="|" read -r server_name ssh; do
		echo "BEGIN;"
		echo "DELETE FROM server__ssh_key WHERE server_name='$server_name';";
		ssh "$server_name" -n cat .ssh/authorized_keys | sed 's/#.*//g' | awk NF | sort | while IFS=" " read -r type key comment; do
			if ! [ "$comment" ]; then
				_fail "Missing comment for key: $type $key"
			fi

			if [ "$key" ]; then
				local key_name="$(_query <<< "SELECT name FROM ssh_key WHERE key='$key'")"
				if ! [ "$key_name" ]; then
					if [ "$(_query <<< "SELECT key FROM ssh_key WHERE name='$comment'")" ]; then
						echo "CONFLICT: Key for name $comment exists, but the keys don't match" >&2
					else
						cat <<-EOF
							INSERT INTO
								ssh_key(type, key, name)
							VALUES
								('$type', '$key', '$comment')
							ON CONFLICT DO NOTHING;
						EOF
					fi
				elif [ "$key_name" != "$comment" ]; then
					echo "WARNING: Key for $comment is known as $key_name. Please make sure this is correct." >&2
				fi
				cat <<-EOF
					INSERT INTO
						server__ssh_key(server_name, ssh_key_name)
					VALUES
						('$server_name', '$key_name')
					ON CONFLICT DO NOTHING;
				EOF
			fi
		done;
		echo "COMMIT;"
		echo "SELECT '[$server_name] OK';";
	done | _query;
}

## Upload SSH keys to each server from management database. Note that this
## doesn't provide for any safety net regarding throwing away your own
## key, except for a manual confirmation of the changes.
ssh_push_keys() {
	local where
	if [ "${1:-}" != "" ]; then
		where="name='$1'";
	else
		where="name <> 'local'"
	fi
	local new;
	local diff;
	_query <<< "SELECT name FROM server WHERE $where" | while IFS="|" read -r server_name; do
		echo "[$server_name] checking difference..."
		new="$(mktemp)"
		_query <<< "SELECT type || ' ' || key || ' ' || ssh_key.name FROM ssh_key INNER JOIN server__ssh_key ON ssh_key_name=ssh_key.name WHERE server_name='$server_name'" \
			| sort \
			> "$new"
		if ! existing="$(ssh -n "$server_name" cat .ssh/authorized_keys)"; then
			echo "Failure getting ssh keys from '$server_name'" >&2
			continue;
		fi
		if [ "$(wc -l "$new" | awk '{print $1}')" -eq 0 ]; then
			echo "[$server_name] ERROR: Refusing to push empty key file. There are no keys in the database!" >&2
			return 1
		else
			diff="$(diff <(echo "$existing" | sort) "$new" || true)"
			if [ "$diff" != "" ]; then
				echo "$diff";
				if _confirm "[$server_name] Continue applying changes? [y/N] "; then
					scp -F "ssh/config" "$new" "$server_name":.ssh/authorized_keys
				fi
			else
				echo "[$server_name] No changes"
			fi
		fi
		rm -f "$new"
	done
}

ssh_import_key() {
	IFS=" " read -r type key comment
	local exists=""
	local existing_name; existing_name="$(_query <<< "SELECT name FROM ssh_key WHERE name='$comment'")"
	local existing_key; existing_key="$(_query <<< "SELECT name FROM ssh_key WHERE key='$key'")"

	if [ "$existing_key" ]; then
		echo "Key already exists as '$existing_key'" >&2
		exists="1"
	fi
	if [ "$existing_name" ]; then
		echo "Key name '$existing_name' already in use" >&2
		exists="1"
	fi

	if ! [ "$exists" ]; then
		_query <<-EOF
			INSERT INTO
				ssh_key(type, key, name)
			VALUES
				('$type', '$key', '$comment')
		EOF
	fi
}

ssh_close_sockets() {
	for f in "$(cd -P "$ROOT/ssh/sockets" && pwd)"/*; do
		if test -S $f; then
			echo "Closing existing ControlPath: $f"
			ssh -O exit -o ControlPath=$f true || true
		fi
	done;
}

ssh_close_agent() {
	ssh-agent -k
	ssh_close_sockets
}

ssh_agent() {
	ssh_close_sockets
	eval `ssh-agent`
	ssh-add
	trap ssh_close_agent EXIT
}

