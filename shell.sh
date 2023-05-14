#!/usr/bin/env bash

RCFILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rc.sh"
RESTART="y"
while [ "$RESTART" == "y" ]; do
	( env -i BASH="$BASH" ROOT="$ROOT" TERM="$TERM" INTERACTIVE=1 "$BASH" \
		--rcfile "$RCFILE" \
		-i )
	status="$?"
	if [ "$status" != "0" ]; then
		echo "Shell exited with status $status"
		read -r \
			-p "Do you wish to restart? [y/N] " \
			RESTART
	else
		RESTART=""
	fi
done


