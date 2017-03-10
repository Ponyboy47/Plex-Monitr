#include "select.h"

void fd_zero(fd_set *set) {
    FD_ZERO(&(*set));
}

void fd_setter(int d, fd_set *set) {
    FD_SET(d, &(*set));
}

int fd_isset(int d, fd_set *set) {
    return FD_ISSET(d, set);
}

void fd_clr(int d, fd_set *set) {
    FD_CLR(d, &(*set));
}
