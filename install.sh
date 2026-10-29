#!/bin/sh
# A Panel v0.4.1 - OpenATV Enigma2 TV installer / uninstaller
# OpenATV / opkg only. GSH2 is intentionally excluded.
# Third-party installers run as root.

export PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH

VERSION=v0.4.1
ROOT=/home/root
CORE=$ROOT/apanel-core.sh
PLUG=/usr/lib/enigma2/python/Plugins/Extensions/APanel
CHOICES=$ROOT/apanel-choices.txt
PROGRESS=$ROOT/apanel-progress.log
LOG=$ROOT/apanel-task.log
READY=/tmp/apanel-ui-ready
REQUEST=/tmp/apanel-ui-request
PIDFILE=/tmp/apanel-task.pid
MODEFILE=/tmp/apanel-task.mode

say() {
    printf '%s\n' "$*"
}

report() {
    say "$*" | tee -a "$PROGRESS"
}

bar() {
    [ "$TOTAL" -gt 0 ] || TOTAL=1
    PC=$((DONE*100/TOTAL))
    FILLED=$((DONE*20/TOTAL))
    B=''
    I=0
    while [ "$I" -lt 20 ]; do
        if [ "$I" -lt "$FILLED" ]; then
            B="${B}#"
        else
            B="${B}-"
        fi
        I=$((I+1))
    done
    report "PROGRESS [$B] $PC% | $DONE/$TOTAL | OK:$OK CHECK:$CHECK FAILED:$FAIL"
}

pulse() {
    while :; do
        sleep 20
        report "... $1 still running"
    done
}

step() {
    NUM=$((NUM+1))
    LABEL=$1
    shift

    report "[$NUM/$TOTAL] START: $LABEL"
    pulse "$LABEL" &
    HB=$!

    "$@"
    RC=$?

    kill "$HB" 2>/dev/null || :
    wait "$HB" 2>/dev/null || :

    DONE=$((DONE+1))

    case "$RC" in
        0)
            OK=$((OK+1))
            report "[$NUM/$TOTAL] OK: $LABEL"
            ;;
        2)
            CHECK=$((CHECK+1))
            report "[$NUM/$TOTAL] CHECK: $LABEL (manual review may be needed)"
            ;;
        *)
            FAIL=$((FAIL+1))
            report "[$NUM/$TOTAL] FAILED ($RC): $LABEL"
            ;;
    esac
    bar
}

remote() {
    URL=$1
    FILE=/tmp/apanel-remote-$$.sh
    rm -f "$FILE"
    if ! wget -qO "$FILE" "$URL" || [ ! -s "$FILE" ]; then
        say "Download failed: $URL"
        rm -f "$FILE"
        return 1
    fi
    /bin/sh "$FILE"
    RC=$?
    rm -f "$FILE"
    return "$RC"
}

count_words() {
    set -- $1
    echo $#
}

pkg_installed() {
    opkg list-installed 2>/dev/null | awk '{print $1}' | grep -Fxq "$1"
}

opkg_remove_pkg() {
    PKG=$1
    pkg_installed "$PKG" || return 0
    opkg remove "$PKG" || return 1
    return 0
}

install_transmission_bundle() {
    opkg install transmission transmission-client python3-transmission-rpc xz || return 1
    opkg install python3-beautifulsoup4 python3-yt-dlp || true
    remote http://dreambox4u.com/dreamarabia/Transmission_e2/Transmission_e2.sh || return 1
    return 0
}

install_xstreamity() {
    opkg list | awk '$1=="enigma2-plugin-extensions-xstreamity" {f=1} END {exit !f}' || return 1
    opkg install enigma2-plugin-extensions-xstreamity || return 1
    pkg_installed enigma2-plugin-extensions-xstreamity
}

install_epggrabber() {
    remote https://raw.githubusercontent.com/zKhadiri/Epg-plugin/master/Download/installer.sh || return 1
    [ -d /usr/lib/enigma2/python/Plugins/Extensions/EPGGrabber ]
}

install_ncam() {
    remote https://raw.githubusercontent.com/biko-73/Ncam_EMU/main/installer.sh || return 1
    opkg list-installed | grep -q '^enigma2-plugin-softcams-ncam '
}

install_ipaudio() {
    command -v ffmpeg >/dev/null 2>&1 || opkg install ffmpeg || return 1
    MAJOR=$(ffmpeg -version 2>/dev/null | awk 'NR==1 {split($3,a,"."); print a[1]}')
    case "$MAJOR" in
        7|8)
            remote https://raw.githubusercontent.com/zKhadiri/IPAudioPro-Releases-/main/installer.sh
            return $?
            ;;
        9)
            say 'FFmpeg 9: using upstream FFmpeg 8 build; runtime compatibility not guaranteed'
            ;;
        *)
            say "Unsupported FFmpeg $MAJOR"
            return 1
            ;;
    esac
    PY=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])') || return 1
    case "$PY" in
        3.12) FF=7.1 ;;
        3.13|3.14) FF=8.0 ;;
        *) return 1 ;;
    esac
    case "$(uname -m)" in
        aarch64)
            DIR=aarch64
            ARCH=aarch64
            ;;
        *mips*)
            DIR=mipsel
            ARCH=mips32el
            ;;
        arm*)
            DIR=arm
            ARCH=''
            for A in cortexa15hf-neon-vfpv4 cortexa9hf-neon cortexa7hf-vfp armv7ahf-neon; do
                if opkg print-architecture 2>/dev/null | grep -q " $A " || ls /etc/opkg 2>/dev/null | grep -q "$A"; then
                    ARCH=$A
                    break
                fi
            done
            [ -n "$ARCH" ] || return 1
            ;;
        *)
            return 1
            ;;
    esac
    META=/tmp/apanel-ipaudio-meta-$$.sh
    wget -qO "$META" https://raw.githubusercontent.com/zKhadiri/IPAudioPro-Releases-/main/installer.sh || return 1
    VER=$(sed -n 's/^VERSION=\([0-9][0-9.]*\).*$/\1/p' "$META" | head -n 1)
    rm -f "$META"
    [ -n "$VER" ] || return 1
    PKG="enigma2-plugin-extensions-ipaudiopro_${VER}_${ARCH}_py${PY}_ff${FF}.ipk"
    URL="https://raw.githubusercontent.com/zKhadiri/IPAudioPro-Releases-/main/v${VER}/python${PY}/${DIR}/${PKG}"
    IPK=/tmp/apanel-ipaudio-$$.ipk
    if ! wget -qO "$IPK" "$URL" || [ ! -s "$IPK" ]; then
        rm -f "$IPK"
        return 1
    fi
    opkg install "$IPK"
    RC=$?
    rm -f "$IPK"
    [ "$RC" -eq 0 ] || return "$RC"
    opkg list-installed | grep -q '^enigma2-plugin-extensions-ipaudiopro '
}

install_levi() {
    URL=https://raw.githubusercontent.com/levi-45/Levi45Emulator/main/enigma2-plugin-softcams-oscam-emu-pcsc-levi45_11968-803_all.ipk
    IPK=/tmp/apanel-levi-$$.ipk
    if ! wget -qO "$IPK" "$URL" || [ ! -s "$IPK" ]; then
        rm -f "$IPK"
        return 1
    fi
    opkg install --force-overwrite "$IPK"
    RC=$?
    rm -f "$IPK"
    say "Levi45 opkg exit status: $RC"
    INSTALLED=$(opkg list-installed | grep -Ei '^enigma2-plugin[^ ]*oscam[^ ]*levi[^ ]* - ' | head -n 1)
    if [ -n "$INSTALLED" ]; then
        [ "$RC" -eq 0 ] && return 0
        return 2
    fi
    [ -x /usr/bin/OSCam_11968-803 ] && return 2
    return 1
}

install_audioshift() {
    remote https://xfayez95.github.io/audioshift/installer.sh
}

install_mystreamer() {
    remote https://raw.githubusercontent.com/popking159/MyStreamer/refs/heads/main/myinstaller.sh
}

install_furybiss() {
    remote https://raw.githubusercontent.com/islam-2412/FuryBiss/refs/heads/main/fury/installer.sh
}

install_movies_ostende() {
    URL='http://dreambox4u.com/dreamarabia/Transmission_e2/MoviesManager.sh'
    FILE=/tmp/apanel-movies-$$.sh
    rm -f "$FILE"
    if ! wget -q --no-check-certificate -O "$FILE" "$URL" || [ ! -s "$FILE" ]; then
        rm -f "$FILE"
        return 1
    fi
    bash "$FILE"
    RC=$?
    rm -f "$FILE"
    return "$RC"
}

install_plugin_key() {
    case "$1" in
        aj)
            remote https://raw.githubusercontent.com/biko-73/AjPanel/main/installer.sh ;;
        subs)
            remote https://raw.githubusercontent.com/popking159/SubsSupportPro/refs/heads/main/myinstaller.sh ;;
        transmission)
            install_transmission_bundle ;;
        tmdb)
            remote https://raw.githubusercontent.com/biko-73/TMBD/main/installer.sh ;;
        arabicsavior)
            remote https://raw.githubusercontent.com/fairbird/ArabicSavior/main/installer.sh ;;
        raed)
            remote https://raw.githubusercontent.com/fairbird/RaedQuickSignal/main/installer.sh ;;
        audioshift)
            install_audioshift ;;
        ipaudio)
            install_ipaudio ;;
        customcs)
            remote https://raw.githubusercontent.com/popking159/customchannelselection/refs/heads/main/myinstaller.sh ;;
        aglare)
            remote https://raw.githubusercontent.com/popking159/skins/refs/heads/main/aglareatv/installer.sh ;;
        livefeed)
            remote https://live-feed.net/enigma2/installer.sh ;;
        epggrabber)
            install_epggrabber ;;
        xstreamity)
            install_xstreamity ;;
        mixaudio)
            remote https://raw.githubusercontent.com/Najar1991/MixAudio_All/refs/heads/main/install.sh ;;
        ncam)
            install_ncam ;;
        oscamlevi)
            install_levi ;;
        mystreamer)
            install_mystreamer ;;
        furybiss)
            install_furybiss ;;
        moviesostende)
            install_movies_ostende ;;
        *)
            return 1 ;;
    esac
}

remove_plugin_key() {
    # Only package names verified against upstream installers are enabled.
    # Keep configurations and shared data untouched in this first field trial.
    case "$1" in
        mystreamer)
            if pkg_installed enigma2-plugin-extensions-mystreamer; then
                opkg_remove_pkg enigma2-plugin-extensions-mystreamer || return 1
                report 'MyStreamer package removed. Personal settings kept.'
                return 0
            fi
            report 'CHECK: MyStreamer package not found; no files removed.'
            return 2
            ;;
        furybiss)
            FOUND=0
            for P in enigma2-plugin-extensions-furybiss enigma2-plugin-extensions-furybis; do
                if pkg_installed "$P"; then
                    FOUND=1
                    opkg_remove_pkg "$P" || return 1
                fi
            done
            [ "$FOUND" -eq 1 ] || {
                report 'CHECK: FuryBiss package not found; no files removed.'
                return 2
            }
            report 'FuryBiss package removed. Personal settings kept.'
            return 0
            ;;
        xstreamity)
            if pkg_installed enigma2-plugin-extensions-xstreamity; then
                opkg_remove_pkg enigma2-plugin-extensions-xstreamity || return 1
                report 'XStreamity package removed. Playlists/settings kept.'
                return 0
            fi
            report 'CHECK: XStreamity package not found; no files removed.'
            return 2
            ;;
        ncam)
            if pkg_installed enigma2-plugin-softcams-ncam; then
                opkg_remove_pkg enigma2-plugin-softcams-ncam || return 1
                report 'NCam package removed. Cam configs/keys preserved pending ownership review.'
                return 0
            fi
            report 'CHECK: NCam package not found; no files removed.'
            return 2
            ;;
        oscamlevi)
            if pkg_installed enigma2-plugin-softcams-oscam-emu-pcsc-levi45; then
                opkg_remove_pkg enigma2-plugin-softcams-oscam-emu-pcsc-levi45 || return 1
                report 'OSCam Levi45 package removed. Shared configs/keys preserved.'
                return 0
            fi
            report 'CHECK: OSCam Levi45 package not found; no files removed.'
            return 2
            ;;
        *)
            report "CHECK: uninstall mapping for $1 not verified; no files removed."
            return 2
            ;;
    esac
}

run_mode() {
    MODE=$1
    [ -r "$CHOICES" ] || {
        say 'No plugin selection.'
        return 1
    }

    SELECTED=$(tr '\n' ' ' < "$CHOICES")
    COUNT=$(count_words "$SELECTED")
    TOTAL=$((COUNT + 1))
    NUM=0
    DONE=0
    OK=0
    CHECK=0
    FAIL=0

    : > "$PROGRESS"
    echo "$MODE" > "$MODEFILE"

    if [ "$MODE" = install ]; then
        report "A Panel $VERSION | Install mode | $TOTAL steps"
        step 'Update OpenATV feed' opkg update
        # FuryBiss upstream restarts Enigma2 GUI; run it last in the batch.
        for K in $SELECTED; do
            [ "$K" = furybiss ] && continue
            NAME=$(plugin_name "$K")
            [ -n "$NAME" ] || continue
            step "$NAME" install_plugin_key "$K"
        done
        case " $SELECTED " in
            *' furybiss '*) step 'FuryBiss' install_plugin_key furybiss ;;
        esac
        report '=== INSTALL FINISHED ==='
        report 'Full receiver reboot in 5 seconds.'
    else
        report "A Panel $VERSION | Uninstall mode | $TOTAL steps"
        step 'Refresh package status' true
        for K in $SELECTED; do
            NAME=$(plugin_name "$K")
            [ -n "$NAME" ] || continue
            step "Remove $NAME" remove_plugin_key "$K"
        done
        report '=== UNINSTALL PASS COMPLETE (CHECK means skipped) ==='
        report 'Restarting Enigma2 in 5 seconds (verified removals only).'
    fi

    bar
    report "Results: OK=$OK CHECK=$CHECK FAILED=$FAIL"
    report "Full log: $LOG"

    sync
    sleep 5
    rm -f "$PIDFILE"
    if [ "$MODE" = install ]; then
        reboot
    else
        init 4
        sleep 3
        init 3
    fi
}

plugin_name() {
    case "$1" in
        aj) echo 'AJ Panel' ;;
        subs) echo 'SubsSupport Pro' ;;
        transmission) echo 'Transmission' ;;
        tmdb) echo 'TMDB' ;;
        arabicsavior) echo 'Arabic Savior' ;;
        raed) echo 'Raed Quick Signal' ;;
        audioshift) echo 'AudioShift (Dreambox One only)' ;;
        ipaudio) echo 'IPAudio Pro' ;;
        customcs) echo 'Custom Channel Selection' ;;
        aglare) echo 'Aglare Skin' ;;
        livefeed) echo 'LiveFeed OE' ;;
        epggrabber) echo 'EPG Grabber' ;;
        xstreamity) echo 'XStreamity (OpenATV feed)' ;;
        mixaudio) echo 'MixAudio' ;;
        ncam) echo 'NCam' ;;
        oscamlevi) echo 'OSCam Levi45' ;;
        mystreamer) echo 'MyStreamer' ;;
        furybiss) echo 'FuryBiss' ;;
        moviesostende) echo 'Movies & Series Ostende' ;;
        *) echo '' ;;
    esac
}

if [ "${1:-}" = '--run-install' ]; then
    [ "$(id -u)" -eq 0 ] && command -v opkg >/dev/null 2>&1 || exit 1
    run_mode install
    exit $?
fi

if [ "${1:-}" = '--run-remove' ]; then
    [ "$(id -u)" -eq 0 ] && command -v opkg >/dev/null 2>&1 || exit 1
    run_mode remove
    exit $?
fi

if [ "$(id -u)" -ne 0 ] || ! command -v opkg >/dev/null 2>&1; then
    say 'ERROR: Root and OpenATV/opkg required'
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    say 'ERROR: Python3 required'
    exit 1
fi

# Open the menu without restarting an already loaded GUI.
if [ -r "$READY" ]; then
    read -r UI_VERSION UI_PID < "$READY"
    if [ "$UI_VERSION" = "$VERSION" ] && [ -n "$UI_PID" ] && kill -0 "$UI_PID" 2>/dev/null; then
        : > "$REQUEST"
        say "A Panel $VERSION: opening the TV menu now."
        exit 0
    fi
fi

# New installation or GUI plugin update.
mkdir -p "$ROOT" "$PLUG" || exit 1
cp "$0" "$CORE" || exit 1
chmod 755 "$CORE"

cat > "$PLUG/plugin.py" <<'PY'
# A Panel v0.4.1 - Enigma2 TV interface
from __future__ import absolute_import

import os
import subprocess

from enigma import eTimer
from Plugins.Plugin import PluginDescriptor
from Screens.Screen import Screen
from Components.ActionMap import ActionMap
from Components.Label import Label
from Components.MenuList import MenuList
from Screens.MessageBox import MessageBox

VERSION = 'v0.4.1'
TITLE = 'A Panel'
AUTHOR = 'by Hamada Hawwas'
BASE = '/home/root/'
CORE = BASE + 'apanel-core.sh'
CHOICES = BASE + 'apanel-choices.txt'
PROGRESS = BASE + 'apanel-progress.log'
LOG = BASE + 'apanel-task.log'
REQUEST = '/tmp/apanel-ui-request'
READY = '/tmp/apanel-ui-ready'
PIDFILE = '/tmp/apanel-task.pid'
MODEFILE = '/tmp/apanel-task.mode'

PLUGINS = [
    {'key': 'aj', 'name': 'AJ Panel'},
    {'key': 'subs', 'name': 'SubsSupport Pro'},
    {'key': 'transmission', 'name': 'Transmission'},
    {'key': 'tmdb', 'name': 'TMDB'},
    {'key': 'arabicsavior', 'name': 'Arabic Savior'},
    {'key': 'raed', 'name': 'Raed Quick Signal'},
    {'key': 'audioshift', 'name': 'AudioShift (Dreambox One only)', 'one_only': True},
    {'key': 'ipaudio', 'name': 'IPAudio Pro'},
    {'key': 'customcs', 'name': 'Custom Channel Selection'},
    {'key': 'aglare', 'name': 'Aglare Skin'},
    {'key': 'livefeed', 'name': 'LiveFeed OE'},
    {'key': 'epggrabber', 'name': 'EPG Grabber'},
    {'key': 'xstreamity', 'name': 'XStreamity (OpenATV feed)'},
    {'key': 'mixaudio', 'name': 'MixAudio'},
    {'key': 'ncam', 'name': 'NCam'},
    {'key': 'oscamlevi', 'name': 'OSCam Levi45'},
    {'key': 'mystreamer', 'name': 'MyStreamer'},
    {'key': 'furybiss', 'name': 'FuryBiss'},
    {'key': 'moviesostende', 'name': 'Movies & Series Ostende'}
]


def is_one():
    try:
        with open('/proc/stb/info/model') as f:
            return f.read().strip() in ('one', 'dreamone', 'dreamboxone')
    except Exception:
        return False


def active():
    try:
        with open(PIDFILE) as f:
            pid = int(f.read().strip())
        os.kill(pid, 0)
        return True
    except Exception:
        return False


def current_mode():
    try:
        with open(MODEFILE) as f:
            return f.read().strip() or 'install'
    except Exception:
        return 'install'


class APanelBase(Screen):
    def is_allowed(self, meta):
        return (not meta.get('one_only')) or is_one()

    def rows_for(self, checked, only_installed=False):
        rows = []
        for idx, meta in enumerate(PLUGINS):
            allowed = self.is_allowed(meta)
            installed = self.installed(meta)
            if only_installed and not installed:
                continue
            if not allowed and not only_installed:
                flag = '[-]'
            elif meta['key'] in checked:
                flag = '[X]'
            else:
                flag = '[ ]'
            suffix = ''
            if only_installed:
                suffix = '  (installed)' if installed else ''
            rows.append((meta['key'], '%02d  %s  %s%s' % (idx + 1, flag, meta['name'], suffix)))
        return rows

    def installed(self, meta):
        key = meta['key']
        if not hasattr(self, '_package_names'):
            self._package_names = set()
            try:
                data = subprocess.check_output(['opkg', 'list-installed']).decode('utf-8', 'ignore')
                self._package_names = set(line.split()[0] for line in data.splitlines() if line.strip())
            except Exception:
                pass
        known_packages = {
            'mystreamer': ['enigma2-plugin-extensions-mystreamer'],
            'furybiss': ['enigma2-plugin-extensions-furybiss', 'enigma2-plugin-extensions-furybis'],
            'xstreamity': ['enigma2-plugin-extensions-xstreamity'],
            'ncam': ['enigma2-plugin-softcams-ncam'],
            'oscamlevi': ['enigma2-plugin-softcams-oscam-emu-pcsc-levi45'],
        }
        if any(pkg in self._package_names for pkg in known_packages.get(key, [])):
            return True
        paths = {
            'aj': ['/usr/lib/enigma2/python/Plugins/Extensions/AjPanel'],
            'subs': ['/usr/lib/enigma2/python/Plugins/Extensions/SubsSupport'],
            'transmission': ['/usr/lib/enigma2/python/Plugins/Extensions/Transmission', '/usr/lib/enigma2/python/Plugins/Extensions/Transmission_e2', '/etc/transmission'],
            'tmdb': ['/usr/lib/enigma2/python/Plugins/Extensions/TMDB'],
            'arabicsavior': ['/usr/lib/enigma2/python/Plugins/Extensions/ArabicSavior'],
            'raed': ['/usr/lib/enigma2/python/Plugins/Extensions/RaedQuickSignal'],
            'audioshift': ['/usr/lib/enigma2/python/Plugins/Extensions/AudioShift'],
            'ipaudio': ['/usr/lib/enigma2/python/Plugins/Extensions/IPAudioPro'],
            'customcs': ['/usr/lib/enigma2/python/Plugins/Extensions/CustomChannelSelection'],
            'aglare': ['/usr/share/enigma2/aglare'],
            'livefeed': ['/usr/lib/enigma2/python/Plugins/Extensions/LiveFeedOE', '/usr/lib/enigma2/python/Plugins/Extensions/LiveFeed'],
            'epggrabber': ['/usr/lib/enigma2/python/Plugins/Extensions/EPGGrabber'],
            'xstreamity': ['/usr/lib/enigma2/python/Plugins/Extensions/XStreamity'],
            'mixaudio': ['/usr/lib/enigma2/python/Plugins/Extensions/MixAudio'],
            'ncam': ['/etc/tuxbox/config/ncam', '/usr/bin/ncam', '/usr/keys/ncam'],
            'oscamlevi': ['/usr/bin/OSCam_11968-803', '/etc/tuxbox/config/oscam'],
            'mystreamer': ['/usr/lib/enigma2/python/Plugins/Extensions/MyStreamer', '/usr/lib/enigma2/python/Plugins/Extensions/i2ePlayer'],
            'furybiss': ['/usr/lib/enigma2/python/Plugins/Extensions/FuryBiss'],
            'moviesostende': ['/usr/lib/enigma2/python/Plugins/Extensions/MoviesManager', '/usr/lib/enigma2/python/Plugins/Extensions/MoviesSeriesOstende'],
        }
        for path in paths.get(key, []):
            if os.path.exists(path):
                return True
        return False


class InstallPicker(APanelBase):
    skin = '''<screen name="InstallPicker"
        position="center,center"
        size="1120,660"
        title="A Panel"
        backgroundColor="#10161f">

        <widget name="heading"
            position="24,16" size="1072,42"
            font="Regular;34"
            foregroundColor="#ffffff"
            backgroundColor="#10161f" />

        <widget name="sub"
            position="24,58" size="1072,30"
            font="Regular;21"
            foregroundColor="#f1bb60"
            backgroundColor="#10161f" />

        <widget name="help"
            position="24,92" size="1072,30"
            font="Regular;22"
            foregroundColor="#9fd7ff"
            backgroundColor="#10161f" />

        <widget name="items"
            position="24,132" size="1072,418"
            scrollbarMode="showOnDemand" />

        <widget name="summary"
            position="24,560" size="1072,30"
            font="Regular;23"
            foregroundColor="#ffffff"
            backgroundColor="#10161f" />

        <widget name="keys"
            position="24,600" size="1072,34"
            font="Regular;23"
            foregroundColor="#8de39b"
            backgroundColor="#10161f" />
    </screen>'''

    def __init__(self, session):
        Screen.__init__(self, session)
        self.allowed = [p['key'] for p in PLUGINS if self.is_allowed(p)]
        self.checked = set(self.allowed)
        self.rows = []
        self['heading'] = Label(TITLE + '  |  Install Plugins')
        self['sub'] = Label(AUTHOR)
        self['help'] = Label('UP / DOWN: select     OK: tick / untick     MENU: uninstall')
        self['items'] = MenuList([])
        self['summary'] = Label('')
        self['keys'] = Label('GREEN: Install   YELLOW: All   BLUE: None   MENU: Uninstall   RED: Exit')
        self['actions'] = ActionMap(['OkCancelActions', 'DirectionActions', 'ColorActions', 'MenuActions'], {
            'up': self.up,
            'down': self.down,
            'ok': self.toggle,
            'green': self.install,
            'yellow': self.all,
            'blue': self.none,
            'menu': self.open_uninstall,
            'red': self.close,
            'cancel': self.close,
        }, -1)
        self.refresh()

    def refresh(self):
        current = self['items'].getCurrentIndex()
        self.rows = self.rows_for(self.checked, False)
        self['items'].setList([r[1] for r in self.rows])
        if current >= 0 and current < len(self.rows):
            self['items'].moveToIndex(current)
        self['summary'].setText('Selected: %d / %d plugins' % (len(self.checked), len(self.allowed)))

    def up(self):
        self['items'].up()

    def down(self):
        self['items'].down()

    def toggle(self):
        if not self.rows:
            return
        key = self.rows[self['items'].getCurrentIndex()][0]
        if key not in self.allowed:
            return
        if key in self.checked:
            self.checked.remove(key)
        else:
            self.checked.add(key)
        self.refresh()

    def all(self):
        self.checked = set(self.allowed)
        self.refresh()

    def none(self):
        self.checked = set()
        self.refresh()

    def install(self):
        selected = [k for k in self.allowed if k in self.checked]
        if not selected:
            self['summary'].setText('Select at least one plugin.')
            return
        if active():
            self.session.open(TaskProgress)
            return
        try:
            with open(CHOICES, 'w') as f:
                f.write('\n'.join(selected) + '\n')
            logfile = open(LOG, 'w')
            proc = subprocess.Popen(['/bin/sh', CORE, '--run-install'], stdin=subprocess.DEVNULL, stdout=logfile, stderr=subprocess.STDOUT, close_fds=True, start_new_session=True)
            logfile.close()
            with open(PIDFILE, 'w') as f:
                f.write(str(proc.pid))
            with open(MODEFILE, 'w') as f:
                f.write('install\n')
            self.session.open(TaskProgress)
        except Exception as e:
            self['summary'].setText('Start failed: %s' % e)

    def open_uninstall(self):
        self.session.open(UninstallPicker)


class UninstallPicker(APanelBase):
    skin = '''<screen name="UninstallPicker"
        position="center,center"
        size="1120,660"
        title="A Panel"
        backgroundColor="#16110f">

        <widget name="heading"
            position="24,16" size="1072,42"
            font="Regular;34"
            foregroundColor="#ffffff"
            backgroundColor="#16110f" />

        <widget name="sub"
            position="24,58" size="1072,30"
            font="Regular;21"
            foregroundColor="#f1bb60"
            backgroundColor="#16110f" />

        <widget name="help"
            position="24,92" size="1072,30"
            font="Regular;22"
            foregroundColor="#9fd7ff"
            backgroundColor="#16110f" />

        <widget name="items"
            position="24,132" size="1072,418"
            scrollbarMode="showOnDemand" />

        <widget name="summary"
            position="24,560" size="1072,30"
            font="Regular;23"
            foregroundColor="#ffffff"
            backgroundColor="#16110f" />

        <widget name="keys"
            position="24,600" size="1072,34"
            font="Regular;23"
            foregroundColor="#ffb18d"
            backgroundColor="#16110f" />
    </screen>'''

    def __init__(self, session):
        Screen.__init__(self, session)
        self.checked = set()
        self.rows = []
        self['heading'] = Label(TITLE + '  |  Uninstall Plugins')
        self['sub'] = Label(AUTHOR)
        self['help'] = Label('Only installed plugins are shown     MENU: back to install')
        self['items'] = MenuList([])
        self['summary'] = Label('')
        self['keys'] = Label('GREEN: Remove   YELLOW: All   BLUE: None   MENU: Install   RED: Back')
        self['actions'] = ActionMap(['OkCancelActions', 'DirectionActions', 'ColorActions', 'MenuActions'], {
            'up': self.up,
            'down': self.down,
            'ok': self.toggle,
            'green': self.remove_selected,
            'yellow': self.all,
            'blue': self.none,
            'menu': self.back_to_install,
            'red': self.close,
            'cancel': self.close,
        }, -1)
        self.refresh()

    def refresh(self):
        current = self['items'].getCurrentIndex()
        self.rows = self.rows_for(self.checked, True)
        self['items'].setList([r[1] for r in self.rows])
        if current >= 0 and current < len(self.rows):
            self['items'].moveToIndex(current)
        self['summary'].setText('Selected for removal: %d | Installed shown: %d' % (len(self.checked), len(self.rows)))

    def up(self):
        self['items'].up()

    def down(self):
        self['items'].down()

    def toggle(self):
        if not self.rows:
            return
        key = self.rows[self['items'].getCurrentIndex()][0]
        if key in self.checked:
            self.checked.remove(key)
        else:
            self.checked.add(key)
        self.refresh()

    def all(self):
        self.checked = set([r[0] for r in self.rows])
        self.refresh()

    def none(self):
        self.checked = set()
        self.refresh()

    def remove_selected(self):
        selected = [r[0] for r in self.rows if r[0] in self.checked]
        if not selected:
            self['summary'].setText('Select at least one installed plugin.')
            return
        if active():
            self.session.open(TaskProgress)
            return
        self.session.openWithCallback(
            self.confirm_remove,
            MessageBox,
            'Remove %d selected plugin(s)?\nOnly verified IPK package removals are enabled.\nConfigurations and shared files are kept.' % len(selected),
            MessageBox.TYPE_YESNO,
            default=False
        )

    def confirm_remove(self, confirmed):
        if not confirmed:
            return
        selected = [r[0] for r in self.rows if r[0] in self.checked]
        if not selected or active():
            return
        try:
            with open(CHOICES, 'w') as f:
                f.write('\n'.join(selected) + '\n')
            logfile = open(LOG, 'w')
            proc = subprocess.Popen(['/bin/sh', CORE, '--run-remove'], stdin=subprocess.DEVNULL, stdout=logfile, stderr=subprocess.STDOUT, close_fds=True, start_new_session=True)
            logfile.close()
            with open(PIDFILE, 'w') as f:
                f.write(str(proc.pid))
            with open(MODEFILE, 'w') as f:
                f.write('remove\n')
            self.session.open(TaskProgress)
        except Exception as e:
            self['summary'].setText('Start failed: %s' % e)

    def back_to_install(self):
        # Return to the existing Install screen; do not stack another instance.
        self.close()


class TaskProgress(Screen):
    skin = '''<screen name="TaskProgress"
        position="center,center"
        size="1120,640"
        title="A Panel"
        backgroundColor="#10161f">

        <widget name="heading"
            position="24,20" size="1072,46"
            font="Regular;34"
            foregroundColor="#ffffff"
            backgroundColor="#10161f" />

        <widget name="status"
            position="24,84" size="1072,472"
            font="Regular;25"
            foregroundColor="#ffffff"
            backgroundColor="#10161f" />

        <widget name="footer"
            position="24,576" size="1072,30"
            font="Regular;22"
            foregroundColor="#9fd7ff"
            backgroundColor="#10161f" />
    </screen>'''

    def __init__(self, session):
        Screen.__init__(self, session)
        self['heading'] = Label(TITLE + '  |  Working...')
        self['status'] = Label('Preparing...')
        self['footer'] = Label('You can close Telnet/SSH; the task keeps running on the receiver.')
        self['actions'] = ActionMap(['OkCancelActions'], {'cancel': self.close, 'ok': self.close}, -1)
        self.timer = eTimer()
        try:
            self.timer.callback.append(self.update)
        except AttributeError:
            self.timer_conn = self.timer.timeout.connect(self.update)
        self.onShown.append(self.begin)
        self.onClose.append(self.stop)

    def begin(self):
        self.update()
        self.timer.start(1500, False)

    def stop(self):
        self.timer.stop()

    def update(self):
        mode = current_mode()
        self['heading'].setText(TITLE + ('  |  Installing...' if mode == 'install' else '  |  Uninstalling...'))
        try:
            with open(PROGRESS) as f:
                txt = '\n'.join(f.read().splitlines()[-14:])
            self['status'].setText(txt or 'Preparing task...')
        except Exception:
            self['status'].setText('Preparing task...')


_session = None
_poll = None
_poll_conn = None
_opening = False


def poll_request():
    global _opening
    if _session is None or _opening:
        return
    if not os.path.exists(REQUEST):
        return
    _opening = True
    try:
        os.unlink(REQUEST)
        if active():
            _session.open(TaskProgress)
        else:
            _session.open(InstallPicker)
    except Exception as e:
        print('[A Panel] Open failed:', e)
        try:
            open(REQUEST, 'w').close()
        except Exception:
            pass
    finally:
        _opening = False


def session_start(reason, **kwargs):
    global _session, _poll, _poll_conn
    if reason != 0 or 'session' not in kwargs:
        return
    _session = kwargs['session']
    _poll = eTimer()
    try:
        _poll.callback.append(poll_request)
    except AttributeError:
        _poll_conn = _poll.timeout.connect(poll_request)
    _poll.start(1500, False)
    try:
        with open(READY, 'w') as f:
            f.write('%s %d\n' % (VERSION, os.getpid()))
    except Exception:
        pass
    if active() and not os.path.exists(REQUEST):
        try:
            open(REQUEST, 'w').close()
        except Exception:
            pass


def open_plugin(session, **kwargs):
    if active():
        session.open(TaskProgress)
    else:
        session.open(InstallPicker)


def Plugins(**kwargs):
    return [
        PluginDescriptor(
            name='A Panel',
            description='H. Hawwas OpenATV plugin manager',
            where=PluginDescriptor.WHERE_PLUGINMENU,
            fnc=open_plugin
        ),
        PluginDescriptor(
            where=PluginDescriptor.WHERE_SESSIONSTART,
            fnc=session_start
        )
    ]
PY

# Built-in syntax check, no py_compile module needed.
python3 -c 'import sys; p=sys.argv[1]; compile(open(p,"rb").read(),p,"exec"); print("Python syntax OK")' "$PLUG/plugin.py" || {
    say 'ERROR: A Panel Python syntax failed'
    exit 1
}

touch "$PLUG/__init__.py" || exit 1

# Remove only the previous panel's loader after new plugin syntax has passed.
# Other plugins or their data are never touched here.
OLD_PLUG=/usr/lib/enigma2/python/Plugins/Extensions/HawwasInstaller
if [ -d "$OLD_PLUG" ]; then
    rm -rf "$OLD_PLUG" || {
        say 'WARNING: Could not remove previous Hawwas Panel menu entry.'
    }
fi

: > "$REQUEST"

say "A Panel $VERSION installed/updated."
say 'Restarting Enigma2 GUI once to load this version.'
say 'Future launches of this version will not restart GUI.'
say 'Remote: UP/DOWN, OK toggle, GREEN install, MENU uninstall.'

nohup sh -c 'sleep 2; init 4; sleep 3; init 3' > /home/root/apanel-launch.log 2>&1 < /dev/null &
exit 0
