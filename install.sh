#!/bin/sh
# OpenATV Auto Setup v0.1.2 — EXPERIMENTAL
# For opkg-based OpenATV 8 images; external plugins must be reviewed before use.
# GSH2 is deliberately NOT included. This script reboots even if steps fail.

export PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH
LOG=/home/root/openatv-install.log
N=0
FAILED=""

note() { printf '\n%s\n' "$*"; }

step() {
    N=$((N + 1))
    LABEL=$1
    shift
    note "[$N] START: $LABEL"

    "$@"
    RC=$?

    if [ "$RC" -eq 0 ]; then
        note "[$N] OK: $LABEL"
    else
        note "[$N] FAILED ($RC): $LABEL"
        FAILED="$FAILED | $LABEL"
    fi
    return 0
}

remote() {
    LABEL=$1
    URL=$2
    TMP="/tmp/openatv-plugin-$$.sh"

    note "Download: $LABEL"
    rm -f "$TMP"

    if ! wget -q -O "$TMP" "$URL" || [ ! -s "$TMP" ]; then
        note "FAILED to download $URL"
        rm -f "$TMP"
        return 1
    fi

    bash "$TMP"
    RC=$?
    rm -f "$TMP"
    return "$RC"
}

install_ipaudiopro() {
    # Upstream only ships FFmpeg 7/8 builds (as checked 2026-10-28).
    # FFmpeg 9: attempt the upstream FFmpeg 8 build for this Python/CPU.
    # Package installation may succeed but runtime compatibility is unverified.

    if ! command -v ffmpeg >/dev/null 2>&1; then
        opkg install ffmpeg || return 1
    fi

    FFMPEG_MAJOR=$(ffmpeg -version 2>/dev/null | awk 'NR==1 {split($3,a,"."); print a[1]}')

    case "$FFMPEG_MAJOR" in
        7|8)
            remote 'IPAudio Pro upstream' 'https://raw.githubusercontent.com/zKhadiri/IPAudioPro-Releases-/main/installer.sh'
            return $?
            ;;
        9)
            note 'FFmpeg 9 detected: trying compatible-architecture IPAudioPro package built for FFmpeg 8 (UNVERIFIED runtime)'
            ;;
        *)
            note "Unsupported FFmpeg version: $FFMPEG_MAJOR"
            return 1
            ;;
    esac

    PY=$(python3 -c 'import sys; print("%s.%s" % sys.version_info[:2])' 2>/dev/null) || return 1

    case "$PY" in
        3.12) FF_PKG=7.1 ;;
        3.13|3.14) FF_PKG=8.0 ;;
        *)
            note "No IPAudioPro package for Python $PY"
            return 1
            ;;
    esac

    MACHINE=$(uname -m)

    case "$MACHINE" in
        aarch64)
            CPU_DIR=aarch64
            PKG_ARCH=aarch64
            ;;
        *mips*)
            CPU_DIR=mipsel
            PKG_ARCH=mips32el
            ;;
        arm*)
            CPU_DIR=arm
            PKG_ARCH=""

            for A in cortexa15hf-neon-vfpv4 cortexa9hf-neon cortexa7hf-vfp armv7ahf-neon; do
                if opkg print-architecture 2>/dev/null | grep -q " $A "; then
                    PKG_ARCH=$A
                    break
                fi
                if ls /etc/opkg 2>/dev/null | grep -q "$A"; then
                    PKG_ARCH=$A
                    break
                fi
            done

            if [ -z "$PKG_ARCH" ]; then
                note 'Unsupported ARM package architecture'
                return 1
            fi
            ;;
        *)
            note "Unsupported CPU architecture: $MACHINE"
            return 1
            ;;
    esac

    # Read current upstream release version.
    TMPINFO=/tmp/ipaudio-release-$$.sh

    if ! wget -q -O "$TMPINFO" 'https://raw.githubusercontent.com/zKhadiri/IPAudioPro-Releases-/main/installer.sh'; then
        rm -f "$TMPINFO"
        return 1
    fi

    VERSION=$(sed -n 's/^VERSION=\([0-9][0-9.]*\).*$/\1/p' "$TMPINFO" | head -n 1)
    rm -f "$TMPINFO"

    [ -n "$VERSION" ] || {
        note 'Cannot determine IPAudioPro release'
        return 1
    }

    PACKAGE="enigma2-plugin-extensions-ipaudiopro_${VERSION}_${PKG_ARCH}_py${PY}_ff${FF_PKG}.ipk"
    URL="https://raw.githubusercontent.com/zKhadiri/IPAudioPro-Releases-/main/v${VERSION}/python${PY}/${CPU_DIR}/${PACKAGE}"
    TMPIPK="/tmp/atv-ipaudiopro-$$.ipk"

    note "Trying upstream release: $PACKAGE"

    if ! wget -q -O "$TMPIPK" "$URL" || [ ! -s "$TMPIPK" ]; then
        note 'This CPU/Python/FFmpeg build is unavailable upstream'
        rm -f "$TMPIPK"
        return 1
    fi

    opkg install "$TMPIPK"
    RC=$?
    rm -f "$TMPIPK"

    [ "$RC" -eq 0 ] || return "$RC"

    opkg list-installed | grep -q '^enigma2-plugin-extensions-ipaudiopro '
}

install_ncam() {
    remote 'NCam 15.8' 'https://raw.githubusercontent.com/biko-73/Ncam_EMU/main/installer.sh' || return 1

    PKG=$(opkg list-installed | grep '^enigma2-plugin-softcams-ncam ' | head -n 1)

    note "NCam: $PKG"

    case "$PKG" in
        *15.8*) return 0 ;;
        *) return 1 ;;
    esac
}

# Levi45 may install dependencies in the background.
install_levi() {
    remote 'OSCam Levi45' 'https://raw.githubusercontent.com/levi-45/Levi45Emulator/main/installer.sh'
    ORIGINAL_RC=$?

    [ "$ORIGINAL_RC" -eq 0 ] || note "Levi45 installer returned $ORIGINAL_RC"

    sleep 8

    wait_for_pkg_workers 240 || note 'WARNING: packaging work still active after 240 seconds'

    PKG=$(opkg list-installed | grep -Ei '^enigma2-plugin.*oscam.*levi' | head -n 1)

    note "OSCam Levi45 package: ${PKG:-NOT PRESENT}"

    [ -n "$PKG" ] || return 1
    return 0
}

wait_for_pkg_workers() {
    LIMIT=${1:-180}
    COUNT=0

    while [ "$COUNT" -lt "$LIMIT" ]; do
        P=$(ps w 2>/dev/null || ps)

        if ! printf '%s\n' "$P" | grep -Eq '[o]pkg (install|update|remove)|[p]csc_install|[l]ibusb_install'; then
            return 0
        fi

        if [ "$COUNT" -eq 0 ]; then
            note 'Waiting for outstanding package operations...'
        fi

        sleep 4
        COUNT=$((COUNT + 4))
    done

    return 1
}

note '===== OpenATV Auto Setup v0.1.2 ====='

if [ "$(id -u)" -ne 0 ] || ! command -v opkg >/dev/null 2>&1; then
    note 'ERROR: this requires root and opkg-based OpenATV'
    exit 1
fi

if ! command -v bash >/dev/null 2>&1; then
    opkg update && opkg install bash || exit 1
fi

MODEL=$(cat /proc/stb/info/model 2>/dev/null)

note "Model: ${MODEL:-unknown} | Arch: $(uname -m)"

case "$MODEL" in
    one|dreamone|dreamboxone)
        DREAMONE=1
        note 'Profile: OpenATV Dreambox One'
        ;;
    *)
        DREAMONE=0
        note 'Profile: OpenATV Other Devices'
        ;;
esac

step 'opkg update' opkg update

step 'AJ Panel' remote 'AJ Panel' 'https://raw.githubusercontent.com/biko-73/AjPanel/main/installer.sh'

step 'SubsSupport Pro' remote 'SubsSupport Pro' 'https://raw.githubusercontent.com/popking159/SubsSupportPro/refs/heads/main/myinstaller.sh'

step 'Transmission Clients' opkg install transmission transmission-client python3-transmission-rpc xz

step 'Transmission Libraries' opkg install python3-beautifulsoup4 python3-yt-dlp

step 'Transmission E2' remote 'Transmission E2' 'http://dreambox4u.com/dreamarabia/Transmission_e2/Transmission_e2.sh'

step 'TMDB' remote 'TMDB' 'https://raw.githubusercontent.com/biko-73/TMBD/main/installer.sh'

step 'Arabic Savior' remote 'Arabic Savior' 'https://raw.githubusercontent.com/fairbird/ArabicSavior/main/installer.sh'

step 'Raed Quick Signal' remote 'Raed Quick Signal' 'https://raw.githubusercontent.com/fairbird/RaedQuickSignal/main/installer.sh'

if [ "$DREAMONE" -eq 1 ]; then
    step 'AudioShift' remote 'AudioShift' 'https://xfayez95.github.io/audioshift/installer.sh'
fi

step 'IPAudio Pro' install_ipaudiopro

step 'Custom Channel Selection' remote 'Custom Channel Selection' 'https://raw.githubusercontent.com/popking159/customchannelselection/refs/heads/main/myinstaller.sh'

step 'Aglare Skin' remote 'Aglare Skin' 'https://raw.githubusercontent.com/popking159/skins/refs/heads/main/aglareatv/installer.sh'

step 'LiveFeed OE' remote 'LiveFeed OE' 'https://live-feed.net/enigma2/installer.sh'

# MixAudio BEFORE NCam and Levi45 to avoid opkg.lock conflict.
step 'MixAudio' remote 'MixAudio' 'https://raw.githubusercontent.com/Najar1991/MixAudio_All/refs/heads/main/install.sh'

step 'NCam 15.8' install_ncam

step 'OSCam Levi45' install_levi

note '===== INSTALLATION FINISHED ====='

if [ -n "$FAILED" ]; then
    note "FAILED STEPS:$FAILED"
else
    note 'All steps reported OK'
fi

note "Report remains on disk after reboot: $LOG"
note 'GSH2 is NOT included in this setup.'
note 'Rebooting the entire receiver in 5 seconds, even if some steps failed.'

sync
sleep 5
reboot
exit 0