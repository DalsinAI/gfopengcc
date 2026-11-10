# libnix: POSIX ioctl() and fcntl() for sockets (patch 0010)

**Found:** Team 2, 10 Nov 2026, porting aMule. A small libnix `-lsocket`
program (built with os32-gcc16-open6) on GFOpenSocket 4.5:

    fcntl(F_GETFD)   -> -1 errno 0
    ioctl(FIONBIO)   -> -1 errno 14 (EFAULT)

GFOpenSocket's `IoctlSocket()` itself was fine: called directly, FIONBIO,
FIONREAD, EWOULDBLOCK, non-blocking connect and recvmsg/sendmsg all pass
(gfopensocket `tests/nonblockprobe.c`).

**Cause:** `sources/socket/socket/ioctl.c` reads three variable arguments,
ixemul's `ioctl(fd, cmd, inout, arglen, data)`. A POSIX caller passes one,
so `data` is whatever lies on the stack two words after it: 0 gives EFAULT;
anything else is used as the argument (FIONBIO reads it, FIONREAD writes
through it). In the lab the same binary failed or "worked" depending on the
caller's stack. `sources/nix/extra/fcntl.c` is a stub: -1, errno untouched.

**Fix:** `ioctl()` reads one argument; a descriptor that isn't open is
EBADF and a file ENOTTY. The socket library gets an `fcntl()` (it links
before libnix): F_GETFD 0, F_SETFD taken, F_SETFL O_NONBLOCK through
FIONBIO, F_GETFL O_RDWR (bsdsocket.library has no call that reports
FIONBIO), others EINVAL.

**Checked:** the two patched files built with the open6 stove and linked
ahead of `-lsocket` (lab t5-sockfix-20261110, a copy of Instance-32, with
bsdsocket.library 4.6): Team 2's udptest gives `fcntl(F_GETFD) -> 0` and
`ioctl(FIONBIO) -> 0`; GFOpenBoost's `tests/sockctl.c` passes 26 of 27, the
one FAIL being F_GETFL not reporting O_NONBLOCK, as above. libnix itself has
not been rebuilt into a stove yet.

Until a stove carries it, GFOpenBoost's `compat/src/amiga_ioctl.c` does the
same for programs linked with `libboost_asio`.
