#!/bin/sh
if [ ! -f build/shader_validator ]; then
	odin build tools/shader_validator -o=aggressive -collection:shared=shared -out:build/shader_validator -collection:project=src -strict-style -vet -show-timings
	if [[ $? -ne 0 ]]; then
		exit 1
	fi
fi

build/shader_validator res/shaders/renderer/obj_draw.wgsl -allow-namespaces -include-path:res/shaders
if [[ $? -ne 0 ]]; then
	exit 1
fi

odin build src -debug -collection:shared=shared -out:build/app -strict-style -vet -show-timings -define:WGPU_DEBUG=false
if [[ $? -ne 0 ]]; then
	exit 1
fi

if [[ "$(uname)" == "Darwin" ]]; then
	codesign -s - -v -f --entitlements build/debug.plist build/app
fi
