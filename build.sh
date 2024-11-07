#!/bin/sh
odin build src -debug -collection:shared=shared -out:build/app -strict-style -vet -show-timings -define:WGPU_DEBUG=false
if [[ $? -ne 0 ]]; then
	exit 1
fi

if [[ "$(uname)" == "Darwin" ]]; then
	codesign -s - -v -f --entitlements build/debug.plist build/app
fi
