#!/bin/sh
# H. Hawwas Auto Installer v0.3.1 - TV Edition
# OpenATV / opkg only
# GSH2 is deliberately excluded.

export PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH

CORE=/home/root/hhawwas-core.sh
PLUG=/usr/lib/enigma2/python/Plugins/Extensions/HawwasInstaller
CHOICES=/tmp/hawwas-choices.txt
PROG=/home/root/openatv-progress.log
LOG=/home/root/openatv-install.log

say() {
    printf '%s\n' "$*"
}

report() {
    say "$*" | tee -a "$PROG"
}

bar() {
    PCT=$((DONE*100/TOTAL))
    FILL=$((DONE*20/TOTAL))
    B=''
    I=0

    while [ "$I" -lt 20 ]; do
        if [ "$I" -lt "$FILL" ]; then
            B="${B}#"
        else
            B="${B}-"
        fi
        I=$((I+1))
    done

    report "PROGRESS [$B] $PCT% | $DONE/$TOTAL | OK:$OK CHECK:$CHECK FAILED:$FAIL"
}

pulse() {
    while :; do
        sleep 20
        report "... $1 still installing"
    done
}

step() {
    NUM=$((NUM+1))
    TITLE=$1
    shift

    report "[$NUM/$TOTAL] START: $TITLE"

    pulse "$TITLE" &
    HB=$!

    "$@"
    RC=$?

    kill "$HB" 2>/dev/null || :
    wait "$HB" 2>/dev/null || :

    DONE=$((DONE+1))

    case "$RC" in
        0)
            OK=$((OK+1))
            report "[$NUM/$TOTAL] OK: $TITLE"
            ;;
        2)
            CHECK=$((CHECK+1))
            report "[$NUM/$TOTAL] CHECK: $TITLE (see log)"
            ;;
        *)
            FAIL=$((FAIL+1))
            report "[$NUM/$TOTAL] FAILED ($RC): $TITLE"
            ;;
    esac

    bar
}

remote() {
    U=$1
    F=/tmp/hawwas-remote-$$.sh

    rm -f "$F"

    if ! wget -qO "$F" "$U" || [ ! -s "$F" ]; then
        say "Download failed: $U"
        rm -f "$F"
        return 1
    fi

    bash "$F"
    R=$?

    rm -f "$F"
    return "$R"
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
            say 'FFmpeg 9: trying upstream FFmpeg 8 build; runtime compatibility is not assured'
            ;;
        *)
            say "Unsupported FFmpeg $MAJOR"
            return 1
            ;;
    esac

    PY=$(python3 -c 'import sys;print("%d.%d" % sys.version_info[:2])') || return 1

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
    R=$?

    rm -f "$IPK"

    [ "$R" -eq 0 ] || return "$R"

    opkg list-installed | grep -q '^enigma2-plugin-extensions-ipaudiopro '
}

levi() {
    IPK=/tmp/hawwas-levi-$$.ipk

    URL=https://raw.githubusercontent.com/levi-45/Levi45Emulator/main/enigma2-plugin-softcams-oscam-emu-pcsc-levi45_11968-803_all.ipk

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
    if [ ! -r "$CHOICES" ]; then
        say 'No plugin selection.'
        exit 1
    fi

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

    : > "$PROG"

    report "H. Hawwas Auto Installer v0.3.1 | $TOTAL steps"

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
                step 'Transmission Clients and Libraries' transmission
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
                step 'NCam 15.8' ncam
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

    rm -f /tmp/hawwas-installer.pid
    reboot
}

if [ "${1:-}" = '--run' ]; then
    run
    exit $?
fi

if [ "$(id -u)" -ne 0 ]; then
    say 'ERROR: Run as root'
    exit 1
fi

if ! command -v opkg >/dev/null 2>&1; then
    say 'ERROR: OpenATV/opkg required'
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    say 'ERROR: Python3 required'
    exit 1
fi

mkdir -p /home/root "$PLUG" || exit 1

cp "$0" "$CORE" || exit 1
chmod 755 "$CORE"

cat > "$PLUG/plugin.py" <<'PY'
# H. Hawwas Auto Installer v0.3.1 - Enigma2 TV interface

from __future__ import absolute_import

import os
import subprocess

from enigma import eTimer
from Plugins.Plugin import PluginDescriptor
from Screens.Screen import Screen
from Components.ActionMap import ActionMap
from Components.Label import Label
from Components.MenuList import MenuList

BASE = '/home/root/'
CORE = BASE + 'hhawwas-core.sh'
CHOICES = '/tmp/hawwas-choices.txt'
PROGRESS = BASE + 'openatv-progress.log'
LOG = BASE + 'openatv-install.log'
PENDING = '/tmp/hawwas-show-menu'
PIDFILE = '/tmp/hawwas-installer.pid'

TITLE = 'H. Hawwas Auto Installer v0.3.1'

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
    'NCam 15.8',
    'OSCam Levi45 11968 (experimental)'
]


def is_one():
    try:
        return open('/proc/stb/info/model').read().strip() in (
            'one', 'dreamone', 'dreamboxone'
        )
    except Exception:
        return False


def active():
    try:
        pid = int(open(PIDFILE).read().strip())
        os.kill(pid, 0)
        return True
    except Exception:
        return False


class HawwasPicker(Screen):

    skin = '''<screen name="HawwasPicker"
        position="center,center"
        size="1100,650"
        title="H. Hawwas Auto Installer"
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

        self['heading'] = Label(TITLE)

        self['help'] = Label(
            'UP / DOWN: select    OK: tick / untick'
        )

        self['items'] = MenuList([])
        self['summary'] = Label('')

        self['keys'] = Label(
            'GREEN: Install    YELLOW: All    BLUE: None    RED: Exit'
        )

        self['actions'] = ActionMap(
            ['OkCancelActions', 'DirectionActions', 'ColorActions'],
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
            else:
                flag = '[X]' if i in self.checked else '[ ]'

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
                'Choose at least one plugin before installing.'
            )
            return

        if active():
            self.session.open(HawwasProgress)
            return

        try:
            with open(CHOICES, 'w') as f:
                f.write(
                    ' '.join(
                        str(i + 1) for i in sorted(self.checked)
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
                'START FAILED: %s' % str(e)[:75]
            )


class HawwasProgress(Screen):

    skin = '''<screen name="HawwasProgress"
        position="center,center"
        size="1100,620"
        title="H. Hawwas Installation Progress"
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

        self['heading'] = Label(TITLE + ' - Progress')
        self['status'] = Label('Starting installation...')

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
        self.timer.callback.append(self.update)

        self.onShown.append(self.begin)
        self.onClose.append(self.stop)

    def begin(self):
        self.update()
        self.timer.start(1500, False)

    def stop(self):
        self.timer.stop()

    def update(self):
        try:
            lines = open(PROGRESS).read().splitlines()

            txt = '\n'.join(lines[-14:])

            self['status'].setText(
                txt or 'Preparing the installer...'
            )

        except Exception:
            self['status'].setText(
                'Preparing the installer...'
            )


_pendingTimer = None
_pendingConn = None
_session = None


def show_pending():
    global _pendingTimer

    if _pendingTimer is not None:
        _pendingTimer.stop()

    if _session is None:
        return

    if active():
        _session.open(HawwasProgress)

    elif os.path.exists(PENDING):
        try:
            os.unlink(PENDING)
        except Exception:
            pass

        _session.open(HawwasPicker)


def session_start(reason, **kwargs):
    global _pendingTimer, _pendingConn, _session

    if reason != 0 or 'session' not in kwargs:
        return

    _session = kwargs['session']

    if not active() and not os.path.exists(PENDING):
        return

    _pendingTimer = eTimer()

    try:
        _pendingTimer.callback.append(show_pending)
    except AttributeError:
        _pendingConn = _pendingTimer.timeout.connect(show_pending)

    _pendingTimer.start(5000, True)


def open_plugin(session, **kwargs):
    session.open(
        HawwasProgress if active() else HawwasPicker
    )


def Plugins(**kwargs):
    return [
        PluginDescriptor(
            name='H. Hawwas Auto Installer',
            description='Select and install OpenATV plugins on TV',
            where=PluginDescriptor.WHERE_PLUGINMENU,
            fnc=open_plugin
        ),

        PluginDescriptor(
            where=PluginDescriptor.WHERE_SESSIONSTART,
            fnc=session_start
        )
    ]
PY

python3 -c 'import sys; p=sys.argv[1]; compile(open(p,"rb").read(),p,"exec"); print("Python syntax OK")' "$PLUG/plugin.py" || {
    say 'ERROR: Enigma2 plugin Python syntax failed'
    exit 1
}

touch "$PLUG/__init__.py"
touch /tmp/hawwas-show-menu

say 'H. Hawwas Auto Installer v0.3.1 installed.'
say 'Restarting Enigma2 GUI to show the plugin list on TV.'
say 'Use UP/DOWN, OK to toggle, GREEN to start.'
say 'If it does not pop up, open Plugins -> H. Hawwas Auto Installer.'

nohup sh -c 'sleep 2; init 4; sleep 3; init 3' \
    > /home/root/hawwas-launch.log 2>&1 < /dev/null &

exit 0