if [ "${ROOT:-}" == "" ]; then
	echo "Missing ROOT."
	exit;
fi

RESTART="y"
while [ "$RESTART" == "y" ]; do
	( env -i TERM="$TERM" INTERACTIVE=1 bash \
		--rcfile "${BASH_SOURCE[0]}/rc.sh" \
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


