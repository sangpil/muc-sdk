#ifndef CSHM_H
#define CSHM_H
#include <sys/types.h>
// POSIX shm_open 은 가변 인자(int shm_open(const char *, int, ...))라 Swift 가 바로 못 부른다 — 고정 인자로 감싼다.
int cshm_open(const char *name, int oflag, mode_t mode);
#endif
