#!/bin/sh
# H. Hawwas Auto Installer v0.2.2 - Interactive selector (EXPERIMENTAL)
# OpenATV with opkg ONLY. GSH2 is excluded.
# Third-party installers may restart Enigma2.

export PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH

SELF=$0
LOG=/home/root/openatv-install.log
PROGRESS=/home/root/openatv-progress.log
SELECTION=/tmp/openatv-selection.txt
PIDFILE=/tmp/openatv-setup.pid

NAME_1='AJ Panel'
NAME_2='SubsSupport Pro'
NAME_3='Transmission packages'
NAME_4='Transmission E2'
NAME_5='TMDB'
NAME_6='Arabic Savior'
NAME_7='Raed Quick Signal'
NAME_8='AudioShift (Dreambox One only)'
NAME_9='IPAudio Pro'
NAME_10='Custom Channel Selection'
NAME_11='Aglare Skin'
NAME_12='LiveFeed OE'
NAME_13='EPG Grabber'
NAME_14='XStreamity (OpenATV feed)'
NAME_15='MixAudio'
NAME_16='NCam 15.8'
NAME_17='OSCam Levi45 11968 (experimental)'

MAX=17

model() {
    cat /proc/stb/info/model 2>/dev/null || :
}

MODEL=$(model)

case "$MODEL" in
    one|dreamone|dreamboxone)
        DREAMONE=1
        ;;
    *)
        DREAMONE=0
        ;;
esac

name_of() {
    case "$1" in
        1) echo "$NAME_1" ;;
        2) echo "$NAME_2" ;;
        3) echo "$NAME_3" ;;
        4) echo "$NAME_4" ;;
        5) echo "$NAME_5" ;;
        6) echo "$NAME_6" ;;
        7) echo "$NAME_7" ;;
        8) echo "$NAME_8" ;;
        9) echo "$NAME_9" ;;
        10) echo "$NAME_10" ;;
        11) echo "$NAME_11" ;;
        12) echo "$NAME_12" ;;
        13) echo "$NAME_13" ;;
        14) echo "$NAME_14" ;;
        15) echo "$NAME_15" ;;
        16) echo "$NAME_16" ;;
        17) echo "$NAME_17" ;;
    esac
}

selected() {
    case " $SELECTED " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

add_choice() {
    if ! selected "$1"; then
        SELECTED="$SELECTED $1"
    fi
}

remove_choice() {
    NEW=''
    for K in $SELECTED; do
        [ "$K" = "$1" ] || NEW="$NEW $K"
    done
    SELECTED=$NEW
}

select_defaults() {
    SELECTED=''
    for I in $(seq 1 "$MAX"); do
        [ "$I" = 8 ] && [ "$DREAMONE" -ne 1 ] && continue
        add_choice "$I"
    done
}

read_byte() {
    set -- $(LC_ALL=C dd bs=1 count=1 2>/dev/null | od -An -tu1)
    printf '%s' "${1:-}"
}

menu_draw() {
    printf '\033[2J\033[H'
    printf '========================================================\n'
    printf '  H. Hawwas Auto Installer v0.2.2\n'
    printf '  Device: %s | CPU: %s\n' "${MODEL:-unknown}" "$(uname -m)"
    printf '========================================================\n'

    I=1
    while [ "$I" -le "$MAX" ]; do
        FLAG=' '
        selected "$I" && FLAG=X

        FOCUS=' '
        [ "$I" -eq "$CURSOR" ] && FOCUS='>'

        if [ "$I" -eq 8 ] && [ "$DREAMONE" -ne 1 ]; then
            printf '%s %2d. [-] %s (not compatible)\n' \
                "$FOCUS" "$I" "$(name_of "$I")"
        else
            printf '%s %2d. [%s] %s\n' \
                "$FOCUS" "$I" "$FLAG" "$(name_of "$I")"
        fi

        I=$((I+1))
    done

    COUNT=0
    for I in $SELECTED; do
        COUNT=$((COUNT+1))
    done

    printf '\n  Selected: %s/%s plugins\n' "$COUNT" "$MAX"
    printf '  UP/DOWN=Move | SPACE=Toggle | ENTER=Start | Q=Quit\n'
    printf '  A=All | N=None | S=Start\n'
}

menu_restore() {
    stty "$SAVED_TTY" 2>/dev/null || :
    trap - 0 1 2 15
}

menu() {
    select_defaults
    CURSOR=1

    SAVED_TTY=$(stty -g 2>/dev/null) || {
        echo 'Terminal control unavailable.'
        return 1
    }

    if ! stty -echo -icanon min 1 time 0 2>/dev/null; then
        echo 'Cannot enable interactive terminal mode.'
        return 1
    fi

    trap 'stty "$SAVED_TTY" 2>/dev/null || :' 0
    trap 'exit 130' 2
    trap 'exit 143' 1 15

    while :; do
        menu_draw
        KEY=$(read_byte)

        [ -n "$KEY" ] || {
            menu_restore
            return 1
        }

        case "$KEY" in
            27)
                stty min 0 time 2 2>/dev/null || :
                SEQ1=$(read_byte)
                SEQ2=''
                [ -n "$SEQ1" ] && SEQ2=$(read_byte)
                stty min 1 time 0 2>/dev/null || :

                case "$SEQ1:$SEQ2" in
                    91:65|79:65)
                        CURSOR=$((CURSOR-1))
                        [ "$CURSOR" -lt 1 ] && CURSOR=$MAX
                        ;;
                    91:66|79:66)
                        CURSOR=$((CURSOR+1))
                        [ "$CURSOR" -gt "$MAX" ] && CURSOR=1
                        ;;
                esac
                ;;

            32)
                if [ "$CURSOR" -ne 8 ] || [ "$DREAMONE" -eq 1 ]; then
                    if selected "$CURSOR"; then
                        remove_choice "$CURSOR"
                    else
                        add_choice "$CURSOR"
                    fi
                fi
                ;;

            10|13|83|115)
                COUNT=0
                for I in $SELECTED; do
                    COUNT=$((COUNT+1))
                done

                if [ "$COUNT" -gt 0 ]; then
                    printf '%s\n' "$SELECTED" > "$SELECTION" || {
                        menu_restore
                        return 1
                    }

                    menu_restore
                    printf '\nSelected %s plugins. Installation starts now.\n' "$COUNT"
                    return 0
                fi
                ;;

            81|113)
                menu_restore
                printf '\nCancelled: no installation started.\n'
                return 1
                ;;

            65|97)
                select_defaults
                ;;

            78|110)
                SELECTED=''
                ;;

            49|50|51|52|53|54|55|56|57)
                NUM=$((KEY-48))

                if [ "$NUM" -ne 8 ] || [ "$DREAMONE" -eq 1 ]; then
                    if selected "$NUM"; then
                        remove_choice "$NUM"
                    else
                        add_choice "$NUM"
                    fi
                fi
                ;;
        esac
    done
}

note() {
    printf '%s\n' "$*"
}

emit() {
    printf '%s\n' "$*" | tee -a "$PROGRESS"
}

progress() {
    PCT=$((DONE*100/TOTAL))
    FILL=$((DONE*20/TOTAL))
    BAR=''
    J=0

    while [ "$J" -lt 20 ]; do
        if [ "$J" -lt "$FILL" ]; then
            BAR="${BAR}#"
        else
            BAR="${BAR}-"
        fi
        J=$((J+1))
    done

    emit "PROGRESS [$BAR] $PCT% | $DONE/$TOTAL done | OK:$GOOD CHECK:$CHECK FAILED:$BAD"
}

heartbeat() {
    LABEL=$1
    SEC=0

    while :; do
        sleep 20
        SEC=$((SEC+20))
        emit "  ... $LABEL still running ($SEC seconds)"
    done
}

step() {
    N=$((N+1))
    LABEL=$1
    shift

    emit "[$N/$TOTAL] START: $LABEL"

    heartbeat "$LABEL" &
    HB_PID=$!

    "$@"
    RC=$?

    kill "$HB_PID" 2>/dev/null || :
    wait "$HB_PID" 2>/dev/null || :

    DONE=$((DONE+1))

    case "$RC" in
        0)
            GOOD=$((GOOD+1))
            emit "[$N/$TOTAL] OK: $LABEL"
            ;;
        2)
            CHECK=$((CHECK+1))
            emit "[$N/$TOTAL] CHECK: $LABEL (see detailed log)"
            ;;
        *)
            BAD=$((BAD+1))
            emit "[$N/$TOTAL] FAILED ($RC): $LABEL"
            ;;
    esac

    progress
}

remote() {
    LABEL=$1
    URL=$2
    FILE=/tmp/openatv-plugin-$$.sh

    note "Downloading installer: $LABEL"
    rm -f "$FILE"

    if ! wget -O "$FILE" "$URL" || [ ! -s "$FILE" ]; then
        note "Could not download $LABEL from $URL"
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
    opkg install python3-beautifulsoup4 python3-yt-dlp || return 1
}

install_xstreamity() {
    PKG=enigma2-plugin-extensions-xstreamity

    opkg list | awk '$1=="enigma2-plugin-extensions-xstreamity" {found=1; exit} END {exit !found}' || {
        note 'XStreamity missing from feed'
        return 1
    }

    opkg install "$PKG" || return 1
    opkg list-installed | grep -q '^enigma2-plugin-extensions-xstreamity '
}

install_ipaudiopro() {
    if ! command -v ffmpeg >/dev/null 2>&1; then
        opkg install ffmpeg || return 1
    fi

    MAJOR=$(ffmpeg -version 2>/dev/null | awk 'NR==1 {split($3,a,"."); print a[1]}')

    case "$MAJOR" in
        7|8)
            remote 'IPAudio Pro upstream' 'https://raw.githubusercontent.com/zKhadiri/IPAudioPro-Releases-/main/installer.sh'
            return $?
            ;;
        9)
            note 'FFmpeg 9: using upstream ff8 build, runtime compatibility not guaranteed'
            ;;
        *)
            note "Unsupported FFmpeg $MAJOR"
            return 1
            ;;
    esac

    PY=$(python3 -c 'import sys; print("%s.%s" % sys.version_info[:2])' 2>/dev/null) || return 1

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

    wget -q -O /tmp/atv-ipaudio-meta-$$.sh 'https://raw.githubusercontent.com/zKhadiri/IPAudioPro-Releases-/main/installer.sh' || return 1

    VER=$(sed -n 's/^VERSION=\([0-9][0-9.]*\).*$/\1/p' /tmp/atv-ipaudio-meta-$$.sh | head -n 1)
    rm -f /tmp/atv-ipaudio-meta-$$.sh

    [ -n "$VER" ] || return 1

    PKG="enigma2-plugin-extensions-ipaudiopro_${VER}_${ARCH}_py${PY}_ff${FF}.ipk"
    URL="https://raw.githubusercontent.com/zKhadiri/IPAudioPro-Releases-/main/v${VER}/python${PY}/${DIR}/${PKG}"
    FILE=/tmp/atv-ipaudiopro-$$.ipk

    wget -O "$FILE" "$URL" && [ -s "$FILE" ] || {
        rm -f "$FILE"
        return 1
    }

    opkg install "$FILE"
    RC=$?

    rm -f "$FILE"
    [ "$RC" -eq 0 ] || return "$RC"

    opkg list-installed | grep -q '^enigma2-plugin-extensions-ipaudiopro '
}

install_epggrabber() {
    remote 'EPG Grabber' 'https://raw.githubusercontent.com/zKhadiri/Epg-plugin/master/Download/installer.sh' || return 1
    [ -d /usr/lib/enigma2/python/Plugins/Extensions/EPGGrabber ]
}

install_ncam() {
    remote 'NCam 15.8' 'https://raw.githubusercontent.com/biko-73/Ncam_EMU/main/installer.sh' || return 1

    opkg list-installed | grep '^enigma2-plugin-softcams-ncam ' | grep -q '15\.8'
}

install_levi() {
    URL='https://raw.githubusercontent.com/levi-45/Levi45Emulator/main/enigma2-plugin-softcams-oscam-emu-pcsc-levi45_11968-803_all.ipk'
    FILE=/tmp/atv-levi45-$$.ipk

    if ! wget -O "$FILE" "$URL" || [ ! -s "$FILE" ]; then
        rm -f "$FILE"
        return 1
    fi

    opkg install --force-overwrite "$FILE"
    RC=$?

    rm -f "$FILE"
    note "Levi45 opkg exit status: $RC"

    sleep 6

    INSTALLED=$(opkg list-installed | grep -Ei '^enigma2-plugin[^ ]*oscam[^ ]*levi[^ ]* - ' | head -n 1)

    if [ -n "$INSTALLED" ]; then
        note "Levi45 installed: $INSTALLED"
        [ "$RC" -eq 0 ] && return 0
        return 2
    fi

    if [ -x /usr/bin/OSCam_11968-803 ]; then
        note 'OSCam binary is present, but opkg registration is incomplete'
        return 2
    fi

    return 1
}

run_install() {
    [ -r "$SELECTION" ] || {
        echo 'No selection file'
        exit 1
    }

    CHOICES=$(cat "$SELECTION")

    TOTAL=1
    for K in $CHOICES; do
        TOTAL=$((TOTAL+1))
    done

    N=0
    DONE=0
    GOOD=0
    BAD=0
    CHECK=0

    : > "$PROGRESS"

    emit "H. Hawwas Auto Installer v0.2.2 | Model: ${MODEL:-unknown} | $TOTAL steps"

    step 'opkg update' opkg update

    for K in $(seq 1 "$MAX"); do
        case " $CHOICES " in
            *" $K "*) : ;;
            *) continue ;;
        esac

        LABEL=$(name_of "$K")

        case "$K" in
            1) step "$LABEL" remote "$LABEL" 'https://raw.githubusercontent.com/biko-73/AjPanel/main/installer.sh' ;;
            2) step "$LABEL" remote "$LABEL" 'https://raw.githubusercontent.com/popking159/SubsSupportPro/refs/heads/main/myinstaller.sh' ;;
            3) step "$LABEL" transmission ;;
            4) step "$LABEL" remote "$LABEL" 'http://dreambox4u.com/dreamarabia/Transmission_e2/Transmission_e2.sh' ;;
            5) step "$LABEL" remote "$LABEL" 'https://raw.githubusercontent.com/biko-73/TMBD/main/installer.sh' ;;
            6) step "$LABEL" remote "$LABEL" 'https://raw.githubusercontent.com/fairbird/ArabicSavior/main/installer.sh' ;;
            7) step "$LABEL" remote "$LABEL" 'https://raw.githubusercontent.com/fairbird/RaedQuickSignal/main/installer.sh' ;;
            8) if [ "$DREAMONE" -eq 1 ]; then step "$LABEL" remote "$LABEL" 'https://xfayez95.github.io/audioshift/installer.sh'; fi ;;
            9) step "$LABEL" install_ipaudiopro ;;
            10) step "$LABEL" remote "$LABEL" 'https://raw.githubusercontent.com/popking159/customchannelselection/refs/heads/main/myinstaller.sh' ;;
            11) step "$LABEL" remote "$LABEL" 'https://raw.githubusercontent.com/popking159/skins/refs/heads/main/aglareatv/installer.sh' ;;
            12) step "$LABEL" remote "$LABEL" 'https://live-feed.net/enigma2/installer.sh' ;;
            13) step "$LABEL" install_epggrabber ;;
            14) step "$LABEL" install_xstreamity ;;
            15) step "$LABEL" remote "$LABEL" 'https://raw.githubusercontent.com/Najar1991/MixAudio_All/refs/heads/main/install.sh' ;;
            16) step "$LABEL" install_ncam ;;
            17) step "$LABEL" install_levi ;;
        esac
    done

    emit '===== INSTALLATION FINISHED ====='
    progress

    emit "Detailed log: $LOG"
    emit "Progress log: $PROGRESS"
    emit 'GSH2 was NOT installed.'
    emit 'Full receiver reboot in 5 seconds.'

    rm -f "$PIDFILE"
    sync
    sleep 5
    reboot
}

if [ "${1:-}" = '--run' ]; then
    if [ "$(id -u)" -ne 0 ] || ! command -v opkg >/dev/null 2>&1; then
        echo 'ERROR: Root + opkg-based OpenATV required'
        exit 1
    fi

    if ! command -v bash >/dev/null 2>&1; then
        opkg update && opkg install bash || exit 1
    fi

    run_install
    exit $?
fi

if [ ! -t 0 ]; then
    echo 'ERROR: Run from an interactive SSH/Telnet session.'
    exit 1
fi

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "Another OpenATV installation is running."
    echo "Monitor it: tail -n 30 -f $PROGRESS"
    exit 1
fi

if ! menu; then
    exit 0
fi

: > "$PROGRESS" || exit 1
: > "$LOG" || exit 1

nohup sh "$SELF" --run > "$LOG" 2>&1 < /dev/null &
RUN_PID=$!

printf '%s\n' "$RUN_PID" > "$PIDFILE"

echo "Installer started as PID $RUN_PID. Live progress follows:"
tail -n +1 -f "$PROGRESS"