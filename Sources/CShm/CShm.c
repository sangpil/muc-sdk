#include "CShm.h"
#include <sys/mman.h>
int cshm_open(const char *name, int oflag, mode_t mode) { return shm_open(name, oflag, mode); }
