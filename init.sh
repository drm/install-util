#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname ${BASH_SOURCE[0]})" && pwd)"
SKEL="$ROOT/skel"
INIT_ROOT="$(cd "$1" && pwd)"

FILES="
	install.sh
	project.sh
	vars.sh
	config.json
	ssh/config
"

for f in $FILES; do
	mkdir -p "$(dirname $INIT_ROOT/$f)"
	if [ -f "$INIT_ROOT/$f" ]; then
		echo "Skipping $f, file exists"
	else
		cp -v "$SKEL/$f" "$INIT_ROOT/$f"
	fi
done
