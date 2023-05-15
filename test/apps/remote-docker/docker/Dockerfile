FROM debian:bullseye

RUN apt-get -y update \
	&& apt-get -y install openssh-server rsync \
	&& rm -rf /var/apt/lists/*

RUN mkdir /run/sshd
ADD start.sh /start.sh

RUN mkdir /root/.ssh && ssh-keygen -t rsa -f /root/.ssh/id_rsa && cat /root/.ssh/id_rsa.pub > /root/.ssh/authorized_keys

CMD ["/start.sh"]
