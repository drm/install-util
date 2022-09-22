#!/usr/bin/env bash

RCFILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rc.sh"
RESTART="y"
while [ "$RESTART" == "y" ]; do
	( env -i ROOT="$ROOT" TERM="$TERM" INTERACTIVE=1 bash \
		--rcfile "$RCFILE" \
		-i )
	status="$?"
	if [ "$status" != "0" ]; then
		echo "Shell exited with status $status"
		read \
			-p "Do you wish to restart? [y/N] " \
			RESTART
	else
		RESTART=""
	fi
done


