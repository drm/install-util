
## Called at the end of this file to initialize the environment
_prelude() {
	[ "${DEBUG:-0}" -gt 2 ] && set -x

	if [ "${ROOT:-}" == "" ]; then
		echo "Missing ROOT. See README.md for details."
		exit;
	fi
	if [ -f "$ROOT/project.sh" ]; then
		source $ROOT/project.sh
	fi
	export DEFAULT_ENV="${DEFAULT_ENV:-development}"
	export PS1="$NAMESPACE [\$ENV] "
	export PS4="+ \033[0;37m[debug]\033[0m"' $(date +"%Y-%m-%dT%H:%M:%S.%N") ${BASH_SOURCE:-1}:${LINENO:-} ${FUNCNAME[0]:-main}() - '
	export DEBUG="${DEBUG:-0}"
	export ENV="${ENV:-$DEFAULT_ENV}"
	export HISTFILE="$ROOT/shell_history"
	export FORCE="${FORCE:-}"
	export CONFIG_DB="$ROOT/config.db"
	export PAGER="${PAGER:-$(which less)}"
	export INSTALL_SCRIPT_NAMES="${INSTALL_SCRIPT_NAMES:-install status}"
	export BASH="${BASH:-/bin/bash}"

	# In the future, for portability we might rather configure a command line to use mysql, psql or something else
	export SQLITE="$(which sqlite3)"
	export SSH="$(which ssh)"
	export RSYNC="$(which rsync)"
	export SHOWSOURCE="$(which batcat)"
	if [ "$SHOWSOURCE" == "" ]; then
		export SHOWSOURCE="cat";
	fi

	if [ "${SKIP_PREREQ_CHECK:-}" == "" ]; then
		_check_prereq
	fi

	if [ "${INTERACTIVE:-}" == "1" ]; then
		cat "$ROOT/resources/doc/header.md";
	fi
}

## Helper to report an error and exit the shell.
_fail() {
	echo -e "FATAL: $1" >&2
	exit 1
}

## Helper to assert non-empty vars
_assert_not_empty() {
	[ "$1" != "" ] || _fail "$2"
}

## Check the prerequisites for using this script
_check_prereq() {
	[ "$SQLITE" == "" ] && _fail "'sqlite3' is not found in the PATH..."
	[ "$SSH" == "" ] && _fail "'ssh' is not found in the PATH..."
	[ "$RSYNC" == "" ] && _fail "'rsync' is not found in the PATH..."
	! [ -f "$CONFIG_DB" ] && _fail "$CONFIG_DB is not a file..."
	return 0
}

_query() {
	if [ "$DEBUG" -gt 0 ]; then
		tee /dev/stderr
	else
		cat -
	fi | $SQLITE -init /dev/null -bail "$@" "$CONFIG_DB"
}

_confirm() {
	local response;
	read -p "$1" response < /dev/tty
	if [ "$response" == "y" ] || [ "$response" == "Y" ]; then
		return 0
	else
		return 1;
	fi;
}

_cfg_get_ip() {
	local env="$1"
	local app="$2"
	_query <<<"SELECT ip FROM vw_app WHERE app_name='$app' AND env_name='$env'"
}

## Get the ssh name for the specified app and environment
_cfg_get_ssh() {
	_query <<<"SELECT ssh FROM server INNER JOIN deployment ON server_name=server.name WHERE app_name='${1}' AND env_name='${2}'"
}

## Get the ssh prefix for the specified app and environment. Will return empty string
## if no ssh is configured
_cfg_get_ssh_prefix() {
	local ssh; ssh=$(_cfg_get_ssh "$1" "$2");
	if [ "$ssh" != "" ]; then
		shift 2;
		echo "$SSH" -F "$ROOT/ssh/config $@ $ssh "
	fi
}

## Get the shell for the specified deployment; i.e. prefix /bin/bash
## with the ssh prefix, if any.
_cfg_get_shell() {
	local prefix; prefix="$(_cfg_get_ssh_prefix "$1" "$2")"
	if [ "$prefix" == "" ]; then
		echo "$BASH"
	else
		echo "${prefix}/bin/bash"
	fi
}

## Wrapper for 'ssh' to use the project ssh config.
ssh() {
	"$SSH" -F "$ROOT/ssh/config" $@
}

## Wrapper for 'rsync' to use the project ssh config.
rsync() {
	"$RSYNC" -e "$SSH -F $ROOT/ssh/config" $@
}

## Increase debug level, or turn debugging off.
debug() {
	if [ "${1:-}" == "off" ]; then
		DEBUG="0"
	else
		DEBUG="$(( "$DEBUG" + 1 ))"
	fi
	_prelude
	echo "Set debugging level to $DEBUG"
}

## Change current working environment.
env() {
	ENV="$1"
	_prelude
}

## Dump current variables.
vars() {
	"$(which env)";
}

## Perform deployment for all specified arguments.
install() {
	for app in "$@"; do
		if [ "$(_query <<<"SELECT COUNT(1) FROM app WHERE name='$app'")" != "1" ]; then
			_fail "Invalid app name $app. Valid app names are: $(_query <<< "SELECT GROUP_CONCAT(DISTINCT app_name) FROM deployment")"
		fi
		if [ "$(_query <<<"SELECT COUNT(1) FROM deployment WHERE app_name='$app' AND env_name='$ENV'")" != "1" ]; then
			_fail "No deployment for $app on $ENV. Valid deployments for $app are: $(_query <<< "SELECT GROUP_CONCAT(env_name, ', ') FROM deployment WHERE app_name='$app'")"
		fi
		if ! [ -f "$ROOT/apps/$app/install.sh" ]; then
			_fail "Missing installation script $ROOT/apps/$app/install.sh"
		fi
	done

	for app in "$@"; do
		local build_vars="ENV NAMESPACE VERSION artifacts resources app server"
		local ssh; ssh="$(_cfg_get_ssh $app $ENV)"
		local shell; shell="$(_cfg_get_shell $app $ENV)"

		source $ROOT/vars.sh

		for subdir in resources artifacts; do
			local $subdir="$ROOT/apps/$app/$subdir/"
		done
		artifacts="$artifacts/$ENV"
		rm -rf $artifacts;
		mkdir -p $artifacts
		local build_script="$ROOT/apps/$app/build.sh"
		if [ -f "$build_script" ]; then
			[ "$DEBUG" -eq 0 ] || echo "Calling build script: $build_script"
			source "$build_script"
		fi

		local remote_wd;
		remote_wd="$($shell <<< 'mkdir -p scripts && cd scripts && pwd')"

		for script_name in $INSTALL_SCRIPT_NAMES; do
			local script="$artifacts/$script_name.sh"
			[ "$DEBUG" -eq 0 ] || echo "Building script: $script"

			if [ -f "$ROOT/apps/$app/$script_name.sh" ]; then
				# subshell to scope 'artifacts' and 'resources' variables remotely different from locally.
				(
					for subdir in resources artifacts; do
						local $subdir="$remote_wd/$app/$ENV/$subdir"
					done
					cat \
						> $script \
						<(cat \
							<(cat <<-EOF
								#!/usr/bin/env bash
								set -euo pipefail
								if [ "$DEBUG" -gt 0 ]; then
									set -x
								fi
							EOF
							) \
							<(for var in $build_vars; do echo $var='"'${!var:-}'"'; done ) \
							$ROOT/apps/$app/$script_name.sh
						)
					chmod +x $script;
				)
			fi
		done

		if [ "$DEBUG" -ge 1 ]; then
			PS3="How do you wish to proceed? "
			select x in "Show script" "Show diff" "Continue install [on $shell]" "Exit"; do
				echo $x;
				case "$REPLY" in
					1)
						for script_name in $INSTALL_SCRIPT_NAMES; do
							if [ -f "$artifacts/$script_name.sh" ]; then
								$SHOWSOURCE $artifacts/$script_name.sh;
							fi
						done;
					;;
					2)
						for subdir in resources artifacts; do
							local local_dir="${!subdir}"
							local remote_dir="$remote_wd/$app/$ENV/$subdir"

							if [ -d "$local_dir" ]; then
								# subshell to keep cwd
								(
									cd $local_dir;
									find ./ -type f | while read f; do
										f="${f:2}"
										diff -s <($shell <<< "cat $remote_dir/$f") $local_dir/$f || true
									done;
								)
							fi;
						done
					;;
					3)
						break
					;;
					4) exit; ;;
					*) echo "Invalid selection. Please retry."; ;;
				esac
				# resets the prompt
				REPLY=
			done;
			echo "$REPLY";
			if [ "$REPLY" == "" ]; then
				exit;
			fi
		fi;

		for subdir in resources artifacts; do
			local local_dir="${!subdir}"
			local remote_dir="$remote_wd/$app/$ENV/$subdir"

			if [ -d "$local_dir" ] && [ "$(find $local_dir -type f | wc -l)" -gt 0 ]; then
				rsync_opts=""
				if [ "$DEBUG" -ge 2 ]; then
					rsync_opts="$rsync_opts -nv"
				fi
				if [ "$DEBUG" -lt 2 ]; then
					if [ "$DEBUG" -lt 1 ]; then
						$shell <<<"mkdir -p \"$remote_dir\""
					else
						$shell <<<"mkdir -pv \"$remote_dir\""
					fi
				fi
				if [ "$ssh" != "" ]; then
					rsync -prL $rsync_opts "$local_dir/" "$ssh:$remote_dir/"
				else
					rsync -prL $rsync_opts "$local_dir/" "$remote_dir/"
				fi
			fi
		done;
		if [ "$DEBUG" -lt 2 ]; then
			for script_name in $INSTALL_SCRIPT_NAMES; do
				if [ -f "$artifacts/$script_name.sh" ]; then
					(
						for subdir in resources artifacts; do
							local $subdir="$remote_wd/$app/$ENV/$subdir"
						done

						$shell <<< "$artifacts/$script_name.sh";
					)
				fi
			done;
		else
			echo "Skipping install, DEBUG is set to ${DEBUG}, and script will not run with DEBUG at a value higher than 1" ;
		fi
	done;
}

## Show help.
help() {
	$PAGER $ROOT/README.md
}

## List all apps.
apps() {
	_query -box <<<"SELECT * FROM app";
}

## List all deployments for the specified app.
deployments() {
	local where="true";
	if [ "${1:-}" != "" ]; then
		where="app_name='$1'"
	fi
	_query -box <<<"SELECT app_name, env_name, server_name, ssh FROM deployment INNER JOIN server ON server_name=server.name WHERE $where";
}

## Refresh all server's ip's
refresh_dns() {
	_query <<<"SELECT name, hostname FROM server WHERE hostname IS NOT NULL" | while IFS="|" read name hostname; do
		echo "UPDATE server SET ip='$(dig +short $hostname | tail -1)' WHERE name='$name';"
	done | _query;
}

## Verify configurations
verify() {
	local app;
	local d;
	_query <<< "SELECT ssh FROM server WHERE ssh IS NOT NULL" | while read s; do
		ssh -n $s echo "Hello from $s";
	done;
	for d in $ROOT/apps/*; do
		app="$(basename "$d")"
		echo "App '${app}' is configured in db: $(_query <<<"SELECT CASE WHEN COUNT(1) > 0 THEN 'YES' ELSE 'NO' END FROM app WHERE name='${app}'")";
	done
	_query <<< "SELECT app_name, env_name FROM deployment" | while IFS="|" read app_name env_name; do
		shell="$(_cfg_get_shell $app_name $env_name)"
		$shell <<<"echo 'Hello from $shell'";
		DEBUG=9 install $app_name $env_name
	done;
}

## Download SSH keys from each server into local database.
fetch_keys() {
	_query <<< "SELECT name, ssh FROM server WHERE ssh IS NOT NULL" | while IFS="|" read server_name ssh; do
		echo "BEGIN;"
		echo "DELETE FROM ssh_key WHERE server_name='$server_name';";
		ssh "$ssh" /bin/bash <<< "cat ~/.ssh/authorized_keys" | sed 's/#.*//g' | awk NF | sort | while IFS=" " read type key comment; do
			cat <<-EOF
				INSERT INTO
					ssh_key(server_name, type, key, comment)
				VALUES
					('$server_name', '$type', '$key', '$comment')
				ON CONFLICT DO NOTHING;
			EOF
		done;
		echo "COMMIT;"
		echo "SELECT '[$server_name] OK';";
	done | _query;
}

## Upload SSH keys from each server into management database. Note that this
## doesn't provide for any safety net regarding throwing away your own
## key, except for a manual confirmation of the changes.
push_keys() {
	local where="ssh IS NOT NULL";
	if [ "${1:-}" != "" ]; then
		where="name='$1'";
	fi
	local new;
	local diff;
	_query <<< "SELECT name, ssh FROM server WHERE $where" | while IFS="|" read server_name ssh; do
		new="$(mktemp)"
		trap "rm -f '$new'" EXIT
		_query <<< "SELECT type || ' ' || key || ' ' || comment FROM ssh_key WHERE server_name='$server_name'" | sort > "$new"
		diff="$(diff <(ssh -n "$ssh" cat \~/.ssh/authorized_keys | sort) "$new" || true)"
		if [ "$diff" != "" ]; then
			echo "$diff";
			if _confirm "[$server_name] Continue applying changes? [y/N] "; then
				scp "$new" "$ssh":.ssh/authorized_keys
			fi
		else
			echo "[$server_name] No changes"
		fi
	done
}


## * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
_prelude;
