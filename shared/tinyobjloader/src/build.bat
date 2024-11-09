@echo off

cl -nologo -MT -TC -O2 -c tinyobj_loader_build.c
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" (
  lib -nologo tinyobj_loader_build.obj -out:..\lib\Windows_arm64_tinyobjloader.lib
) else (
  lib -nologo tinyobj_loader_build.obj -out:..\lib\Windows_amd64_tinyobjloader.lib
)

del *.obj
