CC=clang
AR=ar

build:
	$(CC) -o ../lib/tinyobjloader.o -c tinyobj_loader_build.c -g
	$(AR) r ../lib/$(shell uname)_tinyobjloader.a ../lib/tinyobjloader.o
	rm ../lib/tinyobjloader.o
