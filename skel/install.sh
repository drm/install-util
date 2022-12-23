#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
	echo "Usage: ./install.sh ENV APP1 [APP2 ...]" >&2
	exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV="$1"
shift;
source $ROOT/install-util/rc.sh

install $@
