#!/bin/sh
if [ ! -f build/shader_validator ]; then
	odin build tools/shader_validator -o=aggressive -collection:shared=shared -out:build/shader_validator -collection:project=src -strict-style -vet -show-timings
	if [[ $? -ne 0 ]]; then
		exit 1
	fi
fi

build/shader_validator res/shaders/renderer/obj_draw.wgsl -allow-namespaces -include-path:res/shaders -feature:SampledTextureAndStorageBufferArrayNonUniformIndexing
if [[ $? -ne 0 ]]; then
	exit 1
fi
