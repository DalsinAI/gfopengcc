#!/usr/bin/env python3
"""Two fresh, socket-disabled AmigaOS builds in one fixed absolute path.

Usage: reproduce-offline.py RECORD_ROOT LOCAL_MIRROR NDK_LHA [JOBS]
RECORD_ROOT must not exist. All input commits are frozen before either build.
The script preserves both installed prefixes, logs, packages and a comparison.
GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team.
"""
import ctypes
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import resource
import shutil
import socket
import stat
import subprocess
import sys
import time


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def offline():
    # A sandbox can forbid unshare while still allowing a more restrictive
    # seccomp filter. This filter is inherited across fork/exec, with no root,
    # network-namespace changes, proxies, or external-service exceptions.
    library = ctypes.CDLL("libseccomp.so.2", use_errno=True)
    library.seccomp_init.argtypes = [ctypes.c_uint32]
    library.seccomp_init.restype = ctypes.c_void_p
    library.seccomp_rule_add.argtypes = [ctypes.c_void_p, ctypes.c_uint32,
                                         ctypes.c_int, ctypes.c_uint]
    library.seccomp_syscall_resolve_name.argtypes = [ctypes.c_char_p]
    library.seccomp_syscall_resolve_name.restype = ctypes.c_int
    library.seccomp_load.argtypes = [ctypes.c_void_p]
    context = library.seccomp_init(0x7FFF0000)  # SCMP_ACT_ALLOW
    if not context:
        raise RuntimeError("cannot allocate offline seccomp context")
    for name in (b"socket", b"connect"):
        number = library.seccomp_syscall_resolve_name(name)
        result = library.seccomp_rule_add(context, 0x50000 | errno.ENETDOWN,
                                          number, 0)
        if result:
            raise RuntimeError(f"cannot install offline {name!r} rule: {result}")
    result = library.seccomp_load(context)
    if result:
        raise RuntimeError(f"cannot activate offline filter: {result}")
    for family in (socket.AF_INET, socket.AF_INET6):
        try:
            socket.socket(family, socket.SOCK_STREAM)
        except OSError as error:
            if error.errno != errno.ENETDOWN:
                raise
        else:
            raise RuntimeError("offline filter did not block socket creation")


def manifest(root):
    result = {}
    for directory, dirs, files in os.walk(root):
        for name in sorted(dirs + files):
            path = Path(directory) / name
            relative = str(path.relative_to(root))
            mode = stat.S_IMODE(path.lstat().st_mode)
            if path.is_symlink():
                result[relative] = {"type": "link", "mode": mode,
                                    "target": os.readlink(path)}
            elif path.is_file():
                result[relative] = {"type": "file", "mode": mode,
                                    "size": path.stat().st_size, "sha256": sha(path)}
            elif path.is_dir():
                result[relative] = {"type": "directory", "mode": mode}
            else:
                raise RuntimeError(f"unexpected installed file type: {path}")
    return result


def main():
    if len(sys.argv) not in (4, 5):
        sys.exit(__doc__)
    root = Path(sys.argv[1]).resolve()
    mirror = Path(sys.argv[2]).resolve()
    ndk = Path(sys.argv[3]).resolve()
    jobs = int(sys.argv[4]) if len(sys.argv) == 5 else 8
    source = Path(__file__).resolve().parent.parent
    if root.exists() or jobs < 1:
        sys.exit("use a new record directory and a positive job count")
    if subprocess.check_output(["git", "status", "--porcelain"], cwd=source).strip():
        sys.exit("commit the orchestration repository before freezing its input")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source,
                                     text=True).strip()
    epoch = subprocess.check_output(["git", "show", "-s", "--format=%ct", "HEAD"],
                                    cwd=source, text=True).strip()
    root.mkdir()
    lock = (root / "campaign.lock").open("w")
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    os.umask(0o022)
    state = {"status": "preparing", "orchestration_commit": commit,
             "source_date_epoch": epoch, "jobs": jobs, "runs": [],
             "mirror": str(mirror), "ndk_sha256": sha(ndk),
             "network": "inherited seccomp: socket/connect return ENETDOWN"}

    def save():
        temporary = root / "status.json.new"
        temporary.write_text(json.dumps(state, indent=2) + "\n")
        temporary.replace(root / "status.json")

    environment = os.environ.copy()
    for key in ("http_proxy", "https_proxy", "all_proxy", "HTTP_PROXY",
                "HTTPS_PROXY", "ALL_PROXY", "GCC_EXEC_PREFIX", "COMPILER_PATH",
                "LIBRARY_PATH", "CPATH", "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH",
                "TMPDIR", "LIBNIX_PATCHES", "TAR_OPTIONS", "OUT"):
        environment.pop(key, None)
    environment.update(SOURCE_DATE_EPOCH=epoch, TZ="UTC", LC_ALL="C", LANG="C",
                       PYTHONHASHSEED="0", CCACHE_DISABLE="1", GIT_TERMINAL_PROMPT="0",
                       GIT_ALLOW_PROTOCOL="file")
    work = root / "work"
    prefix = root / "prefix"
    orchestration = root / "orchestration"

    def command(label, args, log, extra=None):
        state["stage"] = label
        state["stage_started"] = time.time()
        save()
        print(f"[{time.strftime('%H:%M:%S')}] {label}: {log}", flush=True)
        env = environment | (extra or {})
        with log.open("w") as output:
            output.write("command: " + json.dumps(list(map(str, args))) + "\n")
            output.flush()
            completed = subprocess.run(list(map(str, args)), cwd=orchestration
                                       if orchestration.is_dir() else root,
                                       env=env, stdout=output, stderr=subprocess.STDOUT)
        if completed.returncode:
            raise RuntimeError(f"{label} failed ({completed.returncode}); see {log}")

    save()
    try:
        offline()
        state["offline_probe_passed"] = True
        save()
        command("freeze orchestration", ["git", "clone", "--local", "--no-checkout",
                                         source, orchestration], root / "freeze.log")
        command("select frozen commit", ["git", "-C", orchestration, "checkout",
                                         "--detach", commit], root / "checkout.log")
        locked_ndk = (orchestration / "scripts/ndk.lock").read_text().splitlines()
        expected_ndk = next(line.split()[2] for line in locked_ndk
                            if line and not line.startswith("#"))
        if expected_ndk != state["ndk_sha256"]:
            raise RuntimeError("local NDK does not match scripts/ndk.lock")
        for number in (1, 2):
            if shutil.disk_usage(root).free < 12 * 1024**3:
                raise RuntimeError("less than 12 GiB free before a fresh build")
            if work.exists() or prefix.exists():
                raise RuntimeError("fresh build paths are unexpectedly populated")
            record = root / f"run-{number}"
            record.mkdir()
            run = {"number": number, "status": "preparing", "started": time.time()}
            state["runs"].append(run)
            state["status"] = "running"
            command(f"run {number}: fresh pinned sources",
                    ["bash", orchestration / "scripts/fetch.sh", work, mirror],
                    record / "sources.log")
            heads = []
            for line in (orchestration / "scripts/sources.lock").read_text().splitlines():
                if not line or line.startswith("#"):
                    continue
                name, url, expected, relative = line.split()
                actual = subprocess.check_output(["git", "-C", str(work / relative),
                                                   "rev-parse", "HEAD"], text=True).strip()
                dirty = subprocess.check_output(["git", "-C", str(work / relative),
                                                  "status", "--porcelain", "--untracked-files=no"])
                if actual != expected or dirty.strip():
                    raise RuntimeError(f"{name}: source is not pristine at {expected}")
                heads.append({"name": name, "commit": actual, "url": url})
            (record / "source-heads.json").write_text(json.dumps(heads, indent=2) + "\n")
            run["source_count"] = len(heads)
            run["empty_build_tree"] = not list(work.glob("build-*"))
            run["empty_prefix"] = not prefix.exists()
            if not run["empty_build_tree"] or not run["empty_prefix"]:
                raise RuntimeError("clean-build precondition failed")
            run["status"] = "building"
            command(f"run {number}: full offline build",
                    ["bash", orchestration / "scripts/build.sh", work, prefix, ndk, jobs],
                    record / "build.log")
            run["status"] = "regression"
            binary = prefix / "bin"
            temporary = work / ".gfopenamigagcc-tmp"
            environment["TMPDIR"] = str(temporary)
            tests = [
                ("repro", ["bash", "tests/repro/prove.sh", binary]),
                ("repro-no-loop-distribute", ["bash", "tests/repro/prove.sh", binary,
                                               "-fno-tree-loop-distribute-patterns"]),
                ("optimizer", ["bash", "tests/optimizer/check.sh", binary]),
                ("optimizer-fuzz", ["python3", "tests/optimizer/fuzz.py", binary, "12"]),
                ("ubsan-trap", ["python3", "tests/ubsan-trap/check.py", binary]),
                ("autoinc", ["bash", "tests/autoinc/check.sh", "--amigaos", binary]),
                ("libnix-endptr", ["bash", "tests/libnix/endptr/run.sh", binary]),
                ("lean-cxx", ["bash", "tests/cxx/lean-check.sh"]),
                ("baserel-eh", ["bash", "tests/baserel/eh-check.sh", prefix]),
            ]
            for label, args in tests:
                command(f"run {number}: {label}", args, record / f"{label}.log",
                        {"OUT": str(record / label),
                         "CXX": str(binary / "m68k-amigaos-g++"),
                         "NM": str(binary / "m68k-amigaos-nm")})
            run["status"] = "packaging"
            # The build's temporary directory contains host scratch files,
            # not source inputs. Keep it out of source archives by clearing
            # our own scratch directory after all compiler processes finish.
            shutil.rmtree(temporary)
            temporary.mkdir()
            normalization = f"--sort=name --mtime=@{epoch} --owner=0 --group=0 --numeric-owner"
            command(f"run {number}: package",
                    ["bash", "scripts/package.sh", work, prefix, record / "packages",
                     "16.2.0-open7"], record / "package.log", {"TAR_OPTIONS": normalization})
            entries = manifest(prefix)
            (record / "prefix-manifest.json").write_text(json.dumps(entries, sort_keys=True,
                                                                     indent=2) + "\n")
            run["installed_entries"] = len(entries)
            run["status"] = "passed"
            run["finished"] = time.time()
            shutil.copytree(work / "gfopenamigagcc-logs", record / "build-checks")
            prefix.rename(record / "prefix")
            save()
            # Only this campaign's generated trees are removed. Mirror,
            # earlier integration builds, logs, packages and prefix snapshots
            # remain untouched. The next run starts from fresh Git checkouts.
            shutil.rmtree(work)
            environment.pop("TMPDIR", None)
        state["stage"] = "compare"
        save()
        first = json.loads((root / "run-1/prefix-manifest.json").read_text())
        second = json.loads((root / "run-2/prefix-manifest.json").read_text())
        differences = [{"path": path, "run_1": first.get(path), "run_2": second.get(path)}
                       for path in sorted(first.keys() | second.keys())
                       if first.get(path) != second.get(path)]
        packages = []
        for path in sorted((root / "run-1/packages").glob("*.tar.xz")):
            peer = root / "run-2/packages" / path.name
            packages.append({"name": path.name, "run_1_sha256": sha(path),
                             "run_2_sha256": sha(peer), "identical": sha(path) == sha(peer)})
        comparison = {"prefix_differences": differences, "packages": packages,
                      "prefix_identical": not differences,
                      "packages_identical": bool(packages) and all(p["identical"] for p in packages)}
        (root / "comparison.json").write_text(json.dumps(comparison, indent=2) + "\n")
        state["status"] = "passed" if not differences and comparison["packages_identical"] else "different"
        save()
        print(f"offline reproducibility: {state['status']}; {root / 'comparison.json'}", flush=True)
        return 0 if state["status"] == "passed" else 1
    except BaseException as error:
        state["status"] = "failed"
        state["error"] = str(error)
        save()
        raise


if __name__ == "__main__":
    sys.exit(main())
