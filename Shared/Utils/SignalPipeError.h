#include <signal.h>

static void sigpipeHandler(int sigNum) {
    __builtin_trap();
}

extern void installSIGPIPEHandler(void) {
    signal(SIGPIPE, sigpipeHandler);
}
