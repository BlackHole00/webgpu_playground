CC=clang
AR=ar

build:
	$(CC) -o ../lib/stb_include.o -c stb_include.c
	$(AR) r ../lib/$(shell uname)_stb_include.a ../lib/stb_include.o
	rm ../lib/stb_include.o
