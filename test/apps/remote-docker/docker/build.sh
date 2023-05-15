#!/bin/bash

NO_COLOR=1 docker build -t install-util-remote-test:$(git describe) .
