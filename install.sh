#!/bin/sh
# APanel installation bootstrap. Copyright Mr. H.HAWWAS.
# The program is distributed as a separate packaged payload.

VERSION=v0.4.34
PACKAGE_URL=https://raw.githubusercontent.com/hhawwas7/APanel/main/dist/apanel-v0.4.34.dat
PACKAGE_SHA256=777253887fcd0feff4fa80ce4da188efd410db643b9ea6ccdba74d9c03fc0ab7

if [ "$(id -u)" -ne 0 ] || ! command -v opkg >/dev/null 2>&1; then
    echo 'ERROR: A root Enigma2 image with opkg is required.'
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import sys; sys.exit(sys.version_info < (3,9))'; then
    echo 'ERROR: Python 3.9 or newer is required.'
    exit 1
fi
APANEL_SETUP_DIR=$(mktemp -d /tmp/apanel-setup.XXXXXX) || exit 1
case "$APANEL_SETUP_DIR" in /tmp/apanel-setup.*) : ;; *) exit 1 ;; esac
trap 'rm -f "$APANEL_SETUP_DIR/package.dat" "$APANEL_SETUP_DIR/runtime.sh"; rmdir "$APANEL_SETUP_DIR" 2>/dev/null || true' 0
trap 'exit 1' HUP INT TERM

echo "A Panel $VERSION: downloading installation package..."
if ! wget -q -O "$APANEL_SETUP_DIR/package.dat" "$PACKAGE_URL"; then
    echo 'ERROR: Installation package download failed.'
    exit 1
fi
if ! python3 - "$APANEL_SETUP_DIR/package.dat" "$APANEL_SETUP_DIR/runtime.sh" "$PACKAGE_SHA256" <<'APANEL_UNPACK'
import base64, gzip, hashlib, os, sys
try:
    with open(sys.argv[1], 'rb') as stream:
        archive = base64.b64decode(b''.join(stream.read().split()), validate=True)
    if hashlib.sha256(archive).hexdigest() != sys.argv[3]:
        raise ValueError('installation package checksum mismatch')
    program = gzip.decompress(archive)
    if not program.startswith(b'#!/bin/sh\n') or not program.endswith(b'exit 0\n'):
        raise ValueError('invalid installation package')
    with open(sys.argv[2], 'wb') as stream:
        stream.write(program)
    os.chmod(sys.argv[2], 0o600)
except Exception as error:
    print('ERROR: %s' % error, file=sys.stderr)
    sys.exit(1)
APANEL_UNPACK
then
    exit 1
fi
if ! /bin/sh -n "$APANEL_SETUP_DIR/runtime.sh"; then
    echo 'ERROR: Installation package syntax check failed.'
    exit 1
fi
/bin/sh "$APANEL_SETUP_DIR/runtime.sh" "$@"
APANEL_SETUP_STATUS=$?
exit "$APANEL_SETUP_STATUS"
