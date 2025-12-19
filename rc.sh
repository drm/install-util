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
	if ! _is_debugging_global && [ "${DEBUG/X}" != "$DEBUG" ]; then
		set -x
 	fi
}

debug_off() {
	if ! _is_debugging_global && [ "${DEBUG/X}" != "$DEBUG" ]; then
		set +x
	fi
}

## Called at the end of this file to initialize the environment
_prelude() {
	local vars_before

	if [ "${ROOT:-}" == "" ]; then
		echo "Missing ROOT. See README.md for details."
		exit;
	fi
	export build_vars="DEBUG ENV VERSION resources artifacts"
	if [ -f "$ROOT/project.sh" ]; then
		vars_before="$(declare -p)"
		# shellcheck disable=SC1091
		source "$ROOT/project.sh"
		build_vars="$(_add_declared_vars "$build_vars" "$vars_before" "$(declare -p)")"
		vars_before=""
	fi
	export PS1="server-config [$NAMESPACE] "
	export PS4="+ \033[0;37m[debug]\033[0m"' $(date +"%Y-%m-%dT%H:%M:%S.%N") ${BASH_SOURCE:-1}:${LINENO:-} ${FUNCNAME[0]:-main}() - '

	export DEBUG
	if [ -v DEBUG ]; then
		case "$DEBUG" in
			1) DEBUG="ixp"; ;;
			2) DEBUG="ixpvSO"; ;;
			3) DEBUG="ixpvSOXD"; ;;
			"?")
				cat <<-EOF
					DEBUG contains debug flags:

					 X - execute internal bash -x
					 x - execute scripts with bash -x
					 s - print all SQL
					 v - print var declarations used in scripts
					 i - print info messages
					 p - show prompts in vital stages
					 O - make file operations verbose (rsync, mkdir, etc)
					 D - Dry-run, don't execute the scripts
					 ? - Show this message

					Shortcuts are:

					 1 - ixp
					 2 - ixpvSO
					 3 - ixpvSOXD

					When in doubt, search '${BASH_SOURCE[0]/$ROOT\//}' for occurrences of DEBUG/C
					where C is the debug flag.
				EOF
		esac
	fi
	export DEBUG="${DEBUG:-}"
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

	export SQLITE; SQLITE="$(which sqlite3 || true)"
	export SSH; SSH="$(which ssh || true)"
	export SSH_CONFIG; SSH_CONFIG="$(if [ -f "$ROOT/ssh/config" ]; then echo "$ROOT/ssh/config"; else echo "/dev/null"; fi)"
	export RSYNC; RSYNC="$(which rsync || true)"
	export SCP; SCP="$(which scp || true)"
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

	local existing_trap; existing_trap="$(trap -p EXIT)"
	# shellcheck disable=SC2064
	trap "${existing_trap:+$existing_trap; }_exit" EXIT
}

_init() {
	true; # noop, can be overridden in project.sh
}

_exit() {
	true;
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

db() {
	local tmp_file="$(mktemp)"
	local ret=0
	local opts="";

	if [ -t 0 ] || [ -t 1 ]; then
		opts="-box"
	fi

	if ! $SQLITE "$tmp_file" $opts "$@" -init <(
		cat $CONFIG_DB_SRC;

		echo "PRAGMA foreign_keys=ON;"
	); then
		ret="$!"
	else
		$SQLITE $tmp_file <<-EOF
			.output $CONFIG_DB_SRC
			.dump
		EOF
	fi
	rm -f $tmp_file
	return $ret
}

_query() {
	local query="$(cat)"
	local is_transaction

	is_transaction="$(grep -cP 'COMMIT;?\s*$' <<< "$query" || true)"

	if [ "$is_transaction" == 0 ] && grep -P '\b(CREATE|ALTER|UPDATE|DELETE|INSERT)\b' <<< "$query" >/dev/null; then
		echo "$query" >&2
		cat <<-EOF >&2

			WARNING: query seems to contain modification queries, but it's not
			wrapped in a transaction. Note that change queries are not persisted
			if they are not inside a transaction block.

		EOF
	elif [ "${DEBUG/s}" != "$DEBUG" ]; then
		echo "[SQL] $(paste -sd" " <<< "$query")" >&2
	fi

	contents="$(
		cat <<-EOF
			.read $CONFIG_DB_SRC
			PRAGMA foreign_keys=ON;
			$query;
		EOF

		if [ "$is_transaction" != 0 ]; then
			cat <<-EOF
				.output $CONFIG_DB_SRC
				.dump
			EOF
		fi
	)"
	$SQLITE -init /dev/null -bail "$@" <<< "$contents"
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

_server_deployment_where() {
	echo "app_name='${1}' AND env_name='${2}' AND node_id='${3:-1}'";
}

## Get the ssh name for the specified app, environment and node id
_cfg_get_ssh() {
	local name
	name="$(
		_query <<-EOF
			SELECT DISTINCT name FROM server INNER JOIN deployment ON server_name=server.name
			WHERE $(_server_deployment_where "$1" "$2" "${3:-1}")
		EOF
	)"
	if [ "$name" != "local" ]; then
		echo "$name"
	fi
}

## Get the ssh prefix for the specified app and environment. Will return empty string
## if no ssh is configured
_cfg_get_ssh_prefix() {
	local ssh; ssh=$(_cfg_get_ssh "$1" "$2" "${3:-0}");
	local sudo; sudo="$(_query <<< "SELECT CASE sudo WHEN true THEN 'sudo' END FROM server INNER JOIN deployment ON server_name=server.name WHERE  $(_server_deployment_where "$1" "$2" "${3:-1}")" 2>/dev/null)"
	if [ "$ssh" != "" ]; then
		shift 3;
		echo "$SSH" -F "$SSH_CONFIG" "$* $ssh $sudo "
	fi
}

## Get the shell for the specified deployment; i.e. prefix /bin/bash
## with the ssh prefix, if any.
_cfg_get_shell() {
	local prefix; prefix="$(_cfg_get_ssh_prefix "$1" "$2" "${3:-}")"
	if [ "$prefix" == "" ]; then
		echo -n "$BASH"
	else
		echo -n "${prefix}/bin/bash"
	fi
	if [ "${DEBUG/X}" != "${DEBUG}" ]; then
		echo -n " -x"
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
		if [ "$(_query <<<"SELECT COUNT(1) FROM deployment WHERE app_name='$app' AND env_name='$ENV'")" == "0" ]; then
			_fail "No deployment for $app on $ENV. Valid deployments for $app are: $(_query <<< "SELECT GROUP_CONCAT(env_name, ', ') FROM deployment WHERE app_name='$app'")"
		fi
		if ! [ -f "$ROOT/apps/$app/install.sh" ]; then
			_fail "Missing installation script $ROOT/apps/$app/install.sh"
		fi
	done

	local file_opts_verbose;
	if [ "${DEBUG/O}" != "$DEBUG" ]; then
		file_opts_verbose="v"
	else
		file_opts_verbose=""
	fi

	for app in "$@"; do
		DROP_TO_SHELL=""

		# deployments may have multiple nodes:
		query="SELECT node_id FROM deployment WHERE app_name='$app' AND env_name='$ENV'"
		if [ "${NODE_ID:-}" != "" ]; then
			query="$query AND node_id='$NODE_ID'"
		fi
		if [ "${ROLE:-}" != "" ]; then
			query="$query AND role='$ROLE'"
		fi
		for node_id in $(_query <<< "$query"); do
			_info() {
				if [ "${DEBUG/i}" != "$DEBUG" ]; then
					echo "[app=$app, node_id=$node_id, ENV=$ENV, DO=$DO]" "$@" >&2
				fi
			}

			_info "Setting up"

			local ssh; ssh="$(_cfg_get_ssh "$app" "$ENV" "$node_id")"
			local shell; shell="$(_cfg_get_shell "$app" "$ENV" "$node_id")"

			if [ -f "$ROOT/vars.sh" ]; then
				_info "Reading vars"
				vars_before="$(declare -p)"
				# shellcheck disable=SC1091
				source "$ROOT/vars.sh"
				build_vars="$(_add_declared_vars "$build_vars" "$vars_before" "$(declare -p)")"
				vars_before=""
			fi

			for subdir in resources artifacts; do
				local $subdir="$ROOT/apps/$app/$subdir"
			done
			artifacts="$artifacts/$ENV"
			_info "Creating artifacts"
			rm -rf${file_opts_verbose} "$artifacts"
			mkdir -p${file_opts_verbose} "$artifacts"
			local build_script="$ROOT/apps/$app/build.sh"
			if [ -f "$build_script" ]; then
				_info "Build script found: ${build_script/"$ROOT/"}"

				vars_before="$(declare -p)"
				# shellcheck disable=SC1090
				source "$build_script"
				build_vars="$(_add_declared_vars "$build_vars" "$vars_before" "$(declare -p)")"
				vars_before=""
			fi
			# make the list unique
			build_vars="$(for f in $build_vars; do echo "$f"; done | sort | uniq)"

			local remote_wd;
			remote_wd="$($shell <<< "mkdir -p${file_opts_verbose} scripts && cd scripts && pwd")"

			debug_on

			for script_name in $DO; do
				_info "Entering DO=$script_name"

				local src_script="$ROOT/apps/$app/$script_name.sh"
				local target_script="$artifacts/$script_name.sh"
				local declaration_block=""

				_info "Building script '${src_script/"$ROOT/"}' => '${target_script/"$ROOT/"}'" >&2

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

						declaration_block="$(
							for var in $script_build_vars; do
								if [ -v var ] && [ -n "$var${var[*]}" ]; then
									declare -p "$var"
								fi
							done
						)"

						if [ "${DEBUG/v}" != "$DEBUG" ]; then
							echo "------------------"
							echo "$declaration_block"
							echo "------------------"
						fi

						cat \
							> "$target_script" \
							<(cat \
								<(cat <<-EOF
									#!/usr/bin/env bash
									set -euo pipefail
									export DEBUG="${DEBUG}"

									if [ "\${DEBUG/x}" != "$DEBUG" ]; then
										set -x
									fi
								EOF
								) \
								<(echo "$declaration_block") \
								"$src_script"
							)

						_info "Written ${target_script/"$ROOT/"}"

						if [ "$file_opts_verbose" ]; then
							chmod +x -v "$target_script";
						else
							chmod +x "$target_script";
						fi
					)
				fi
			done

			if [ "${DEBUG/p}" != "$DEBUG" ]; then
				debug_off
				echo "=== ${artifacts/"$ROOT/"} ===="
				ls -l $artifacts
				echo ""
				PS3="How do you wish to proceed? "
				select x in "Show script(s)" "Drop to shell in '${artifacts/"$ROOT/"}'" "Continue install [on $shell]" "Continue and drop to remote shell" "Continue and disable further prompting." "Exit";  do
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
							echo "Dropping to shell. Either use CTRL+D or type exit [enter] to return."
							( cd $artifacts && $BASH -i )
						;;
						3)
							break
						;;
						4)
							DROP_TO_SHELL=1
							break
							;;
						5)
							export DEBUG="${DEBUG/p}"
							break
						;;
						6|q|x) exit; ;;
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

			debug_on

			for subdir in resources artifacts; do
				local local_dir="${!subdir}"
				local remote_dir="$remote_wd/$app/$ENV/$subdir"

				if [ -d "$local_dir" ] && [ "$(find "$local_dir" -type f | wc -l)" -gt 0 ]; then
					rsync_opts=("-prL${file_opts_verbose}" "--delete")
					$shell <<<"mkdir -p${file_opts_verbose} \"$remote_dir\""
					if [ "$ssh" != "" ]; then
						rsync "${rsync_opts[@]}" "$local_dir/" "$ssh:$remote_dir/"
					else
						rsync "${rsync_opts[@]}" "$local_dir/" "$remote_dir/"
					fi
				fi
			done;

			_info "Artifacts sync'ed to remote at $remote_dir"

			for script_name in $DO; do
				if [ -f "$artifacts/$script_name.sh" ]; then
					(
						for subdir in resources artifacts; do
							local $subdir="$remote_wd/$app/$ENV/$subdir"
						done
						if [ "$DROP_TO_SHELL" ]; then
							_info "Artifacts are in: $artifacts"
							$shell -i
						fi
						if [ "${DEBUG/D}" != "$DEBUG" ]; then
							_info "Not executing remote script, as (D)ry-run debug flag is set."
							cat <<-EOF
								$shell <<< "export DEBUG=$DEBUG; export ENV=$ENV; $artifacts/$script_name.sh";
							EOF
						else
							if [ "${DEBUG/i}" != "${DEBUG}" ]; then
								_info "Executing $artifacts/$script_name.sh" >&2
							fi
							$shell <<< "export DEBUG=$DEBUG; export ENV=$ENV; $artifacts/$script_name.sh";
						fi
					)
				elif [ "${DEBUG/i}" != "${DEBUG}" ]; then
					_info "Skipping DO=$DO, $artifacts/$script_name does not exist"
				fi
			done
		done
	done;
}

for u in $UTILS; do
	source "$UTIL_ROOT/${u}.sh"
done

## * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
_prelude;
