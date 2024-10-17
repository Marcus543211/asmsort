#define _GNU_SOURCE
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stddef.h>
#include <wait.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>

#define PRINT_CONST(C) printf(#C ": 0x%x\n", C)

int main() {
    printf("About stat from stat and fstat\n");
    printf("stat size: %lu\n", sizeof(struct stat));
    printf("st_size offset: %lu, size: %lu\n", offsetof(struct stat, st_size), sizeof(off_t));
    printf("st_blksize offset: %lu, size: %lu\n", offsetof(struct stat, st_blksize), sizeof(blksize_t));
    printf("st_blocks offset: %lu, size: %lu\n", offsetof(struct stat, st_blocks), sizeof(blkcnt_t));
    printf("\n");
    
    printf("For mmap\n");
    PRINT_CONST(PROT_READ);
    PRINT_CONST(PROT_WRITE);
    PRINT_CONST(MAP_PRIVATE);
    PRINT_CONST(MAP_ANONYMOUS);
    PRINT_CONST(MAP_POPULATE);
    printf("\n");

    printf("For clone\n");
    PRINT_CONST(CLONE_VM);
    PRINT_CONST(SIGCHLD);
    PRINT_CONST(__WCLONE);
    printf("\n");

    return 0;
}

