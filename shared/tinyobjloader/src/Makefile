CC=clang
AR=ar

build:
	$(CC) -o ../lib/tinyobjloader.o -c tinyobj_loader_build.c
	# TODO(Vicix): Do not hardcode
	$(AR) r ../lib/$(shell uname)_arm64_tinyobjloader.a ../lib/tinyobjloader.o
	rm ../lib/tinyobjloader.o
