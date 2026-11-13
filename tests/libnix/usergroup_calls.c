/*
 * usergroup_calls.c: the socket library's user and group calls come back
 * (libnix patch 0011).
 *
 * With bsdsocket.library open (AmiTCP mode) but no usergroup.library, the
 * calls went through a NULL library base and never came back: wxWidgets'
 * tar reader calls getgrgid() for every archive, which hung 4Pane on a
 * .tar.gz (Team 2, 11 Nov 2026). Each call here is printed before it is
 * made, so a hang shows which one; "usergroup: ALL RETURNED" at the end.
 *   m68k-amigaos-gcc -noixemul -m68040 -O2 usergroup_calls.c -lsocket
 * Copyright (c) 2026 AmiCradle Team. MIT licence (see LICENSE at the repository root).
 */
#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <grp.h>
#include <pwd.h>

static void step(const char *what)
{
    printf("%s... ", what);
    fflush(stdout);
}

static void said(const char *name)
{
    printf("%s\n", name ? name : "(none)");
    fflush(stdout);
}

int main(void)
{
    struct group *g;
    struct passwd *p;
    gid_t list[32];
    int n;

    printf("uid %d gid %d\n", (int)getuid(), (int)getgid());
    step("getgrgid(getgid())"); g = getgrgid(getgid()); said(g ? g->gr_name : NULL);
    step("getgrgid(0)");        g = getgrgid(0);        said(g ? g->gr_name : NULL);
    step("getgrnam(\"wheel\")"); g = getgrnam("wheel"); said(g ? g->gr_name : NULL);
    step("setgrent/getgrent/endgrent");
    setgrent();
    for (n = 0; n < 8 && (g = getgrent()) != NULL; n++)
        printf("%s ", g->gr_name);
    endgrent();
    printf("(%d)\n", n);
    step("getpwuid(getuid())"); p = getpwuid(getuid()); said(p ? p->pw_name : NULL);
    step("getpwnam(\"root\")"); p = getpwnam("root"); said(p ? p->pw_name : NULL);
    step("setpwent/getpwent/endpwent");
    setpwent();
    for (n = 0; n < 8 && (p = getpwent()) != NULL; n++)
        printf("%s ", p->pw_name ? p->pw_name : "?");
    endpwent();
    printf("(%d)\n", n);
    step("getgroups");
    n = getgroups(32, list);
    printf("%d\n", n);
    printf("usergroup: ALL RETURNED\n");
    return 0;
}
