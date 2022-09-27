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

	export APP_NAMES=$($JQ -r '(.deployments|keys)[] ' < $CONFIG_JSON)
	export ENV_NAMES=$(for a in $APP_NAMES; do $JQ -r '(.deployments["'$a'"]|keys?)[]' < $CONFIG_JSON; done | sort | uniq)
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
	local path; path=".${root}$(for a in $@; do echo -n "[\"${a}\"]"; done)"
	local val; val="$("$JQ" -e -r "$path" < $CONFIG_JSON)"
	if [ "$val" == "null" ]; then
		echo "";
	else
		echo "$val";
	fi;
}

_cfg_get() {
	local val; val="$(_jq "$@")"
	if [ "$DEBUG" -gt 0 ] && [ "$val" == "" ]; then
		echo "JQ return value is empty for $@" >&2
	fi
	echo "$val";
}

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

_cfg_get_ssh_prefix() {
	local server="$1"
	local opts="${2:-}"
	if [ "$server" != "local" ]; then
		echo "ssh $opts $server "
	fi
}

_cfg_get_shell() {
	local shell="/bin/bash"
	echo "$(_cfg_get_ssh_prefix "$1")$shell"
}

ssh() {
	$(which ssh) -F "$ROOT/ssh/config" $@
}

rsync() {
	$(which rsync) -e "$(which ssh) -F $ROOT/ssh/config" $@
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
	for app in $@; do
		if ! [ -f "$ROOT/apps/$app/install.sh" ]; then
			echo "Missing installation script $ROOT/apps/$app/install.sh"
			false;
		fi
	done

	for app in $@; do
		local build_vars="ENV NAMESPACE VERSION artifacts resources app server"
		local server="$(_cfg_get_server $app $ENV)"
		local shell="$(_cfg_get_shell $server)"

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

__do() {
	local fn="$1"
	local app="$2"
	local server="$(_cfg_get_server $app $ENV)"
	local shell="$(_cfg_get_shell "$server")"

#	if [ -f "$ROOT/apps/$app/$fn.sh" ]; then
#		source "$ROOT/apps/$app/$fn.sh"
#	fi

	case "$fn" in
		"version-at" )
			$shell <<-EOF
				docker ps --format='{{ .Names }}\t{{ .Image }}' | grep "$NAMESPACE-$app-$ENV" | awk -F ":" '{print \$NF}'
			EOF
		;;
		"logs" )
			$shell <<-EOF
				docker logs --tail=100 --follow "$NAMESPACE-$app-$ENV"
			EOF
		;;
	esac
}

version-at() {
	__do version-at $@
}

logs() {
	__do logs $@
}

_prelude;

# Trick to autocomplete envs; typing env name will select it.
for e in $ENV_NAMES; do
	eval "$e() {
		env $e;
	}"
done;
