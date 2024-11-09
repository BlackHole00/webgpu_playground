@echo off
call validate_shaders.bat

odin build src -debug -collection:shared=shared -out:build/app.exe -strict-style -vet -show-timings -define:WGPU_DEBUG=false
