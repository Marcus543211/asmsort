#define _GNU_SOURCE
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stddef.h>
#include <wait.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>

int main() {
    printf("About stat from stat and fstat\n");
    printf("stat size: %lu\n", sizeof(struct stat));
    printf("st_size offset: %lu, size: %lu\n", offsetof(struct stat, st_size), sizeof(off_t));
    printf("st_blksize offset: %lu, size: %lu\n", offsetof(struct stat, st_blksize), sizeof(blksize_t));
    printf("st_blocks offset: %lu, size: %lu\n", offsetof(struct stat, st_blocks), sizeof(blkcnt_t));
    printf("\n");
    
    printf("For mmap\n");
    printf("PROT_READ: %x\n", PROT_READ);
    printf("PROT_WRITE: %x\n", PROT_WRITE);
    printf("MAP_PRIVATE: %x\n", MAP_PRIVATE);
    printf("MAP_ANONYMOUS: %x\n", MAP_ANONYMOUS);
    printf("MAP_POPULATE: %x\n", MAP_POPULATE);
    printf("\n");

    printf("For clone\n");
    printf("CLONE_VM: %x\n", CLONE_VM);
    printf("SIGCHLD: %x\n", SIGCHLD);
    printf("__WCLONE: %x\n", __WCLONE);
    printf("\n");

    return 0;
}

