#!/bin/sh
# Original plugin authors retain all rights. APanel distribution wrapper only.
set -eu
[ "$(id -u)" -eq 0 ] && command -v opkg >/dev/null 2>&1 || { echo 'A root Enigma2 / opkg image is required.'; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo 'Python 3 is required.'; exit 1; }
stage=$(mktemp -d /tmp/apanel-plugin.XXXXXX)
trap 'rm -f "$stage/package.b64" "$stage/plugin.ipk" "$stage/reciters.b64"; rmdir "$stage" 2>/dev/null || :' EXIT
wget -qO "$stage/package.b64" 'https://raw.githubusercontent.com/hhawwas7/APanel/main/plugins/ansite/ansite-1.12.py3.ipk.b64' || exit 1
python3 - "$stage" <<'VERIFY_PLUGIN'
import base64, hashlib, io, pathlib, sys, tarfile
if sys.version_info < (3, 9):
    raise SystemExit('This plugin requires a Python 3.9+ image.')
root = pathlib.Path(sys.argv[1])
data = base64.b64decode((root/'package.b64').read_bytes(), validate=False)
if hashlib.sha256(data).hexdigest() != '13dce017e310578c8552db55e5e5eece968ea641630ed9a597b5a034fba44c2b':
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
opkg install python3-beautifulsoup4
if ! python3 -c 'from bs4 import BeautifulSoup' 2>/dev/null; then
    opkg install --force-reinstall python3-beautifulsoup4
fi
python3 -c 'from bs4 import BeautifulSoup'
wget -qO "$stage/reciters.b64" 'https://raw.githubusercontent.com/hhawwas7/APanel/main/plugins/ansite/all-reciters-surahs-v1.zip.b64'
python3 - "$stage/reciters.b64" <<'CHECK_RECITERS'
import base64,hashlib,io,json,pathlib,sys,zipfile
data=base64.b64decode(pathlib.Path(sys.argv[1]).read_bytes())
if hashlib.sha256(data).hexdigest()!='3c2e53b488cdba7f2f8ca511fc697ff2d6d2aa5bf8536a6641cfb4edc0e24c4d':
    raise SystemExit('Reciter database checksum mismatch; installation cancelled.')
with zipfile.ZipFile(io.BytesIO(data)) as archive:
    value=json.loads(archive.read('all_reciters_surahs.json'))
    if not isinstance(value.get('reciters'),list):raise SystemExit('Invalid reciter data.')
CHECK_RECITERS
ansite=/usr/lib/enigma2/python/Plugins/Extensions/Ansite
[ ! -L "$ansite" ] || { echo 'Ansite is a symlink; installation cancelled.'; exit 1; }
if [ -d "$ansite" ]; then
    backup=$(mktemp -d /home/root/apanel-ansite-backup.XXXXXX)
    chmod 700 "$backup"
    cp -a "$ansite" "$backup/"
    echo "Existing Ansite backup: $backup"
fi
opkg install --force-reinstall "$stage/plugin.ipk"
[ -f "$ansite/plugin.py" ] || { echo 'Ansite program is missing.'; exit 1; }
python3 - "$stage/reciters.b64" "$ansite" <<'INSTALL_RECITERS'
import base64,io,json,os,pathlib,sys,zipfile
target=pathlib.Path(sys.argv[2])/'Adons'/'XML'
for path in (pathlib.Path(sys.argv[2]), target.parent, target):
    if path.is_symlink():raise SystemExit('Reciter destination is a symlink; preserved.')
with zipfile.ZipFile(io.BytesIO(base64.b64decode(pathlib.Path(sys.argv[1]).read_bytes()))) as archive:
    data=archive.read('all_reciters_surahs.json')
json.loads(data)
target.mkdir(parents=True,exist_ok=True)
destination=target/'all_reciters_surahs.json'
if destination.is_symlink():raise SystemExit('Existing reciter file is a symlink; preserved.')
temporary=target/('all_reciters_surahs.json.apanel-'+str(os.getpid()))
temporary.write_bytes(data)
os.replace(str(temporary),str(destination))
print('Ansite reciter database installed.')
INSTALL_RECITERS
echo 'Ansite installed. Restart the GUI from the image menu when ready.'
