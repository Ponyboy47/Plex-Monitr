#include <sys/select.h>

__BEGIN_DECLS

extern void fd_zero(fd_set *set);
extern void fd_setter(int d, fd_set *set);
extern int fd_isset(int d, fd_set *set);
extern void fd_clr(int d, fd_set *set);

__END_DECLS
