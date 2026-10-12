// 모듈 `CShm` — 런타임 갈래의 C 심(제품 아님). 모듈 지도는 `Docs/SDK.md` §2.
//   무엇       : POSIX `shm_open` 을 고정 인자로 감싼 한 줄.
//   누가 부르나 : SDK 의 `PreviewWire`(`SharedRegion`) 만.
//   지키는 것   : 제품으로 내지 않는다 · 감싸기 밖의 일을 하지 않는다.
//   시작점     : `cshm_open`
#ifndef CSHM_H
#define CSHM_H
#include <sys/types.h>
// POSIX shm_open 은 가변 인자(int shm_open(const char *, int, ...))라 Swift 가 바로 못 부른다 — 고정 인자로 감싼다.
int cshm_open(const char *name, int oflag, mode_t mode);
#endif
