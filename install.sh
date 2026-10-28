#!/bin/sh
# OpenATV Auto Setup v0.1.4
# OpenATV 8 / opkg - Experimental
# GSH2 is deliberately excluded.
# Progress = completed steps, not download percentage.

export PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH

LOG=/home/root/openatv-install.log
PROGRESS=/home/root/openatv-progress.log

N=0
DONE=0
GOOD=0
BAD=0
CHECK=0
FAILED=""
TOTAL=17

note() {
    printf '\n%s\n' "$*"
}

emit() {
    printf '%s\n' "$*" | tee -a "$PROGRESS"
}

progress() {
    PCT=$((DONE * 100 / TOTAL))
    FILLED=$((DONE * 20 / TOTAL))
    POS=0
    BAR=""

    while [ "$POS" -lt 20 ]; do
        if [ "$POS" -lt "$FILLED" ]; then
            BAR="${BAR}#"
        else
            BAR="${BAR}-"
        fi
        POS=$((POS + 1))
    done

    emit "PROGRESS [$BAR] ${PCT}% | $DONE/$TOTAL done | OK:$GOOD CHECK:$CHECK FAILED:$BAD"
}

heartbeat() {
    HB_LABEL=$1
    HB_SECONDS=0

    while :; do
        sleep 20
        HB_SECONDS=$((HB_SECONDS + 20))
        emit "  ... $HB_LABEL still running ($HB_SECONDS seconds)"
    done
}

step() {
    N=$((N + 1))
    STEP_LABEL=$1
    shift

    emit "[$N/$TOTAL] START: $STEP_LABEL"
    note "[$N] START: $STEP_LABEL"

    heartbeat "$STEP_LABEL" &
    WATCH_PID=$!

    "$@"
    RC=$?

    kill "$WATCH_PID" 2>/dev/null || :
    wait "$WATCH_PID" 2>/dev/null || :

    DONE=$((DONE + 1))

    case "$RC" in
        0)
            GOOD=$((GOOD + 1))
            emit "[$N/$TOTAL] OK: $STEP_LABEL"
            note "[$N] OK: $STEP_LABEL"
            ;;
        2)
            CHECK=$((CHECK + 1))
            emit "[$N/$TOTAL] CHECK: $STEP_LABEL"
            note "[$N] CHECK: $STEP_LABEL"
            ;;
        *)
            BAD=$((BAD + 1))
            FAILED="$FAILED | $STEP_LABEL"
            emit "[$N/$TOTAL] FAILED ($RC): $STEP_LABEL"
            note "[$N] FAILED ($RC): $STEP_LABEL"
            ;;
    esac

    progress
    return 0
}

remote() {
    LABEL=$1
    URL=$2
    TMP="/tmp/openatv-plugin-$$.sh"

    rm -f "$TMP"
    note "Downloading installer: $LABEL"

    if ! wget -O "$TMP" "$URL" || [ ! -s "$TMP" ]; then
        note "DOWNLOAD FAILED: $URL"
        rm -f "$TMP"
        return 1
    fi

    note "Downloaded $(wc -c < "$TMP") bytes"
    note "Running: $LABEL"

    bash "$TMP"
    RC=$?

    rm -f "$TMP"
    return "$RC"
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
            note 'Waiting for background package operations...'
        fi

        sleep 4
        COUNT=$((COUNT + 4))
    done

    return 1
}

# IPAudio Pro: preserve the FFmpeg 9 workaround
# that worked on the Dreambox One.
install_ipaudiopro() {
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
            note 'FFmpeg 9 detected. Trying IPAudioPro FFmpeg 8 build.'
            note 'Runtime compatibility remains unverified on other devices.'
            ;;
        *)
            note "Unsupported FFmpeg: $FFMPEG_MAJOR"
            return 1
            ;;
    esac

    PY=$(python3 -c 'import sys; print("%s.%s" % sys.version_info[:2])' 2>/dev/null) || return 1

    case "$PY" in
        3.12) FF_PKG=7.1 ;;
        3.13|3.14) FF_PKG=8.0 ;;
        *)
            note "Unsupported Python: $PY"
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
                if opkg print-architecture 2>/dev/null | grep -q " $A " || ls /etc/opkg 2>/dev/null | grep -q "$A"; then
                    PKG_ARCH=$A
                    break
                fi
            done

            if [ -z "$PKG_ARCH" ]; then
                note 'ARM package architecture not found'
                return 1
            fi
            ;;
        *)
            note "Unsupported CPU: $MACHINE"
            return 1
            ;;
    esac

    TMPINFO="/tmp/ipaudio-release-$$.sh"

    if ! wget -O "$TMPINFO" 'https://raw.githubusercontent.com/zKhadiri/IPAudioPro-Releases-/main/installer.sh'; then
        rm -f "$TMPINFO"
        return 1
    fi

    VERSION=$(sed -n 's/^VERSION=\([0-9][0-9.]*\).*$/\1/p' "$TMPINFO" | head -n 1)
    rm -f "$TMPINFO"

    if [ -z "$VERSION" ]; then
        note 'IPAudioPro release version not found'
        return 1
    fi

    PACKAGE="enigma2-plugin-extensions-ipaudiopro_${VERSION}_${PKG_ARCH}_py${PY}_ff${FF_PKG}.ipk"
    URL="https://raw.githubusercontent.com/zKhadiri/IPAudioPro-Releases-/main/v${VERSION}/python${PY}/${CPU_DIR}/${PACKAGE}"
    TMPIPK="/tmp/atv-ipaudiopro-$$.ipk"

    note "Downloading: $PACKAGE"

    if ! wget -O "$TMPIPK" "$URL" || [ ! -s "$TMPIPK" ]; then
        note "Package unavailable: $URL"
        rm -f "$TMPIPK"
        return 1
    fi

    note "Downloaded $(wc -c < "$TMPIPK") bytes"
    note 'Installing IPAudio Pro...'

    opkg install "$TMPIPK"
    RC=$?

    rm -f "$TMPIPK"

    [ "$RC" -eq 0 ] || return "$RC"

    opkg list-installed | grep -q '^enigma2-plugin-extensions-ipaudiopro '
}

install_xstreamity() {
    PKG=enigma2-plugin-extensions-xstreamity

    note 'Finding XStreamity in configured OpenATV feed...'

    AVAILABLE=$(opkg list 2>/dev/null | awk '$1=="enigma2-plugin-extensions-xstreamity" {print $2; exit}')

    if [ -z "$AVAILABLE" ]; then
        note 'XStreamity not found in configured OpenATV feed'
        return 1
    fi

    note "XStreamity feed version: $AVAILABLE"

    opkg install "$PKG" || return 1

    INSTALLED=$(opkg list-installed | grep '^enigma2-plugin-extensions-xstreamity ' | head -n 1)

    if [ -z "$INSTALLED" ]; then
        note 'XStreamity package not registered'
        return 1
    fi

    note "XStreamity installed: $INSTALLED"
    return 0
}

install_ncam() {
    remote 'NCam 15.8' 'https://raw.githubusercontent.com/biko-73/Ncam_EMU/main/installer.sh' || return 1

    PKG=$(opkg list-installed | grep '^enigma2-plugin-softcams-ncam ' | head -n 1)

    note "NCam: ${PKG:-NOT PRESENT}"

    case "$PKG" in
        *15.8*) return 0 ;;
        *) return 1 ;;
    esac
}

# Direct IPK installation for OSCam Levi45.
# Avoids the upstream installer wrapper.
install_levi() {
    PKGURL='https://raw.githubusercontent.com/levi-45/Levi45Emulator/main/enigma2-plugin-softcams-oscam-emu-pcsc-levi45_11968-803_all.ipk'
    TMPIPK="/tmp/atv-levi45-$$.ipk"

    note 'Downloading OSCam Levi45 11968 IPK...'

    if ! wget -O "$TMPIPK" "$PKGURL" || [ ! -s "$TMPIPK" ]; then
        note 'OSCam Levi45 IPK download failed'
        rm -f "$TMPIPK"
        return 1
    fi

    note "Downloaded $(wc -c < "$TMPIPK") bytes"
    note 'Installing OSCam Levi45 through opkg...'

    opkg install --force-overwrite "$TMPIPK"
    INSTALL_RC=$?

    rm -f "$TMPIPK"

    note "OSCam opkg exit status: $INSTALL_RC"

    # Wait for any package post-install background tasks.
    sleep 10

    if ! wait_for_pkg_workers 180; then
        note 'Package tasks still active; status uncertain'
        return 2
    fi

    sleep 3

    INSTALLED=$(opkg list-installed | grep -Ei '^enigma2-plugin[^ ]*oscam[^ ]*levi[^ ]* - ' | head -n 1)

    if [ -n "$INSTALLED" ]; then
        note "OSCam Levi45 registered: $INSTALLED"

        if [ "$INSTALL_RC" -eq 0 ]; then
            return 0
        fi

        note 'Package present, but opkg returned an error'
        return 2
    fi

    FOUND=$(find /usr/bin /usr/softcams /usr/softcam /usr/script /etc/init.d -maxdepth 2 -type f -iname '*oscam*' 2>/dev/null | head -n 1)

    if [ -n "$FOUND" ]; then
        note "OSCam-related file exists: $FOUND"
        note 'Package registration not confirmed'
        return 2
    fi

    note 'OSCam Levi45 package not registered'
    return 1
}

# Main installation
: > "$PROGRESS" || exit 1

emit '===== OpenATV Auto Setup v0.1.4 ====='

if [ "$(id -u)" -ne 0 ] || ! command -v opkg >/dev/null 2>&1; then
    note 'ERROR: root and opkg-based OpenATV required'
    exit 1
fi

if ! command -v bash >/dev/null 2>&1; then
    opkg update && opkg install bash || exit 1
fi

MODEL=$(cat /proc/stb/info/model 2>/dev/null)

note "Model: ${MODEL:-unknown} | Architecture: $(uname -m)"

case "$MODEL" in
    one|dreamone|dreamboxone)
        DREAMONE=1
        TOTAL=18
        note 'Profile: Dreambox One'
        ;;
    *)
        DREAMONE=0
        TOTAL=17
        note 'Profile: Other OpenATV device'
        ;;
esac

progress

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

# Install from OpenATV feed before softcams.
step 'XStreamity (OpenATV feed)' install_xstreamity

# Keep MixAudio before softcams.
step 'MixAudio' remote 'MixAudio' 'https://raw.githubusercontent.com/Najar1991/MixAudio_All/refs/heads/main/install.sh'

step 'NCam 15.8' install_ncam

# Last package: direct IPK install.
step 'OSCam Levi45 IPK' install_levi

emit '===== INSTALLATION FINISHED ====='
note '===== INSTALLATION FINISHED ====='

progress

if [ -n "$FAILED" ]; then
    note "Failed steps:$FAILED"
else
    note 'No steps returned FAILED'
fi

emit "Detailed log: $LOG"
emit "Progress log: $PROGRESS"
emit 'GSH2 was not installed.'
emit 'Full receiver reboot in 5 seconds.'

sync
sleep 5
reboot
exit 0