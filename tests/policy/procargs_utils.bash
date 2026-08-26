# Shared helpers for tests that read a target process's argv/env via procargs sysctls.

# Emits a Python helper that reads a target process's argv+env via a procargs sysctl and
# prints the raw bytes.
# argv[1] selects the sysctl: KERN_PROCARGS (38) or KERN_PROCARGS2 (49).
# argv[2] is the target pid.
#
# ("obvious" alternatives which don't work: the shell's `sysctl` is unable to make
# the pid-parameterized call, and `ps` is refused with the default safehouse profile).
#
# Two constraints on the target process these read from:
#  - It must outlive the whole test. Inside a sandbox a dead pid fails the sysctl with
#    EPERM, not the EINVAL you get unsandboxed, which is indistinguishable from a policy
#    denial and turns the deny-side assertions into false passes.
#  - It must not be an Apple-signed system binary (/bin/sh, perl, ruby): those are
#    restricted under SIP, so procargs returns their argv but withholds their
#    environment. python3, already required by these tests, is not restricted.
export KERN_PROCARGS=38
export KERN_PROCARGS2=49
sft_procargs_reader_py() {
  cat <<EOF
import ctypes, sys
CTL_KERN = 1
libc = ctypes.CDLL(None, use_errno=True)

def _sysctl(mib_vals, buf, size):
    mib = (ctypes.c_int * len(mib_vals))(*mib_vals)
    oldlen = ctypes.c_size_t(size)
    rc = libc.sysctl(mib, len(mib_vals), buf, ctypes.byref(oldlen), None, ctypes.c_size_t(0))
    return rc, oldlen.value

selector = int(sys.argv[1])
assert selector in ($KERN_PROCARGS, $KERN_PROCARGS2), selector
pid = int(sys.argv[2])
buf = ctypes.create_string_buffer(16384)
rc, got = _sysctl([CTL_KERN, selector, pid], buf, ctypes.sizeof(buf))
if rc != 0:
    sys.stderr.write("PROCARGS_ERRNO sel=%d errno=%d\n" % (selector, ctypes.get_errno()))
    sys.exit(1)
sys.stdout.buffer.write(buf.raw[:got])
EOF
}
