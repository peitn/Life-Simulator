#!/usr/bin/env python3
"""Test-only per-worker stdout/stderr capture, preserving the child PID via exec."""
import os
import sys

if len(sys.argv) < 4:
    raise SystemExit(64)
log_path, executable = sys.argv[1:3]
fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0), 0o600)
try:
    os.dup2(fd, 1)
    os.dup2(fd, 2)
finally:
    if fd > 2:
        os.close(fd)
os.execv(executable, [executable] + sys.argv[3:])
