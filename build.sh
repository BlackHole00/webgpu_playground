#!/bin/sh
odin build src -debug -collection:shared=shared -collection:project=src -out:build/app -strict-style -vet -show-timings -internal-cached
if [[ $? -ne 0 ]]; then
	exit 1
fi

if [[ "$(uname)" == "Darwin" ]]; then
	codesign -s - -v -f --entitlements build/debug.plist build/app
fi
