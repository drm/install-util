export NAMESPACE="???"
export DOCKER_REPO="???"

_cfg_get_ip() {
	local subnet; subnet="$(_cfg_get networks $1)"
	local suffix; suffix="$(_cfg_get suffix $2)"

	! test -z "$subnet"
	! test -z "$suffix"

	echo "$subnet.$suffix"
}

# Called from app/{hub-http,hub-processor,aanbieder-backend,aanbieder-frontend}/build.sh
_build_project() {
	local project_dir="$ROOT/../$1/"
	local docker_image="$2"

	[ -d "$project_dir" ] || _fail "Project dir does not exist: $project_dir.\nPlease clone the git repo at this location."
	[ -f "$project_dir/build.sh" ] || _fail "Project build file does not exist: $project_dir/build.sh.\nPlease verify the git repo at this location."

	export VERSION="${VERSION:-}"
	if [ "$VERSION" == "" ]; then
		VERSION=$(cd "$project_dir" && git describe)
		if [ -n "$(cd "$project_dir" && git status --porcelain)" ]; then
			echo -e "WARNING: $project_dir is not clean."
		fi
	fi

	local canonical_image=$DOCKER_REPO/$docker_image:$VERSION

	if [ "${FORCE_BUILD:-}" != "" ] || ( ! docker inspect $canonical_image > /dev/null 2>&1 && ! docker pull $canonical_image > /dev/null 2>&1 ); then
		( cd "$project_dir" && ./build.sh $VERSION )
	fi
}

version() {
	local app="$1"
	$(_cfg_get_shell "$app" $ENV) <<< "docker ps --format='{{ .Names }}\t{{ .Image }}' | grep \"$NAMESPACE-$app-$ENV\" | awk -F ":" '{print \$NF}'"
}

logs() {
	local app="$1"
	$(_cfg_get_shell "$app" $ENV) <<< "docker logs --tail=100 --follow \"$NAMESPACE-$app-$ENV\""
}
