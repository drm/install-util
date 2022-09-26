set -euo pipefail
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
	export PS4="\033[0;31m[debug]\033[0m"'+ $(date +"%Y-%m-%dT%H:%M:%S") ${BASH_SOURCE:-1}:${LINENO:-} ${FUNCNAME[0]:-main}() - '
	export DEBUG="${DEBUG:-0}"
	export ENV="${ENV:-$DEFAULT_ENV}"
	export HISTFILE="$ROOT/shell_history"
	export FORCE="${FORCE:-}"
	export CONFIG_JSON="$ROOT/config.json"
	export JQ="$(which jq)"
	export PAGER="${PAGER:-$(which less)}"

	_check_prereq

	if [ "${INTERACTIVE:-}" == "1" ]; then
		cat "$ROOT/resources/doc/header.md";
	fi
}

_fail() {
	echo -e "FATAL: $1" >&2
	exit 1
}

_assert_not_empty() {
	[ "$1" != "" ] || _fail "$2"
}

_check_prereq() {
	[ "$JQ" == "" ] && _fail "jq is not found in the PATH..."
	! [ -f "$CONFIG_JSON" ] && _fail "$CONFIG_JSON is not a file..."
	return 0
}

_jq() {
	local root="$1"
	shift;
	local path=".${root}$(for a in $@; do echo -n "[\"${a}\"]"; done)"
	local val="$("$JQ" -e -r "$path" < $CONFIG_JSON)"
	if [ "$val" == "null" ]; then
		echo "";
	else
		echo "$val";
	fi;
}

_cfg_get() {
	local val="$(_jq "$@")"
	if [ "$DEBUG" -gt 0 ] && [ "$val" == "" ]; then
		echo "JQ return value is empty for $@" >&2
	fi
	echo "$val";
}

ssh() {
	$(which ssh) -o ControlPath=$ROOT/ssh/sockets/%r@%h-%p -F "$ROOT/ssh/config" $@
}

debug() {
	if [ "${1:-}" == "off" ]; then
		DEBUG="0"
	else
		DEBUG="$(( "$DEBUG" + 1 ))"
	fi
	_prelude
	echo "Set debugging level to $DEBUG"
}

env() {
	ENV="$1"
	_prelude
}

vars() {
	"$(which env)";
}

install() {
	local shell="/bin/bash"
	for app in $@; do
		if ! [ -f "$ROOT/apps/$app/install.sh" ]; then
			echo "Missing installation script $ROOT/apps/$app/install.sh"
			false;
		fi
	done

	for app in $@; do
		local build_vars="ENV NAMESPACE VERSION artifacts resources app server"
		local server

		if [ "$(_cfg_get deployments $app)" == "*" ]; then
			server="$ENV"
		else
			server="$(_cfg_get deployments $app $ENV)"
			if [ "$server" == "" ]; then
				_fail "No deployment configured for $app on $ENV"
			fi
		fi

		if [ "$server" != "local" ]; then
			local shell="ssh $(_cfg_get "servers" $server) $shell"
		fi

		source $ROOT/vars.sh

		for subdir in resources artifacts; do
			local $subdir="$ROOT/apps/$app/$subdir/"
		done
		artifacts="$artifacts/$ENV"
		mkdir -p $artifacts
		if [ -f "$ROOT/apps/$app/build.sh" ]; then
			source "$ROOT/apps/$app/build.sh"
		fi

		if [ "$server" != "local" ]; then
			local remote_pwd="$($shell -c 'pwd')"
			for subdir in resources artifacts; do
				local local_dir="${!subdir}"
				local remote_dir="$remote_pwd/$app/$ENV/$subdir"
				if [ -d "$local_dir" ] && [ "$(find $local_dir -type f | wc -l)" -gt 0 ]; then
					ssh "$(_cfg_get "servers" $server)" mkdir -p $remote_dir
					rsync -r $local_dir/ "$(_cfg_get "servers" $server):$remote_dir/"
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
						if ! docker network inspect $network >/dev/null 2>&1; then
							docker network create $network --subnet="$(_cfg_get networks $ENV).0/24"
						fi
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

help() {
	$PAGER $ROOT/README.md
}

apps() {
	find $ROOT/apps -maxdepth 2 -type f -name "install.sh" | awk -F "/" '{print $(NF-1)}' | sort
}

_prelude;
