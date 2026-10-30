#!/bin/sh
# Original plugin authors retain all rights. APanel distribution wrapper only.
set -eu
[ "$(id -u)" -eq 0 ] && command -v opkg >/dev/null 2>&1 || { echo 'A root Enigma2 / opkg image is required.'; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo 'Python 3 is required.'; exit 1; }
stage=$(mktemp -d /tmp/apanel-plugin.XXXXXX)
trap 'rm -f "$stage/package.b64" "$stage/plugin.ipk"; rmdir "$stage" 2>/dev/null || :' EXIT
wget -qO "$stage/package.b64" 'https://raw.githubusercontent.com/hhawwas7/APanel/main/plugins/hisnmuslim/hisnmuslim-v1.ipk.b64' || exit 1
python3 - "$stage" <<'VERIFY_PLUGIN'
import base64, hashlib, io, pathlib, sys, tarfile
if sys.version_info < (3, 9):
    raise SystemExit('This plugin requires a Python 3.9+ image.')
root = pathlib.Path(sys.argv[1])
data = base64.b64decode((root/'package.b64').read_bytes(), validate=False)
if hashlib.sha256(data).hexdigest() != '4df373f17de6107618ae052945a3327e2494cf1bfe5eaf5806628a458e287500':
    raise SystemExit('Plugin checksum mismatch; installation cancelled.')
if not data.startswith(b'!<arch>\n'):
    raise SystemExit('Invalid plugin package.')
offset = 8
while offset < len(data):
    header = data[offset:offset+60]
    size = int(header[48:58]); content = data[offset+60:offset+60+size]
    offset += 60 + size + size % 2
    if header[:16].startswith(b'data.tar'):
        with tarfile.open(fileobj=io.BytesIO(content)) as archive:
            for member in archive:
                if member.isfile() and member.name.endswith('.py'):
                    compile(archive.extractfile(member).read(), member.name, 'exec')
(root/'plugin.ipk').write_bytes(data)
VERIFY_PLUGIN
if [ -z "${APANEL_PROFILE:-}" ]; then opkg update || :; fi
opkg install --force-reinstall "$stage/plugin.ipk"
echo 'HisnMuslim installed. Restart the GUI from the image menu when ready.'
