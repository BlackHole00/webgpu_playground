#include <stddef.h>
#include <stdlib.h>

typedef void* (*TinyObjLoader_Malloc)(size_t size);
typedef void* (*TinyObjLoader_Realloc)(void* ptr, size_t size);
typedef void* (*TinyObjLoader_Calloc)(size_t count, size_t size);
typedef void (*TinyObjLoader_Free)(void* ptr);

TinyObjLoader_Malloc g_tinyobjloader_malloc = NULL;
TinyObjLoader_Realloc g_tinyobjloader_realloc = NULL;
TinyObjLoader_Calloc g_tinyobjloader_calloc = NULL;
TinyObjLoader_Free g_tinyobjloader_free = NULL;

void tinyobj_set_memory_callbacks(
	TinyObjLoader_Malloc malloc,
	TinyObjLoader_Realloc realloc,
	TinyObjLoader_Calloc calloc,
	TinyObjLoader_Free free
) {
	g_tinyobjloader_malloc = malloc;
	g_tinyobjloader_realloc = realloc;
	g_tinyobjloader_calloc = calloc;
	g_tinyobjloader_free = free;
}

static void* tinyobjloader_malloc(size_t size) {
	if (g_tinyobjloader_malloc == NULL) {
		return malloc(size);
	}
	return g_tinyobjloader_malloc(size);
}
static void* tinyobjloader_realloc(void* ptr, size_t size) {
	if (g_tinyobjloader_realloc == NULL) {
		return realloc(ptr, size);
	}
	return g_tinyobjloader_realloc(ptr, size);
}
static void* tinyobjloader_calloc(size_t count, size_t size) {
	if (g_tinyobjloader_calloc == NULL) {
		return calloc(count, size);
	}
	return g_tinyobjloader_calloc(count, size);
}
static void tinyobjloader_free(void* ptr) {
	if (g_tinyobjloader_free == NULL) {
		free(ptr);
		return;
	}
	g_tinyobjloader_free(ptr);
}

#define TINYOBJ_LOADER_C_IMPLEMENTATION
#define TINYOBJ_MALLOC tinyobjloader_malloc
#define TINYOBJ_REALLOC tinyobjloader_realloc
#define TINYOBJ_CALLOC tinyobjloader_calloc
#define TINYOBJ_FREE tinyobjloader_free
#include "tinyobj_loader_c.h"

