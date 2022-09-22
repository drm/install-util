set -euo pipefail

_prelude() {
	[ "${DEBUG:-0}" -gt 0 ] && set -x

	export ROOT="$(cd "$(dirname "$BASH_SOURCE")" && pwd)"
	source $ROOT/project.sh
	export PS1="$NAMESPACE [\$ENV] "
	export PS4='+ $(date +"%Y-%m-%dT%H:%M:%S") ${BASH_SOURCE:-1}:${LINENO:-} ${FUNCNAME[0]:-main}() - '
    export DEBUG="${DEBUG:-0}"
	export ENV="${ENV:-development}"
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

_build_project() { 						# Builds a project accoriding
	local project_dir="$ROOT/../$1/" 	# 1: A git repository containing the build.sh file
	local docker_image="$2"				# 2: The docker image name

	[ -d "$project_dir" ] || _fail "Project dir does not exist: $project_dir.\nPlease clone the git repo at this location."

	export VERSION="${VERSION:-}"
	if [ "$VERSION" == "" ]; then
		VERSION=$(cd "$project_dir" && git describe)
	fi

	local canonical_image=$DOCKER_REPO/$docker_image:$VERSION

	if [ "${FORCE_BUILD:-}" != "" ] || ( ! docker inspect $canonical_image > /dev/null 2>&1 && ! docker pull $canonical_image > /dev/null 2>&1 ); then
		( cd "$project_dir" && ./build.sh $VERSION )
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
		_fail "Invalid JQ path $path"
		echo "";
	else
		echo "$val";
	fi;
}

_cfg_get() {
	local val="$(_jq "$@")"
	_assert_not_empty "$val" "JQ return value is empty"
	echo "$val";
}

ssh() {
	$(which ssh) -o ControlPath=$ROOT/ssh/sockets/%r@%h-%p -F "$ROOT/ssh/config" "$args"
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
		local build_vars="ENV NAMESPACE artifacts resources app server"

		if [ "$ENV" != "development" ]; then
			local server="$(_cfg_get deployments $app $ENV)"
			local shell="ssh $server $shell"
		else
			local server=""
		fi

		source $ROOT/vars.sh

		for subdir in resources artifacts; do
			local $subdir="$ROOT/apps/$app/$subdir/"
		done
		artifacts="$artifacts/$ENV"

		if [ -f "$ROOT/apps/$app/build.sh" ]; then
			mkdir -p $artifacts
			source "$ROOT/apps/$app/build.sh"
		fi

		if [ "$server" != "" ]; then
			local remote_pwd="$($shell -c 'pwd')"
			for subdir in resources artifacts; do
				if [ -d "$ROOT/apps/$app/resources" ]; then
					rsync "$ROOT/apps/$app/$subdir/" "$server:$app/$subdir/"
					local $subdir="$remote_pwd/$app/resources)"
				fi
			done;
		fi

		if [ "$DEBUG" -gt 1 ]; then
			shell="cat"
		fi

		$shell \
			<(cat \
				<(cat <<-EOF
					set -euo pipefail
					if [ "$DEBUG" -gt 0 ]; then
						set -x
					fi
					if ! docker network inspect $network >/dev/null 2>&1; then
					 	docker network create $network --subnet="$(_cfg_get network $ENV).0/24"
					fi
				EOF
				) \
				<(for var in $build_vars; do echo $var='"'${!var}'"'; done ) \
				$ROOT/apps/$app/install.sh
			)
	done;
}

help() {
	$PAGER $ROOT/README.md
}

_prelude;
