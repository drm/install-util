export docker_image; docker_image="install-util-remote-test:$(git describe)"

if ! docker image inspect "$docker_image" >/dev/null 2>&1; then
	( cd "$(dirname "${BASH_SOURCE[0]}")"/docker && ./build.sh )
fi
