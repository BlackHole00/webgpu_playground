@echo off

if not exist build\shader_validator.exe (
  odin build tools/shader_validator -o=aggressive -collection:shared=shared -out:build/shader_validator.exe -collection:project=src -strict-style -vet -show-timings
)

build\shader_validator.exe res/shaders/renderer/obj_draw.wgsl -allow-namespaces -include-path:res/shaders
