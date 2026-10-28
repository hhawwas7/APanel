 #!/bin/sh
# OpenATV 8 Auto Setup
# Version: 0.1.1
# Dreambox One + Other OpenATV Devices
# GSH2 is installed separately.

LOG=/home/root/openatv-install.log
FAILED=""
N=0
export PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH

note() {
    printf '\n%s\n' "$*"
}

step() {
    N=$((N+1))
    note "[$N] START: $1"
    LABEL=$1
    shift

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
    TMPFILE="/tmp/openatv-stage-$$.sh"

    rm -f "$TMPFILE"
    note "--- Download: $LABEL"

    if wget --no-check-certificate -q -O "$TMPFILE" "$URL" && [ -s "$TMPFILE" ]; then
        bash "$TMPFILE"
        RC=$?
    else
        note "Download failed: $URL"
        RC=1
    fi

    rm -f "$TMPFILE"
    return "$RC"
}

install_ncam_release() {
    remote 'NCam stable' 'https://raw.githubusercontent.com/biko-73/Ncam_EMU/main/installer.sh' || return 1

    INSTALLED=$(opkg list-installed | grep -E '^enigma2-plugin-softcams-ncam[[:space:]]+-' | head -n 1)

    if [ -z "$INSTALLED" ]; then
        note "NCam package missing after installer"
        return 1
    fi

    note "NCam installed: $INSTALLED"

    case "$INSTALLED" in
        *15.8*) return 0 ;;
        *)
            note "WARNING: NCam is not 15.8"
            return 1
            ;;
    esac
}

install_levi45() {
    remote 'OSCam Levi45' 'https://raw.githubusercontent.com/levi-45/Levi45Emulator/main/installer.sh' || return 1

    INSTALLED=$(opkg list-installed | grep -E '^enigma2-plugin-softcams-oscam-emu-pcsc-levi45[[:space:]]+-' | head -n 1)

    if [ -z "$INSTALLED" ]; then
        note "OSCam Levi45 package missing after installer"
        return 1
    fi

    note "OSCam Levi45 installed: $INSTALLED"
}

note "=== OpenATV Auto Setup v0.1.1 ==="

if [ "$(id -u)" -ne 0 ] || ! command -v opkg >/dev/null 2>&1; then
    note "ERROR: OpenATV with opkg required"
    exit 1
fi

if ! command -v bash >/dev/null 2>&1; then
    opkg update || exit 1
    opkg install bash || exit 1
fi

MODEL=$(cat /proc/stb/info/model 2>/dev/null)

note "Model: ${MODEL:-unknown}"
note "Architecture: $(uname -m)"

if [ "$MODEL" = "one" ] || [ "$MODEL" = "dreamone" ] || [ "$MODEL" = "dreamboxone" ]; then
    note "Profile: OpenATV Dreambox One"
else
    note "Profile: OpenATV Other Devices"
fi

# 1. Package Update
step "opkg update" opkg update

# 2. AJ Panel
step "AJ Panel" remote "AJ Panel" "https://raw.githubusercontent.com/biko-73/AjPanel/main/installer.sh"

# 3. SubsSupport Pro
step "SubsSupport Pro" remote "SubsSupport Pro" "https://raw.githubusercontent.com/popking159/SubsSupportPro/refs/heads/main/myinstaller.sh"

# 4. Transmission Clients
step "Transmission Clients" opkg install transmission transmission-client python3-transmission-rpc xz

# 5. Transmission Libraries
step "Transmission Libraries" opkg install python3-beautifulsoup4 python3-yt-dlp

# 6. Transmission E2
step "Transmission E2" remote "Transmission E2" "http://dreambox4u.com/dreamarabia/Transmission_e2/Transmission_e2.sh"

# 7. TMDB
step "TMDB" remote "TMDB" "https://raw.githubusercontent.com/biko-73/TMBD/main/installer.sh"

# 8. Arabic Savior
step "Arabic Savior" remote "Arabic Savior" "https://raw.githubusercontent.com/fairbird/ArabicSavior/main/installer.sh"

# 9. Raed Quick Signal
step "Raed Quick Signal" remote "Raed Quick Signal" "https://raw.githubusercontent.com/fairbird/RaedQuickSignal/main/installer.sh"

# 10. AudioShift - Dreambox One ONLY
if [ "$MODEL" = "one" ] || [ "$MODEL" = "dreamone" ] || [ "$MODEL" = "dreamboxone" ]; then
    step "AudioShift" remote "AudioShift" "https://xfayez95.github.io/audioshift/installer.sh"
fi

# 11. IPAudio Pro
step "IPAudio Pro" remote "IPAudio Pro" "https://raw.githubusercontent.com/zKhadiri/IPAudioPro-Releases-/main/installer.sh"

# 12. Custom Channel Selection
step "Custom Channel Selection" remote "Custom Channel Selection" "https://raw.githubusercontent.com/popking159/customchannelselection/refs/heads/main/myinstaller.sh"

# 13. Aglare Skin
step "Aglare Skin" remote "Aglare Skin" "https://raw.githubusercontent.com/popking159/skins/refs/heads/main/aglareatv/installer.sh"

# 14. LiveFeed OE
step "LiveFeed OE" remote "LiveFeed OE" "https://live-feed.net/enigma2/installer.sh"

# 15. NCam 15.8
step "NCam 15.8" install_ncam_release

# 16. OSCam Levi45
step "OSCam Levi45" install_levi45

# 17. MixAudio LAST
step "MixAudio LAST" remote "MixAudio" "https://raw.githubusercontent.com/Najar1991/MixAudio_All/refs/heads/main/install.sh"

# Installation Report
note "=== INSTALLATION FINISHED ==="

if [ -n "$FAILED" ]; then
    note "FAILED STEPS: $FAILED"
else
    note "All steps reported success"
fi

note "Full log: $LOG"
note "GSH2 NOT installed"
note "Full system reboot in 5 seconds"

sync
sleep 5
reboot

RC=$?
note "ERROR: reboot returned $RC"
exit "$RC"