/* libnix socket library: POSIX ioctl() and fcntl() on a socket (patch
 * 0010). Before it, ioctl(FIONBIO) gave -1 errno 14 (EFAULT) or worked by
 * chance, and fcntl(F_GETFD) gave -1 with errno left 0.
 *   m68k-amigaos-gcc -noixemul -m68040 -O2 socket_ioctl.c -lsocket
 * Needs a running bsdsocket.library; prints PASS/FAIL per line. */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <sys/filio.h>
#include <netinet/in.h>

static int fails;
static void check(const char *what, int ok, int r)
{
    printf("%-36s %s", what, ok ? "PASS" : "FAIL");
    if (!ok) printf(" (rc %d errno %d)", r, errno);
    printf("\n");
    fails += !ok;
}

int main(void)
{
    struct sockaddr_in a;
    struct timeval tv = { 1, 0 };
    char buf[8];
    int s = socket(AF_INET, SOCK_DGRAM, 0), on = 1, off = 0, n = -1, r;
    check("socket", s >= 0, s);
    if (s < 0) return 20;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_port = htons(23481);
    a.sin_addr.s_addr = htonl(0x7f000001UL);
    bind(s, (struct sockaddr *)&a, sizeof a);
    setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);   /* no hang if FIONBIO fails */
    errno = 0; r = ioctl(s, FIONBIO, &on);
    check("ioctl FIONBIO on", r == 0, r);
    errno = 0; r = recv(s, buf, sizeof buf, 0);
    check("recv empty EWOULDBLOCK", r == -1 && errno == EWOULDBLOCK, r);
    errno = 0; r = ioctl(s, FIONREAD, &n);
    check("ioctl FIONREAD 0", r == 0 && n == 0, r);
    errno = 0; r = ioctl(s, FIONBIO, &off);
    check("ioctl FIONBIO off", r == 0, r);
    errno = 0; r = ioctl(1, FIONBIO, &on);
    check("ioctl on a console ENOTTY", r == -1 && errno == ENOTTY, r);
    errno = 0; r = fcntl(s, F_GETFD, 0);
    check("fcntl F_GETFD 0", r == 0, r);
    errno = 0; r = fcntl(s, F_SETFD, FD_CLOEXEC);
    check("fcntl F_SETFD", r == 0, r);
    errno = 0; r = fcntl(s, F_SETFL, O_NONBLOCK);
    check("fcntl F_SETFL O_NONBLOCK", r == 0, r);
    errno = 0; r = recv(s, buf, sizeof buf, 0);
    check("recv empty EWOULDBLOCK (F_SETFL)", r == -1 && errno == EWOULDBLOCK, r);
    errno = 0; r = fcntl(97, F_GETFD, 0);
    check("fcntl closed descriptor EBADF", r == -1 && errno == EBADF, r);
    close(s);
    printf("%s\n", fails ? "FAIL" : "ALL PASS");
    return fails ? 20 : 0;
}
