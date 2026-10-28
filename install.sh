#!/bin/sh
# Hawwas Panel v0.3.2 - OpenATV Enigma2 TV installer
# OpenATV / opkg only. GSH2 is intentionally excluded.
# Third-party installers run as root.

export PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH

VERSION=v0.3.2
ROOT=/home/root
CORE=$ROOT/hhawwas-core.sh
PLUG=/usr/lib/enigma2/python/Plugins/Extensions/HawwasInstaller
CHOICES=/tmp/hawwas-choices.txt
PROGRESS=$ROOT/openatv-progress.log
LOG=$ROOT/openatv-install.log
READY=/tmp/hawwas-ui-ready
REQUEST=/tmp/hawwas-ui-request
PIDFILE=/tmp/hawwas-installer.pid

say() {
    printf '%s\n' "$*"
}

report() {
    say "$*" | tee -a "$PROGRESS"
}

bar() {
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
        report "... $1 still installing"
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
            report "[$NUM/$TOTAL] CHECK: $LABEL (see log)"
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
    FILE=/tmp/hawwas-remote-$$.sh

    rm -f "$FILE"

    if ! wget -qO "$FILE" "$URL" || [ ! -s "$FILE" ]; then
        say "Download failed: $URL"
        rm -f "$FILE"
        return 1
    fi

    bash "$FILE"
    RC=$?

    rm -f "$FILE"
    return "$RC"
}

transmission() {
    opkg install transmission transmission-client python3-transmission-rpc xz || return 1
    opkg install python3-beautifulsoup4 python3-yt-dlp
}

xstreamity() {
    opkg list | awk '$1=="enigma2-plugin-extensions-xstreamity" {f=1} END {exit !f}' || return 1

    opkg install enigma2-plugin-extensions-xstreamity || return 1

    opkg list-installed | grep -q '^enigma2-plugin-extensions-xstreamity '
}

epggrabber() {
    remote https://raw.githubusercontent.com/zKhadiri/Epg-plugin/master/Download/installer.sh || return 1

    [ -d /usr/lib/enigma2/python/Plugins/Extensions/EPGGrabber ]
}

ncam() {
    # Current upstream installer provides NCam 15.8.
    remote https://raw.githubusercontent.com/biko-73/Ncam_EMU/main/installer.sh || return 1

    opkg list-installed | grep '^enigma2-plugin-softcams-ncam ' | grep -q '15\.8'
}

ipaudio() {
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

    META=/tmp/hawwas-ipaudio-meta-$$.sh

    wget -qO "$META" https://raw.githubusercontent.com/zKhadiri/IPAudioPro-Releases-/main/installer.sh || return 1

    VER=$(sed -n 's/^VERSION=\([0-9][0-9.]*\).*$/\1/p' "$META" | head -n 1)

    rm -f "$META"

    [ -n "$VER" ] || return 1

    PKG="enigma2-plugin-extensions-ipaudiopro_${VER}_${ARCH}_py${PY}_ff${FF}.ipk"

    URL="https://raw.githubusercontent.com/zKhadiri/IPAudioPro-Releases-/main/v${VER}/python${PY}/${DIR}/${PKG}"

    IPK=/tmp/hawwas-ipaudio-$$.ipk

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

levi() {
    # Fixed Levi45 build.
    URL=https://raw.githubusercontent.com/levi-45/Levi45Emulator/main/enigma2-plugin-softcams-oscam-emu-pcsc-levi45_11968-803_all.ipk

    IPK=/tmp/hawwas-levi-$$.ipk

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

run() {
    [ -r "$CHOICES" ] || {
        say 'No plugin selection.'
        return 1
    }

    SELECTED=$(cat "$CHOICES")

    TOTAL=1
    for K in $SELECTED; do
        TOTAL=$((TOTAL+1))
    done

    NUM=0
    DONE=0
    OK=0
    CHECK=0
    FAIL=0

    : > "$PROGRESS"

    report "Hawwas Panel $VERSION | $TOTAL steps"

    step 'Update OpenATV feed' opkg update

    for K in $(seq 1 17); do
        case " $SELECTED " in
            *" $K "*) : ;;
            *) continue ;;
        esac

        case "$K" in
            1)
                step 'AJ Panel' remote https://raw.githubusercontent.com/biko-73/AjPanel/main/installer.sh
                ;;
            2)
                step 'SubsSupport Pro' remote https://raw.githubusercontent.com/popking159/SubsSupportPro/refs/heads/main/myinstaller.sh
                ;;
            3)
                step 'Transmission Clients + Libraries' transmission
                ;;
            4)
                step 'Transmission E2' remote http://dreambox4u.com/dreamarabia/Transmission_e2/Transmission_e2.sh
                ;;
            5)
                step 'TMDB' remote https://raw.githubusercontent.com/biko-73/TMBD/main/installer.sh
                ;;
            6)
                step 'Arabic Savior' remote https://raw.githubusercontent.com/fairbird/ArabicSavior/main/installer.sh
                ;;
            7)
                step 'Raed Quick Signal' remote https://raw.githubusercontent.com/fairbird/RaedQuickSignal/main/installer.sh
                ;;
            8)
                case "$(cat /proc/stb/info/model 2>/dev/null)" in
                    one|dreamone|dreamboxone)
                        step 'AudioShift' remote https://xfayez95.github.io/audioshift/installer.sh
                        ;;
                esac
                ;;
            9)
                step 'IPAudio Pro' ipaudio
                ;;
            10)
                step 'Custom Channel Selection' remote https://raw.githubusercontent.com/popking159/customchannelselection/refs/heads/main/myinstaller.sh
                ;;
            11)
                step 'Aglare Skin' remote https://raw.githubusercontent.com/popking159/skins/refs/heads/main/aglareatv/installer.sh
                ;;
            12)
                step 'LiveFeed OE' remote https://live-feed.net/enigma2/installer.sh
                ;;
            13)
                step 'EPG Grabber' epggrabber
                ;;
            14)
                step 'XStreamity' xstreamity
                ;;
            15)
                step 'MixAudio' remote https://raw.githubusercontent.com/Najar1991/MixAudio_All/refs/heads/main/install.sh
                ;;
            16)
                step 'NCam' ncam
                ;;
            17)
                step 'OSCam Levi45' levi
                ;;
        esac
    done

    report '=== INSTALLATION FINISHED ==='
    bar

    report "Results: OK=$OK CHECK=$CHECK FAILED=$FAIL"
    report "Full log: $LOG"
    report 'GSH2 was NOT installed.'
    report 'Full receiver reboot in 5 seconds.'

    sync
    sleep 5

    rm -f "$PIDFILE"
    reboot
}

if [ "${1:-}" = '--run' ]; then
    [ "$(id -u)" -eq 0 ] && command -v opkg >/dev/null 2>&1 || exit 1
    run
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
        say "Hawwas Panel $VERSION: opening the TV menu now."
        exit 0
    fi
fi

# New installation or GUI plugin update.

mkdir -p "$ROOT" "$PLUG" || exit 1

cp "$0" "$CORE" || exit 1
chmod 755 "$CORE"

cat > "$PLUG/plugin.py" <<'PY'
# Hawwas Panel v0.3.2 - Enigma2 TV interface

from __future__ import absolute_import

import os
import subprocess

from enigma import eTimer
from Plugins.Plugin import PluginDescriptor
from Screens.Screen import Screen
from Components.ActionMap import ActionMap
from Components.Label import Label
from Components.MenuList import MenuList

VERSION = 'v0.3.2'
TITLE = 'Hawwas Panel ' + VERSION
AUTHOR = 'by H. Hawwas'

BASE = '/home/root/'
CORE = BASE + 'hhawwas-core.sh'
CHOICES = '/tmp/hawwas-choices.txt'
PROGRESS = BASE + 'openatv-progress.log'
LOG = BASE + 'openatv-install.log'
REQUEST = '/tmp/hawwas-ui-request'
READY = '/tmp/hawwas-ui-ready'
PIDFILE = '/tmp/hawwas-installer.pid'

NAMES = [
    'AJ Panel',
    'SubsSupport Pro',
    'Transmission Clients + Libraries',
    'Transmission E2',
    'TMDB',
    'Arabic Savior',
    'Raed Quick Signal',
    'AudioShift (Dreambox One only)',
    'IPAudio Pro',
    'Custom Channel Selection',
    'Aglare Skin',
    'LiveFeed OE',
    'EPG Grabber',
    'XStreamity (OpenATV feed)',
    'MixAudio',
    'NCam',
    'OSCam Levi45'
]


def is_one():
    try:
        with open('/proc/stb/info/model') as f:
            return f.read().strip() in (
                'one', 'dreamone', 'dreamboxone'
            )
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


class HawwasPicker(Screen):

    skin = '''<screen name="HawwasPicker"
        position="center,center"
        size="1100,650"
        title="Hawwas Panel"
        backgroundColor="#121b29">

        <widget name="heading"
            position="25,18" size="1050,45"
            font="Regular;32"
            foregroundColor="#ffffff"
            backgroundColor="#121b29" />

        <widget name="help"
            position="25,65" size="1050,35"
            font="Regular;23"
            foregroundColor="#e0b85b"
            backgroundColor="#121b29" />

        <widget name="items"
            position="25,115" size="1050,400"
            scrollbarMode="showOnDemand" />

        <widget name="summary"
            position="25,526" size="1050,32"
            font="Regular;23"
            foregroundColor="#ffffff"
            backgroundColor="#121b29" />

        <widget name="keys"
            position="25,572" size="1050,40"
            font="Regular;24"
            foregroundColor="#90db9d"
            backgroundColor="#121b29" />

    </screen>'''

    def __init__(self, session):
        Screen.__init__(self, session)

        self.allowed = [
            i for i in range(17)
            if i != 7 or is_one()
        ]

        self.checked = set(self.allowed)

        self['heading'] = Label(
            TITLE + '  |  ' + AUTHOR
        )

        self['help'] = Label(
            'UP / DOWN: select     OK: tick / untick'
        )

        self['items'] = MenuList([])
        self['summary'] = Label('')

        self['keys'] = Label(
            'GREEN: Install   YELLOW: All   BLUE: None   RED: Exit'
        )

        self['actions'] = ActionMap(
            [
                'OkCancelActions',
                'DirectionActions',
                'ColorActions'
            ],
            {
                'up': self.up,
                'down': self.down,
                'ok': self.toggle,
                'green': self.install,
                'yellow': self.all,
                'blue': self.none,
                'red': self.close,
                'cancel': self.close
            },
            -1
        )

        self.refresh()

    def refresh(self):
        index = self['items'].getCurrentIndex()
        rows = []

        for i, name in enumerate(NAMES):
            if i not in self.allowed:
                flag = '[-]'
            elif i in self.checked:
                flag = '[X]'
            else:
                flag = '[ ]'

            rows.append(
                '%02d  %s  %s' % (i + 1, flag, name)
            )

        self['items'].setList(rows)

        if index >= 0:
            self['items'].moveToIndex(index)

        self['summary'].setText(
            'Selected: %d / %d plugins' %
            (len(self.checked), len(self.allowed))
        )

    def up(self):
        self['items'].up()

    def down(self):
        self['items'].down()

    def toggle(self):
        i = self['items'].getCurrentIndex()

        if i not in self.allowed:
            return

        if i in self.checked:
            self.checked.remove(i)
        else:
            self.checked.add(i)

        self.refresh()

    def all(self):
        self.checked = set(self.allowed)
        self.refresh()

    def none(self):
        self.checked = set()
        self.refresh()

    def install(self):
        if not self.checked:
            self['summary'].setText(
                'Select at least one plugin.'
            )
            return

        if active():
            self.session.open(HawwasProgress)
            return

        try:
            with open(CHOICES, 'w') as f:
                f.write(
                    ' '.join(
                        str(i+1) for i in sorted(self.checked)
                    ) + '\n'
                )

            logfile = open(LOG, 'w')

            proc = subprocess.Popen(
                ['/bin/sh', CORE, '--run'],
                stdin=subprocess.DEVNULL,
                stdout=logfile,
                stderr=subprocess.STDOUT,
                close_fds=True,
                start_new_session=True
            )

            logfile.close()

            with open(PIDFILE, 'w') as f:
                f.write(str(proc.pid))

            self.session.open(HawwasProgress)

        except Exception as e:
            self['summary'].setText(
                'START FAILED: %s' % str(e)[:90]
            )


class HawwasProgress(Screen):

    skin = '''<screen name="HawwasProgress"
        position="center,center"
        size="1100,620"
        title="Hawwas Panel Progress"
        backgroundColor="#121b29">

        <widget name="heading"
            position="25,20" size="1050,48"
            font="Regular;31"
            foregroundColor="#ffffff"
            backgroundColor="#121b29" />

        <widget name="status"
            position="25,85" size="1050,445"
            font="Regular;23"
            foregroundColor="#dddddd"
            backgroundColor="#121b29" />

        <widget name="keys"
            position="25,552" size="1050,40"
            font="Regular;23"
            foregroundColor="#90db9d"
            backgroundColor="#121b29" />

    </screen>'''

    def __init__(self, session):
        Screen.__init__(self, session)

        self['heading'] = Label(
            TITLE + ' - Progress'
        )

        self['status'] = Label(
            'Preparing installation...'
        )

        self['keys'] = Label(
            'RED / EXIT: Hide screen (installation continues)'
        )

        self['actions'] = ActionMap(
            ['OkCancelActions', 'ColorActions'],
            {
                'cancel': self.close,
                'red': self.close
            },
            -1
        )

        self.timer = eTimer()

        try:
            self.timer.callback.append(self.update)
        except AttributeError:
            self.timer_conn = self.timer.timeout.connect(
                self.update
            )

        self.onShown.append(self.begin)
        self.onClose.append(self.stop)

    def begin(self):
        self.update()
        self.timer.start(1500, False)

    def stop(self):
        self.timer.stop()

    def update(self):
        try:
            with open(PROGRESS) as f:
                txt = '\n'.join(
                    f.read().splitlines()[-13:]
                )

            self['status'].setText(
                txt or 'Preparing installation...'
            )

        except Exception:
            self['status'].setText(
                'Preparing installation...'
            )


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
            _session.open(HawwasProgress)
        else:
            _session.open(HawwasPicker)

    except Exception as e:
        print('[Hawwas Panel] Open failed:', e)

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
        _poll_conn = _poll.timeout.connect(
            poll_request
        )

    _poll.start(1500, False)

    try:
        with open(READY, 'w') as f:
            f.write(
                '%s %d\n' % (VERSION, os.getpid())
            )
    except Exception:
        pass

    if active() and not os.path.exists(REQUEST):
        try:
            open(REQUEST, 'w').close()
        except Exception:
            pass


def open_plugin(session, **kwargs):
    if active():
        session.open(HawwasProgress)
    else:
        session.open(HawwasPicker)


def Plugins(**kwargs):
    return [
        PluginDescriptor(
            name='Hawwas Panel',
            description='H. Hawwas OpenATV plugin installer',
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
    say 'ERROR: Hawwas Panel Python syntax failed'
    exit 1
}

touch "$PLUG/__init__.py" || exit 1

: > "$REQUEST"

say "Hawwas Panel $VERSION installed/updated."
say 'Restarting Enigma2 GUI once to load this version.'
say 'Future launches of this version will not restart GUI.'
say 'Remote: UP/DOWN, OK toggle, GREEN install.'

nohup sh -c 'sleep 2; init 4; sleep 3; init 3' \
    > /home/root/hawwas-launch.log 2>&1 < /dev/null &

exit 0