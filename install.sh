#!/bin/sh
# OpenATV 8 - community installer for Dreambox One and other supported devices.
# EXPERIMENTAL: third-party installers may restart Enigma2, ask for input, or fail.
# Intended for newly flashed images. Do not run on a configured receiver without review.
# GSH2 is deliberately excluded.
# Version: 0.1.0
LOG=/home/root/openatv-install.log
FAILED=""
N=0
export PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH

note() { printf '\n%s\n' "$*"; }
step() {
    N=$((N+1))
    note "[$N] START: $1"
    LABEL=$1; shift
    "$@"
    RC=$?
    if [ "$RC" -eq 0 ]; then note "[$N] OK: $LABEL";
    else note "[$N] FAILED ($RC): $LABEL"; FAILED="$FAILED | $LABEL"; fi
    return 0
}
remote() {
    LABEL=$1; URL=$2
    note "--- Download: $LABEL"
    TMPFILE="/tmp/openatv-stage-$$.sh"
    rm -f "$TMPFILE"
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
softcams() {
    rm -f /tmp/feed
    if ! wget --no-check-certificate -q -O /tmp/feed https://raw.githubusercontent.com/SusanOV/softcamfeed/main/oea/feed || [ ! -s /tmp/feed ]; then
        note 'Softcam feed download failed'
        return 1
    fi
    bash -n /tmp/feed || return 1
    bash /tmp/feed || return 1
    opkg update || return 1
    LIST=/tmp/openatv-cams-$$.list
    opkg list > "$LIST" || { rm -f "$LIST"; return 1; }
    NCAM=$(awk '$1=="enigma2-plugin-softcams-ncam" || $1=="enigma2-softcams-ncam" || $1=="ncam" {print $1; exit}' "$LIST")
    OSCAM=$(awk '$1=="enigma2-plugin-softcams-oscam-master" || $1=="oscam-master" {print $1; exit}' "$LIST")
    rm -f "$LIST"
    CAM_RC=0
    if [ -n "$NCAM" ]; then
        note "NCam package: $NCAM"
        opkg install "$NCAM" || CAM_RC=1
    else
        note 'NCam not found in the compatible feed; skipped'
        CAM_RC=1
    fi
    if [ -n "$OSCAM" ]; then
        note "OSCam package: $OSCAM"
        opkg install "$OSCAM" || CAM_RC=1
    else
        note 'OSCam Master not found in the compatible feed; skipped'
        CAM_RC=1
    fi
    return "$CAM_RC"
}

note '=== OpenATV 8 automatic plugins installer ==='
if [ "$(id -u)" -ne 0 ] || ! command -v opkg >/dev/null 2>&1; then
    note 'ERROR: run as root on an opkg-based OpenATV image'
    exit 1
fi
if ! command -v bash >/dev/null 2>&1; then
    note 'Installing required bash shell'
    opkg update || exit 1
    opkg install bash || exit 1
fi
MODEL=$(cat /proc/stb/info/model 2>/dev/null)
note "Model: ${MODEL:-unknown} | Architecture: $(uname -m)"
if [ "$MODEL" = one ] || [ "$MODEL" = dreamone ] || [ "$MODEL" = dreamboxone ]; then note 'Profile: OpenATV Dreambox One'; else note 'Profile: OpenATV Other Devices'; fi

step 'opkg update' opkg update
step 'AJ Panel' remote 'AJ Panel' 'https://raw.githubusercontent.com/biko-73/AjPanel/main/installer.sh'
step 'SubsSupport Pro' remote 'SubsSupport Pro' 'https://raw.githubusercontent.com/popking159/SubsSupportPro/refs/heads/main/myinstaller.sh'
step 'Transmission Clients' opkg install transmission transmission-client python3-transmission-rpc xz
step 'Transmission optional libraries' opkg install python3-beautifulsoup4 python3-yt-dlp
step 'Transmission E2' remote 'Transmission E2' 'http://dreambox4u.com/dreamarabia/Transmission_e2/Transmission_e2.sh'
step 'TMDB' remote 'TMDB' 'https://raw.githubusercontent.com/biko-73/TMBD/main/installer.sh'
step 'Arabic Savior' remote 'Arabic Savior' 'https://raw.githubusercontent.com/fairbird/ArabicSavior/main/installer.sh'
step 'Raed Quick Signal' remote 'Raed Quick Signal' 'https://raw.githubusercontent.com/fairbird/RaedQuickSignal/main/installer.sh'
if [ "$MODEL" = one ] || [ "$MODEL" = dreamone ] || [ "$MODEL" = dreamboxone ]; then
    step 'AudioShift (Dreambox One only)' remote 'AudioShift' 'https://xfayez95.github.io/audioshift/installer.sh'
fi
step 'IPAudio Pro' remote 'IPAudio Pro' 'https://raw.githubusercontent.com/zKhadiri/IPAudioPro-Releases-/main/installer.sh'
step 'Custom Channel Selection' remote 'Custom Channel Selection' 'https://raw.githubusercontent.com/popking159/customchannelselection/refs/heads/main/myinstaller.sh'
step 'Aglare Skin' remote 'Aglare Skin' 'https://raw.githubusercontent.com/popking159/skins/refs/heads/main/aglareatv/installer.sh'
step 'LiveFeed OE' remote 'LiveFeed OE' 'https://live-feed.net/enigma2/installer.sh'
step 'Softcam feed + NCam + OSCam' softcams
step 'MixAudio (last)' remote 'MixAudio' 'https://raw.githubusercontent.com/Najar1991/MixAudio_All/refs/heads/main/install.sh'
note '=== INSTALLATION FINISHED ==='
if [ -n "$FAILED" ]; then note "Check failed steps:$FAILED"; else note 'All steps reported success'; fi
note "Full log: $LOG"
note 'GSH2 was NOT installed; install it separately after setup.'
note 'Full system reboot will start in 5 seconds.'
sync
sleep 5
reboot
RC=$?
note "ERROR: reboot command returned $RC. Please reboot manually."
exit "$RC"
