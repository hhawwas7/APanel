#!/bin/sh
# Original plugin authors retain all rights. APanel distribution wrapper only.
set -eu
[ "$(id -u)" -eq 0 ] && command -v opkg >/dev/null 2>&1 || { echo 'A root Enigma2 / opkg image is required.'; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo 'Python 3 is required.'; exit 1; }
stage=$(mktemp -d /tmp/apanel-plugin.XXXXXX)
trap 'rm -f "$stage/package.b64" "$stage/plugin.ipk"; rmdir "$stage" 2>/dev/null || :' EXIT
wget -qO "$stage/package.b64" 'https://raw.githubusercontent.com/hhawwas7/APanel/main/plugins/iqraaquran/iqraaquran-1.3-source.ipk.b64' || exit 1
python3 - "$stage" <<'VERIFY_PLUGIN'
import base64, hashlib, io, pathlib, sys, tarfile
if sys.version_info < (3, 9):
    raise SystemExit('This plugin requires a Python 3.9+ image.')
root = pathlib.Path(sys.argv[1])
data = base64.b64decode((root/'package.b64').read_bytes(), validate=False)
if hashlib.sha256(data).hexdigest() != 'cc59eae2ace80ec791f727e7acf11f7db3e32e2eeda9097dbe9551f261b54e36':
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
echo 'IqraaQuran installed. Restart the GUI from the image menu when ready.'
