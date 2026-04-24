#!/bin/bash
cd ~/Sites/local-typeless
make build 2>&1 | tee /tmp/lt_build.log
echo "EXIT:$?"
