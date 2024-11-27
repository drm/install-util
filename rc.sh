export INSTALL_UTIL_ROOT; INSTALL_UTIL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UTIL_ROOT; UTIL_ROOT="${UTIL_ROOT:-"${INSTALL_UTIL_ROOT}/utils"}"
export UTILS; UTILS="${UTILS:-$(cd "$UTIL_ROOT" && for f in *.sh; do echo "${f/.sh/}"; done)}"
export BASH_STARTUP_FLAGS="$-"

if [ "${BASH_VERSINFO:-0}" -lt 5 ]; then
	echo "Needs at least bash version 5" >&2
	if [ "${FORCE:-}" == "" ]; then
		exit 1
	fi
fi

## Filters all var names from a `declare -p` output
__filter_var_names() {
	echo "$1" | sed -E 's/^(typeset|export|declare)( -[^ ]+)? //g' | awk -F "=" '{print $1}' | grep -E '^[A-Za-z0-9_]+$'
}

## Prints a list of vars that have been added in-between a declare call
## Example:
## 	vars_before="$(declare -p)"
##	source somefile
##	vars="$(_add_declared_vars "$vars" "$vars_before" "$(declare -p)")"
_add_declared_vars() {
	local __current_build_vars="$1"
	local __env_before="$2"
	local __env_after="$3"
	local __names_before
	local __names_after

	__names_before="$(__filter_var_names "$__env_before")"
	__names_after="$(__filter_var_names "$__env_after")"

	echo "$__current_build_vars $(comm -1 -3 <(echo "$__names_before" | sort) <(echo "$__names_after" | sort))"
}

_is_debugging_global() {
	[ "${BASH_STARTUP_FLAGS/x}" != "${BASH_STARTUP_FLAGS}" ]
}

debug_on() {
	if ! _is_debugging_global && [ "${DEBUG:-0}" -gt 1 ]; then
		set -x
 	fi		
}

debug_off() {
	if ! _is_debugging_global && [ "${DEBUG:-0}" -lt 3 ]; then
		set +x 
	fi
}

## Called at the end of this file to initialize the environment
_prelude() {
	local vars_before

	debug_on
	if [ "${ROOT:-}" == "" ]; then
		echo "Missing ROOT. See README.md for details."
		exit;
	fi
	export build_vars="DEBUG ENV VERSION resources artifacts"
	if [ -f "$ROOT/project.sh" ]; then
		debug_off
		vars_before="$(declare -p)"
		debug_on

		# shellcheck disable=SC1091
		source "$ROOT/project.sh"

		debug_off
		build_vars="$(_add_declared_vars "$build_vars" "$vars_before" "$(declare -p)")"
		debug_on
	fi
	export PS1="server-config [$NAMESPACE] "
	export PS4="+ \033[0;37m[debug]\033[0m"' $(date +"%Y-%m-%dT%H:%M:%S.%N") ${BASH_SOURCE:-1}:${LINENO:-} ${FUNCNAME[0]:-main}() - '
	export DEBUG="${DEBUG:-0}"
	export HISTFILE="$ROOT/shell_history"
	export FORCE="${FORCE:-}"
	export CONFIG_DB_SRC="$ROOT/config.db.sql"
	if ! [ -f "$CONFIG_DB_SRC" ]; then
		echo "Assuming first run, copying schema.sql to $CONFIG_DB_SRC" >&2
		cp -v $INSTALL_UTIL_ROOT/sql/schema.sql "$CONFIG_DB_SRC"
	fi
	export PAGER="${PAGER:-$(which less)}"
	if [ "${INSTALL_SCRIPT_NAMES:-}" ]; then
		echo "INSTALL_SCRIPT_NAMES is defined, but it was renamed to 'DO' in v3.0" >&2
		exit 9;
	fi
	export DO="${DO:-install status}"
	export BASH="${BASH:-/bin/bash}"

	# In the future, for portability we might rather configure a command line to use mysql, psql or something else
	export SQLITE; SQLITE="$(which sqlite3)"
	export SSH; SSH="$(which ssh)"
	export SSH_CONFIG; SSH_CONFIG="$(if [ -f "$ROOT/ssh/config" ]; then echo "$ROOT/ssh/config"; else echo "/dev/null"; fi)"
	export RSYNC; RSYNC="$(which rsync)"
	export SCP; SCP="$(which scp)"
	export SHOWSOURCE; SHOWSOURCE="$(which batcat 2>/dev/null || which bat 2>/dev/null || true)"
	if [ "$SHOWSOURCE" != "" ]; then
		# batcat is available, add some flags
		SHOWSOURCE="$SHOWSOURCE --wrap never --style=grid,header,numbers"
	fi
	if [ "$SHOWSOURCE" == "" ]; then
		# batcat is not available, fallback to 'cat'
		export SHOWSOURCE="cat";
	fi
	if [ "${SKIP_INIT:-}" == "" ]; then
		_init
	fi
	if [ "${SKIP_PREREQ_CHECK:-}" == "" ]; then
		_check_prereq
	fi

	if [ -t 0 ] && [ "${PRINT_HELP:-}" ] && [ "$(type -t help)" == "function" ]; then
		echo "Welcome to the install-util shell. Type 'help' for help."
	fi
}

_init() {
	true; # noop, can be overridden in project.sh
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
	return 0
}

# These functions are used to create a "connection" (temp file) to the database
# and then writing the source file afterwards. This way we can keep the source
# file as the "actual" database.
__open_db() {
	if [ "${__OPEN_DB:-}" != "" ]; then
		echo "Can not open multiple connections to the database." >&2
		return 1;
	fi

	local f; f=$(mktemp)
	$SQLITE "$f" < "$CONFIG_DB_SRC"
	echo "$f"

	export __OPEN_DB="$f";
}

__close_db() {
	local f="$1"
	$SQLITE "$f" .dump > "$CONFIG_DB_SRC"
	unset __OPEN_DB
}

db() {
	local opts
	if [ -t 0 ] || [ -t 1 ]; then
		opts="-box"
	fi

	local db; db=$(__open_db)
	local ret=0
	(
		sqlite3 $opts "$@" -init <(echo "PRAGMA foreign_keys=ON;") $db
	) || true
	ret="$?"
	__close_db $db
	return $ret;
}

_query() {
	local db; db=$(__open_db)
	local ret=0
	(
		if [ "$DEBUG" -gt 0 ]; then
			# copy all input to stderr as well.
			# Note that tee /dev/stderr gives permission denied on some systems.
			tee >(cat >&2)
		else
			cat -
		fi | $SQLITE -init /dev/null -bail "$@" "$db"
	) || true
	ret="$?"
	__close_db $db
	return $ret;
}

_confirm() {
	local response;
	read -r -p "$1" response < /dev/tty
	if [ "$response" == "y" ] || [ "$response" == "Y" ]; then
		return 0
	else
		return 1;
	fi;
}

_cfg_get_ip() {
	local env="$1"
	local app="$2"
	_query <<< "SELECT ip FROM vw_app WHERE app_name='$app' AND env_name='$env'"
}

## Get the ssh name for the specified app and environment
_cfg_get_ssh() {
	_query <<< "SELECT ssh FROM server INNER JOIN deployment ON server_name=server.name WHERE app_name='${1}' AND env_name='${2}'"
}

## Get the ssh prefix for the specified app and environment. Will return empty string
## if no ssh is configured
_cfg_get_ssh_prefix() {
	local ssh; ssh=$(_cfg_get_ssh "$1" "$2");
	local sudo; sudo="$(_query <<< "SELECT CASE sudo WHEN true THEN 'sudo' END FROM server INNER JOIN deployment ON server_name=server.name WHERE app_name='${1}' AND env_name='${2}'" 2>/dev/null)"
	if [ "$ssh" != "" ]; then
		shift 2;
		echo "$SSH" -F "$SSH_CONFIG" "$* $ssh $sudo "
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
	"$SSH" -F "$SSH_CONFIG" "$@"
}

## Wrapper for 'rsync' to use the project ssh config.
rsync() {
	"$RSYNC" -e "$SSH -F \"$SSH_CONFIG\"" "$@"
}

## Wrapper for 'scp' to use the project ssh config.
scp() {
	"$SCP" -F "$ROOT/ssh/config" "$@"
}

## Perform deployment for all specified arguments.
install() {
	local vars_before
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
		local ssh; ssh="$(_cfg_get_ssh "$app" "$ENV")"
		local shell; shell="$(_cfg_get_shell "$app" "$ENV")"

		if [ -f "$ROOT/vars.sh" ]; then
			debug_off
			vars_before="$(declare -p)"
			# shellcheck disable=SC1091
			source "$ROOT/vars.sh"
			build_vars="$(_add_declared_vars "$build_vars" "$vars_before" "$(declare -p)")"
			debug_on
		fi

		for subdir in resources artifacts; do
			local $subdir="$ROOT/apps/$app/$subdir/"
		done
		artifacts="$artifacts/$ENV"
		rm -rf "$artifacts"
		mkdir -p "$artifacts"
		local build_script="$ROOT/apps/$app/build.sh"
		if [ -f "$build_script" ]; then
			[ "$DEBUG" -eq 0 ] || echo "Calling build script: $build_script"

			debug_off
			vars_before="$(declare -p)"
			# shellcheck disable=SC1090
			source "$build_script"
			build_vars="$(_add_declared_vars "$build_vars" "$vars_before" "$(declare -p)")"
			debug_on
		fi
		# make the list unique
		build_vars="$(for f in $build_vars; do echo "$f"; done | sort | uniq)"

		local remote_wd;
		remote_wd="$($shell <<< 'mkdir -p scripts && cd scripts && pwd')"

		for script_name in $DO; do
			local src_script="$ROOT/apps/$app/$script_name.sh"
			local target_script="$artifacts/$script_name.sh"
			[ "$DEBUG" -eq 0 ] || echo "Building script $src_script => $target_script"

			if [ -f "$ROOT/apps/$app/$script_name.sh" ]; then
				script_build_vars=""
				for var in $build_vars; do
					if ! [[ "$var" =~ ^[a-zA-Z0-9_]+$ ]]; then
						_fail "Invalid build_var format: $var";
					fi
					# See if var is used, if not, skip it in the export.
					if grep -E '[$][{]?'"$var"'\b' "$ROOT/apps/$app/$script_name.sh" >/dev/null; then
						script_build_vars="$script_build_vars $var";
					fi
				done;

				# subshell to scope 'artifacts' and 'resources' variables remotely different from locally.
				(
					for subdir in resources artifacts; do
						local $subdir="$remote_wd/$app/$ENV/$subdir"
					done
					cat \
						> "$target_script" \
						<(cat \
							<(cat <<-EOF
								#!/usr/bin/env bash
								set -euo pipefail
								if [ "\${DEBUG:-0}" -gt 0 ]; then
									set -x
								fi
							EOF
							) \
							<(for var in $script_build_vars; do
								if [ -v var ] && [ -n "$var${var[*]}" ]; then
									declare -p "$var"
								fi
							done ) \
							"$src_script"
						)
					chmod +x "$target_script";
				)
			fi
		done

		if [ "$DEBUG" -ge 1 ]; then
			PS3="How do you wish to proceed? "
			select x in "Show script" "Show diff" "Continue install [on $shell]" "Exit"; do
				echo "$x";
				case "$REPLY" in
					1)
						for script_name in $DO; do
							if [ -f "$artifacts/$script_name.sh" ]; then
								$SHOWSOURCE "$artifacts/$script_name.sh";
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
									cd "$local_dir" || exit 1;
									find ./ -type f | while read -r f; do
										f="${f:2}"
										diff -s <($shell <<< "cat $remote_dir/$f") "$local_dir/$f" || true
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

			if [ -d "$local_dir" ] && [ "$(find "$local_dir" -type f | wc -l)" -gt 0 ]; then
				rsync_opts=("-prL")
				if [ "$DEBUG" -ge 3 ]; then
					rsync_opts=("${rsync_opts[@]}" "-nv")
				fi
				if [ "$DEBUG" -lt 3 ]; then
					if [ "$DEBUG" -lt 1 ]; then
						$shell <<<"mkdir -p \"$remote_dir\""
					else
						$shell <<<"mkdir -pv \"$remote_dir\""
					fi
				fi
				if [ "$ssh" != "" ]; then
					rsync "${rsync_opts[@]}" "$local_dir/" "$ssh:$remote_dir/"
				else
					rsync "${rsync_opts[@]}" "$local_dir/" "$remote_dir/"
				fi
			fi
		done;
		
		if [ "$DEBUG" -lt 3 ]; then
			for script_name in $DO; do
				if [ -f "$artifacts/$script_name.sh" ]; then
					(
						for subdir in resources artifacts; do
							local $subdir="$remote_wd/$app/$ENV/$subdir"
						done

						DEBUG=$DEBUG ENV=$ENV $shell <<< "$artifacts/$script_name.sh";
					)
				fi
			done;
		else
			echo "Skipping install, DEBUG is set to ${DEBUG}, and script will not run with DEBUG at a value higher than 2" ;
		fi
	done;
}

for u in $UTILS; do
	source "$UTIL_ROOT/${u}.sh"
done

## * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
_prelude;
