docker rm -f install-util-remote

docker run -d \
	--name "install-util-remote" \
	-p 22220:22 \
	"$docker_image"
