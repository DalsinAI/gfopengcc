# The socket library's user and group calls without usergroup.library

**Fixed by:** `patches/libnix/0011-socket-user-and-group-calls-without-usergroup.library.patch`. Stoves built before it get it from `runtime/stove-usergroup`.

## What went wrong

When `bsdsocket.library` opens, libnix's socket library runs in AmiTCP mode (`LX_AMITCP`). Its user and group calls then go to `usergroup.library` through `lx_UserGroupBase`, which `__initsock` opens. GFOpenSocket, and Roadshow without it, have no usergroup.library, so that base stays NULL.

Only `getpwuid()` checked the base. Every other call went through the NULL base and never came back: `getgrgid`, `getgrnam`, `getgrent`, `setgrent`, `endgrent`, `getpwnam`, `getpwent`, `setpwent`, `endpwent`, `getgroups`, `setgroups` and `crypt`.

- wxWidgets' tar reader calls `getgrgid()` for every archive (wxTarUser), so 4Pane hung on opening a .tar.gz or .tar.bz2 (Team 2, 11 Nov 2026).
- The lab task list showed the task waiting with an empty signal mask.
- `tests/libnix/usergroup_calls.c` hangs at its first call, `getgrgid(getgid())`.

## What the patch does

With AmiTCP but no usergroup.library, the calls answer as libnix does with no network at all:

- **Groups:** the built-in groups `wheel` (0) and `nogroup` (-2), and `$GROUP` for `getgid()`'s group.
- **Users:** the built-in users `root` and `nobody`, and `getlogin()`'s user with `$HOME` and `$REALNAME`.
- **Files:** none are looked for. `inet:db/group` and `etc:passwd` are AS225 and no-network paths, and on these stacks those assigns are not there.
- `getgroups()` and `setgroups()` use the list libnix keeps itself. `crypt()` returns NULL.
- With a usergroup.library present, nothing changes.

## Check

In a lab with GFOpenSocket (Instance-32 copy t2-arexx-20261110), run `UsergroupCalls` from `runtime/stove-usergroup/build-amiga.sh`. It returns at once and prints `usergroup: ALL RETURNED`. `UsergroupCalls-old` stops after `getgrgid(getgid())...`.
