#define _GNU_SOURCE
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>

int pthread_noop() {
    fprintf(stderr, "%s(...)\n", __func__);
    return 0;
}

// https://stackoverflow.com/questions/15599026/how-can-i-intercept-dlsym-calls-using-ld-preload/18825060#18825060

static void* (*libc_dlvsym)(void*, const char*) = NULL;
static void* (*libc_dlsym)(void*, const char*) = NULL;

void* dlsym(void* handle, const char* symbol) {

if (!libc_dlsym) {
    libc_dlsym = dlvsym(RTLD_NEXT, "dlsym", "GLIBC_2.2.5");
}

//~ fprintf(stderr, "%s(_, %s)\n", __func__, symbol);

if (strcmp(symbol, "pthread_attr_setinheritsched") == 0) {
    return pthread_noop;
}

return libc_dlsym(handle, symbol);
} 