#!/bin/sh
odin build src -debug -collection:shared=shared -out:build/app -strict-style -vet -show-timings
if [[ $? -ne 0 ]]; then
	exit
fi

if [[ "$(uname)" == "Darwin" ]]; then
	codesign -s - -v -f --entitlements build/debug.plist build/app
fi
