@echo off
odin build src -debug -collection:shared=shared -out:build/app.exe -strict-style -vet -show-timings
