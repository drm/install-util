#!/bin/bash

# RE SC2154: see https://github.com/koalaman/shellcheck/issues/356
find . -name "*.sh" -exec shellcheck -e SC2154 -f 'gcc' -s bash '{}' + 
