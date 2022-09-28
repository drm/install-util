set -euo pipefail

## Called at the end of this file to initialize the environment
_prelude() {
	[ "${DEBUG:-0}" -gt 0 ] && set -x

	if [ "${ROOT:-}" == "" ]; then
		echo "Missing ROOT. See README.md for details."
		exit;
	fi
	if [ -f "$ROOT/project.sh" ]; then
		source $ROOT/project.sh
	fi
	export DEFAULT_ENV="${DEFAULT_ENV:-development}"
	export PS1="$NAMESPACE [\$ENV] "
	export PS4="+ \033[0;37m[debug]\033[0m"' $(date +"%Y-%m-%dT%H:%M:%S.%N") $SHLVL $BASH_SUBSHELL ${BASH_SOURCE:-1}:${LINENO:-} ${FUNCNAME[0]:-main}() - '
	export DEBUG="${DEBUG:-0}"
	export ENV="${ENV:-$DEFAULT_ENV}"
	export HISTFILE="$ROOT/shell_history"
	export FORCE="${FORCE:-}"
	export CONFIG_JSON="$ROOT/config.json"
	export PAGER="${PAGER:-$(which less)}"

	export JQ="$(which jq)"
	export SSH="$(which ssh)"
	export RSYNC="$(which rsync)"

	_check_prereq

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
	[ "$JQ" == "" ] && _fail "jq is not found in the PATH..."
	! [ -f "$CONFIG_JSON" ] && _fail "$CONFIG_JSON is not a file..."
	return 0
}

## Call jq, building a path based on the passed arguments;
## e.g. `_jq a b c` would fetch the value `.a["b"]["c"]`
_jq() {
	local root="$1"
	shift;
	local path; path=".${root}$(for a in $@; do echo -n "[\"${a}\"]"; done)"
	local val; val="$("$JQ" -e -r "$path" < $CONFIG_JSON)"
	if [ "$val" == "null" ]; then
		echo "";
	else
		echo "$val";
	fi;
}

## Get a config value from config.json, based on the same
## principle as _jq, but warn if the value is empty.
_cfg_get() {
	local val; val="$(_jq "$@")"
	if [ "$DEBUG" -gt 0 ] && [ "$val" == "" ]; then
		echo "JQ return value is empty for $@" >&2
	fi
	echo "$val";
}

## Get the server for the passed $app and $ENV,
## e.g. `_cfg_get_server postgres production`
_cfg_get_server() {
	local app="$1"
	local ENV="$2"
	if [ "$(_cfg_get deployments $app)" == "*" ]; then
		server="$ENV"
	else
		server="$(_cfg_get deployments $app $ENV)"
		if [ "$server" == "" ]; then
			_fail "No deployment configured for $app on $ENV"
		fi
	fi
	echo "$server"
}

## Get the ssh prefix for the specified server. Will return empty string
## if the server is 'local'.
_cfg_get_ssh_prefix() {
	local server="$1"
	local opts="${2:-}"
	if [ "$server" != "local" ]; then
		echo "ssh $opts $server "
	fi
}

## Get the shell for the specified deployment; i.e. prefix /bin/bash
## with the ssh prefix, if any. Supports two modes:
## single argument: _cfg_get_shell SERVER
## two arguments: _cfg_get_shell APP ENV
_cfg_get_shell() {
	local server;
	if [ "$#" -eq 2 ]; then
		local app="$1"
		local env="$2"
		server="$(_cfg_get_server $1 $2)"
	elif [ "$#" -eq 1 ]; then
		server="$1"
	fi
	local shell="/bin/bash"
	echo "$(_cfg_get_ssh_prefix "$server")$shell"
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
	for app in $@; do
		if ! [ -f "$ROOT/apps/$app/install.sh" ]; then
			echo "Missing installation script $ROOT/apps/$app/install.sh"
			false;
		fi
	done

	for app in $@; do
		local build_vars="ENV NAMESPACE VERSION artifacts resources app server"
		local server; server="$(_cfg_get_server $app $ENV)"
		local shell; shell="$(_cfg_get_shell $server)"

		source $ROOT/vars.sh

		for subdir in resources artifacts; do
			local $subdir="$ROOT/apps/$app/$subdir/"
		done
		artifacts="$artifacts/$ENV"
		mkdir -p $artifacts
		local build_script="$ROOT/apps/$app/build.sh"
		if [ -f "$build_script" ]; then
			echo "Calling build script: $build_script"
			source "$build_script"
		fi

		if [ "$server" != "local" ]; then
			local remote_pwd; remote_pwd="$($shell -c 'pwd')"
			for subdir in resources artifacts; do
				local local_dir="${!subdir}"
				local remote_dir="$remote_pwd/$app/$ENV/$subdir"
				if [ -d "$local_dir" ] && [ "$(find $local_dir -type f | wc -l)" -gt 0 ]; then
					echo "Syncing $subdir"
					rsync_opts="-v"
					if [ "$DEBUG" -ge 2 ]; then
						rsync_opts="$rsync_opts -n"
					fi
					if [ "$DEBUG" -lt 2 ]; then
						$shell <<-EOF
							mkdir -pv "$remote_dir"
						EOF
					fi
					rsync -prL $rsync_opts $local_dir/ "$server:$remote_dir/"
					local $subdir="$remote_dir"
				else
					local $subdir=""
				fi
			done;
		fi
		local script="$ROOT/apps/$app/artifacts/$ENV.sh"
		echo "Building script: $script"

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
				<(if [ "$(_cfg_get networks $ENV)" != "" ]; then
					cat <<-EOF
					EOF
				else
					echo "# No network configured for env $ENV";
				fi
				) \
				<(for var in $build_vars; do echo $var='"'${!var:-}'"'; done ) \
				$ROOT/apps/$app/install.sh
			)

		if [ "$DEBUG" -gt 1 ]; then
			shell="cat"
		fi
		$shell < $script;
	done;
}

## Show help.
help() {
	$PAGER $ROOT/README.md
}

## List all apps.
apps() {
	for app in $($JQ -r '(.deployments|keys)[] ' < $CONFIG_JSON); do
		if [ "$(_cfg_get deployments $app)" == "*" ] || [ "$(_cfg_get deployments $app $ENV)" != "" ]; then
			echo $app;
		fi
	done
}

## List all deployments for the specified app.
deployments() {
	$JQ -r '(.deployments["'"$1"'"]|keys)[] ' < $CONFIG_JSON
}

## * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
_prelude;
