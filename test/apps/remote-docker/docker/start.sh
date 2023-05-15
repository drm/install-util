#!/bin/bash

mkdir -p /var/log/ && touch /var/log/sshd.log
/usr/sbin/sshd -f /etc/ssh/sshd_config -E /var/log/sshd.log
tail -f /var/log/sshd.log
