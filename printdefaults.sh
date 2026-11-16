#!/bin/bash

# ==============================================================================
# PRINTER DEFAULTS INTERACTIVE WRAPPER
# Supports: Canon, Ricoh, Sharp, Kyocera
#
# Layout/finishing/accounting-enable can be applied globally (all users, via
# lpadmin + sudo) or per user (~/.cups/lpoptions). The user code is ALWAYS
# stored per user.
#
# Several queues can be selected at once (comma-separated, e.g. 1,2,4) and get
# the same defaults; when finished you are offered another run for more printers.
#
# Usage: printdefaults.sh [-a]
#   (default)  easy mode: simple menus for layout, finishing and accounting
#   -a         advanced mode: step through each setting and pick from the
#              values the printer's PPD offers (staple position, punch type...)
#
# You are first asked whether to also use PaperCut's cups-webui (instead of,
# before, or after this script; default: not at all).
# ==============================================================================

ADVANCED=0
while getopts "ah" OPT; do
    case "$OPT" in
        a) ADVANCED=1 ;;
        *) echo "Usage: $0 [-a]   (-a = advanced mode)"; exit 1 ;;
    esac
done

# 0. OPTIONAL: PAPERCUT CUPS WEB UI
# PaperCut's cups-webui is a browser UI that runs as the logged-in user (no sudo)
# and writes to ~/.cups/lpoptions. It keeps running until CTRL-C is pressed.
WEBUI_URL="https://github.com/PaperCutSoftware/cups-web-interface/raw/main/bin/cups-webui"

# run_webui: download cups-webui to a temp dir, clear the quarantine flag, run it
# with -open, then clean up. Returns non-zero if the download fails.
run_webui() {
    local dir bin
    dir=$(mktemp -d) || return 1
    bin="$dir/cups-webui"
    echo "[*] Downloading PaperCut CUPS web UI..."
    if ! curl -fsSL -o "$bin" "$WEBUI_URL"; then
        echo "[-] Download failed: $WEBUI_URL"
        rm -rf "$dir"
        return 1
    fi
    chmod +x "$bin"
    xattr -d com.apple.quarantine "$bin" 2>/dev/null
    echo "[+] Starting the web UI (runs as $USER; settings are saved to ~/.cups/lpoptions)."
    echo "    Press CTRL-C to stop it and continue."
    trap ':' INT    # let CTRL-C stop the web UI without aborting this script
    "$bin" -open
    trap - INT
    rm -rf "$dir"
    echo ""
    echo "[+] Web UI stopped."
}

echo "PaperCut CUPS web UI (no sudo; saves to ~/.cups/lpoptions):"
echo "  [1] Use it instead of this script"
echo "  [2] Run it before this script"
echo "  [3] Run it after this script"
echo "  [4] Do not use it [Default]"
echo ""
read -p "Enter selection [4]: " WEBUI_IDX
case "${WEBUI_IDX:-4}" in
    1) WEBUI_MODE="instead" ;;
    2) WEBUI_MODE="before" ;;
    3) WEBUI_MODE="after" ;;
    *) WEBUI_MODE="none" ;;
esac
echo ""

case "$WEBUI_MODE" in
    instead) run_webui || exit 1; exit 0 ;;
    before)  run_webui || echo "[!] Continuing with this script." ; echo "" ;;
esac

# ==============================================================================
# HELPERS (operate on the queue most recently passed to load_queue)
# ==============================================================================

# has_opt NAME           -> option exists in the driver
# has_choice NAME VALUE  -> option exists and offers VALUE
has_opt() { echo "$OPTIONS" | grep -q "^$1/"; }
has_choice() { echo "$OPTIONS" | grep "^$1/" | tr -d '*' | grep -qw -- "$2"; }

# load_queue QUEUE: fetch the queue's options and identify the vendor from
# driver-specific option names. Sets QUEUE, PPD, OPTIONS and VENDOR.
load_queue() {
    QUEUE="$1"
    PPD="/etc/cups/ppd/$QUEUE.ppd"
    OPTIONS=$(lpoptions -p "$QUEUE" -l)
    if [ -z "$OPTIONS" ]; then
        echo "[-] Could not retrieve options for queue '$QUEUE'."
        return 1
    fi
    if   has_opt CNColorMode;      then VENDOR="Canon"
    elif has_opt RIEnableUserCode; then VENDOR="Ricoh"
    elif has_opt ARCMode;          then VENDOR="Sharp"
    elif has_opt KCStaple || has_opt KmManagment; then VENDOR="Kyocera"
    else
        echo "[-] '$QUEUE': unsupported driver (no Canon, Ricoh, Sharp or Kyocera options found)."
        return 1
    fi
}

# label_of KEY VALUE -> human label from the queue's PPD, or VALUE if unknown
label_of() {
    local l=""
    [ -r "$PPD" ] && l=$(grep -F -m1 "*$1 $2/" "$PPD" | sed 's/^[^\/]*\///; s/:.*//')
    echo "${l:-$2}"
}

# ==============================================================================
# SETTING MAP
# Each setting has up to two driver keys (K1, K2) with an "on" and "off" value.
# Easy mode applies ON/OFF per the simple menus; advanced mode lets you pick any
# value the PPD offers for each key (ON values are shown as "recommended").
# ==============================================================================
define_settings() {
    case "$VENDOR" in
        Canon)
            DUPLEX_K1=CNDuplex;     DUPLEX_ON1=DuplexFront;   DUPLEX_OFF1=None
            COLOR_K1=CNColorMode;   COLOR_ON1=color;          COLOR_OFF1=mono
            STAPLE_K1=CNStaple;     STAPLE_ON1=True;          STAPLE_OFF1=False
            STAPLE_K2=StapleLocation; STAPLE_ON2=TopLeft;     STAPLE_OFF2=""
            PUNCH_K1=CNPuncher;     PUNCH_ON1=$(echo "$OPTIONS" | grep "^CNPuncher/" | grep -oE "PUNU23|PUNF24|PUNU24" | head -n1); PUNCH_OFF1=None
            PUNCH_K2=CNMultiPunch;  PUNCH_ON2=PUNU3;          PUNCH_OFF2=Off ;;
        Kyocera)
            DUPLEX_K1=Duplex;       DUPLEX_ON1=DuplexNoTumble; DUPLEX_OFF1=None
            COLOR_K1=ColorModel;    COLOR_ON1=CMYK;           COLOR_OFF1=Gray
            STAPLE_K1=KCStaple;     STAPLE_ON1=Upperleft;     STAPLE_OFF1=None
            STAPLE_K2="";           STAPLE_ON2="";            STAPLE_OFF2=""
            PUNCH_K1=KCPunch;       PUNCH_ON1=3Hole;          PUNCH_OFF1=None
            PUNCH_K2="";            PUNCH_ON2="";             PUNCH_OFF2="" ;;
        Ricoh)
            DUPLEX_K1=Duplex;       DUPLEX_ON1=DuplexNoTumble; DUPLEX_OFF1=None
            COLOR_K1=ColorModel;    COLOR_ON1=CMYK;           COLOR_OFF1=Gray
            STAPLE_K1=StapleLocation; STAPLE_ON1=UpperLeft;   STAPLE_OFF1=None
            STAPLE_K2="";           STAPLE_ON2="";            STAPLE_OFF2=""
            PUNCH_K1=RIPunch;       PUNCH_ON1=Left3;          PUNCH_OFF1=None
            PUNCH_K2="";            PUNCH_ON2="";             PUNCH_OFF2="" ;;
        Sharp)
            DUPLEX_K1=Duplex;       DUPLEX_ON1=DuplexNoTumble; DUPLEX_OFF1=None
            COLOR_K1=ARCMode;       COLOR_ON1=CMColor;        COLOR_OFF1=CMBW
            STAPLE_K1=ARStaple;     STAPLE_ON1=Staple1;       STAPLE_OFF1=Staple0
            STAPLE_K2="";           STAPLE_ON2="";            STAPLE_OFF2=""
            PUNCH_K1=ARPunch;       PUNCH_ON1=Punch3;         PUNCH_OFF1=PunchNone
            PUNCH_K2="";            PUNCH_ON2="";             PUNCH_OFF2="" ;;
    esac

    # Drop second keys the driver doesn't actually have
    local S k
    for S in STAPLE PUNCH; do
        k="${S}_K2"
        if [ -n "${!k}" ] && ! has_opt "${!k}"; then printf -v "$k" ''; fi
    done
}

# pick_option KEY TITLE RECOMMENDED DEFAULT
# Shows the PPD's values for KEY as a numbered list; Enter selects DEFAULT.
# Sets PICK_VAL and PICK_LABEL.
pick_option() {
    local key="$1" title="$2" rec="$3" def="$4" v n=0 defidx=1 ppddef="" extra
    local vals=()
    for v in $(echo "$OPTIONS" | grep "^$key/" | sed 's/^[^:]*: *//'); do
        case "$v" in Custom.*) continue ;; esac
        case "$v" in \**) ppddef="${v#\*}"; v="${v#\*}" ;; esac
        vals+=("$v")
    done
    echo ""
    echo "$title ($key):"
    for v in "${vals[@]}"; do
        n=$((n+1)); extra=""
        [ "$v" = "$ppddef" ] && extra="$extra [current]"
        [ "$v" = "$rec" ] && extra="$extra [recommended]"
        [ "$v" = "$def" ] && defidx=$n
        printf "  [%d] %s (%s)%s\n" "$n" "$(label_of "$key" "$v")" "$v" "$extra"
    done
    while true; do
        read -p "Enter selection [$defidx]: " SEL
        SEL=${SEL:-$defidx}
        if [[ "$SEL" =~ ^[0-9]+$ ]] && [ "$SEL" -ge 1 ] && [ "$SEL" -le "$n" ]; then
            PICK_VAL="${vals[$((SEL-1))]}"
            PICK_LABEL="$(label_of "$key" "$PICK_VAL")"
            return
        fi
        echo "[-] Invalid selection."
    done
}

# build_setting NAME TITLE REQUESTED(1=on)
# Appends -o flags to FLAGS; sets CHOSEN_FIRST (value of the setting's first key)
# and CHOSEN_LABEL (advanced mode). In advanced mode the menus are shown once per
# driver vendor; further queues of that vendor reuse (and validate) the picks.
build_setting() {
    local S="$1" title="$2" on="$3" n key onv offv val first_val="" label="" pairs="" line k v
    local c="ADVC_${VENDOR}_${S}"
    if [ "$ADVANCED" -eq 1 ] && [ -n "$(eval echo \${${c}_SET})" ]; then
        eval "pairs=\${${c}_PAIRS}; CHOSEN_FIRST=\${${c}_FIRST}; CHOSEN_LABEL=\${${c}_LABEL}"
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            k="${line%%=*}"; v="${line#*=}"
            if has_choice "$k" "$v"; then FLAGS+=("-o" "$line")
            else echo "[!] $QUEUE: '$k=$v' is not offered by this queue; skipped."; fi
        done <<< "$pairs"
        return
    fi
    for n in 1 2; do
        eval "key=\${${S}_K$n}; onv=\${${S}_ON$n}; offv=\${${S}_OFF$n}"
        [ -z "$key" ] && continue
        if [ "$ADVANCED" -eq 1 ]; then
            # Second key (e.g. staple position) only matters if the first is on
            if [ "$n" -eq 2 ] && [ "$first_val" = "$(eval echo \${${S}_OFF1})" ]; then continue; fi
            echo ""; echo "[$QUEUE]"
            pick_option "$key" "$title" "$onv" "$offv"
            val="$PICK_VAL"; label="$PICK_LABEL"
        else
            if [ "$on" -eq 1 ]; then val="$onv"; else val="$offv"; fi
            label=""
        fi
        [ "$n" -eq 1 ] && first_val="$val"
        if [ -n "$val" ]; then FLAGS+=("-o" "$key=$val"); pairs="$pairs$key=$val"$'\n'; fi
        [ -n "$label" ] && CHOSEN_LABEL="$label"
    done
    CHOSEN_FIRST="$first_val"
    if [ "$ADVANCED" -eq 1 ]; then
        printf -v "${c}_PAIRS" '%s' "$pairs"
        printf -v "${c}_FIRST" '%s' "$CHOSEN_FIRST"
        printf -v "${c}_LABEL" '%s' "$CHOSEN_LABEL"
        printf -v "${c}_SET" '%s' 1
    fi
}

# canon_set_account PPD ID PIN OWNER
# Canon's Printer Utility stores the Department ID/PIN inside the queue's PPD as
# *%INFO_JoAc comment lines: a zlib-compressed XML blob (base64, 200-char lines,
# terminated by END_<xml length>) whose id/password values are base64 of the
# bitwise-NOT of each byte. Rewrite that block here (empty ID/PIN = clear).
# Runs as root, inside the single sudo call made by run_privileged below.
canon_set_account() {
    perl -MCompress::Zlib -MMIME::Base64 - "$1" "$2" "$3" "$4" <<'PERL'
my ($ppd, $id, $pin, $owner) = @ARGV;
open(my $in, '<', $ppd) or die "cannot read $ppd: $!"; local $/; my $t = <$in>; close $in;
sub enc { my $s = shift; return '<string/>' if $s eq '';
          '<string>' . encode_base64(join('', map { chr(255 - ord($_)) } split //, $s), '') . '</string>' }
my $b64 = join '', $t =~ /^\*%INFO_JoAc\d+: (?!END_)(\S+)$/mg;
my $xml = $b64 ne '' ? uncompress(decode_base64($b64)) : undef;
$xml = '<?xml version="1.0" encoding="UTF-8"?>' . "\n" .
       '<CNXML><list_0><use_jobaccount><integer>0</integer></use_jobaccount><id><string/></id><password><string/></password><disable_bw><integer>0</integer></disable_bw><confirm_printing><integer>0</integer></confirm_printing><user_management><string>Dept</string></user_management><user_password><string/></user_password><owner><string/></owner></list_0></CNXML>' . "\n"
    unless defined $xml;
my ($e_id, $e_pin) = (enc($id), enc($pin));
$xml =~ s{<id>.*?</id>}{<id>$e_id</id>}s;
$xml =~ s{<password>.*?</password>}{<password>$e_pin</password>}s;
$xml =~ s{<owner><string/></owner>}{'<owner>' . enc($owner) . '</owner>'}e;
my $z = encode_base64(compress($xml), '');
my @lines; my $n = 1;
while ($z =~ /(.{1,200})/g) { push @lines, "*%INFO_JoAc$n: $1\n"; $n++ }
push @lines, "*%INFO_JoAc$n: END_" . length($xml) . "\n";
$t =~ s/^\*%INFO_JoAc\d+: \S*\n//mg;
my $blk = join '', @lines;
unless ($t =~ s/(^\*%INFO_PrPr\d+: END_\d+\n)/$1$blk/m) { $t =~ s/(^\*%INFO_[^\n]*\n)(?!.*^\*%INFO_)/$1$blk/ms or $t .= $blk }
open(my $out, '>', $ppd) or die "cannot write $ppd: $!"; print $out $t; close $out;
PERL
}

# ==============================================================================
# SESSION STEPS
# ==============================================================================

# select_queues: list the installed queues and read a comma-separated selection
# of numbers and ranges (e.g. 1-3,5,9-11). Fills SEL_Q (queue names) and SEL_V (their detected vendors);
# unusable queues are reported and dropped.
select_queues() {
    local PRINTERS=() i p n lo hi ok seen parts=() INPUT picked=()
    IFS=$'\n' read -r -d '' -a PRINTERS < <(lpstat -p | awk '{print $2}' && printf '\0')
    if [ ${#PRINTERS[@]} -eq 0 ]; then
        echo "[-] No local printer queues discovered."
        return 1
    fi

    echo "Select one or more target printer queues:"
    for i in "${!PRINTERS[@]}"; do
        printf "  [%d] %s\n" "$((i+1))" "${PRINTERS[i]}"
    done
    echo ""
    echo "Several queues can be configured with the same defaults at once, using"
    echo "numbers and/or ranges, e.g. 1-3,5,9-11 (they may use different drivers)."
    echo ""

    while true; do
        read -p "Enter selection(s) (1-${#PRINTERS[@]}): " INPUT
        INPUT="${INPUT// /}"
        ok=1; picked=(); seen=","
        [ -z "$INPUT" ] && ok=0
        IFS=',' read -r -a parts <<< "$INPUT"
        for p in "${parts[@]}"; do
            # each part is a single number (5) or an inclusive range (9-11)
            if [[ "$p" =~ ^[0-9]+$ ]]; then lo=$((10#$p)); hi=$lo
            elif [[ "$p" =~ ^([0-9]+)-([0-9]+)$ ]]; then lo=$((10#${BASH_REMATCH[1]})); hi=$((10#${BASH_REMATCH[2]}))
            else ok=0; break; fi
            if [ "$lo" -lt 1 ] || [ "$hi" -gt "${#PRINTERS[@]}" ] || [ "$lo" -gt "$hi" ]; then ok=0; break; fi
            for ((n=lo; n<=hi; n++)); do
                case "$seen" in
                    *",$n,"*) ;;   # ignore duplicates
                    *) seen="$seen$n,"; picked+=("${PRINTERS[$((n-1))]}") ;;
                esac
            done
        done
        [ "$ok" -eq 1 ] && [ ${#picked[@]} -gt 0 ] && break
        echo "[-] Invalid selection. Use numbers/ranges from the list, separated by commas (e.g. 1-3,5)."
    done

    SEL_Q=(); SEL_V=()
    echo ""
    for p in "${picked[@]}"; do
        if load_queue "$p"; then
            SEL_Q+=("$p"); SEL_V+=("$VENDOR")
            echo "[+] $p: $VENDOR driver"
        fi
    done
    [ ${#SEL_Q[@]} -gt 0 ]
}

# prompt_layout: easy-mode layout and finishing menus (asked once for all queues)
prompt_layout() {
    echo ""
    echo "Select layout options (Default: [1] Simplex + Monochrome):"
    echo "  [1] Simplex / Monochrome"
    echo "  [2] Simplex / Color"
    echo "  [3] Duplex  / Monochrome"
    echo "  [4] Duplex  / Color"
    echo ""
    read -p "Enter selection [1]: " LAYOUT_IDX
    case "${LAYOUT_IDX:-1}" in
        2) DUPLEX_REQ="simplex"; COLOR_REQ="color" ;;
        3) DUPLEX_REQ="duplex";  COLOR_REQ="mono"  ;;
        4) DUPLEX_REQ="duplex";  COLOR_REQ="color" ;;
        *) DUPLEX_REQ="simplex"; COLOR_REQ="mono"  ;;
    esac

    echo ""
    echo "Select finishing hardware profile:"
    echo "  [1] No Finishing (No Staple, No Punch) [Default]"
    echo "  [2] Staple Only"
    echo "  [3] Hole Punch Only"
    echo "  [4] Both Staple and Hole Punch"
    echo ""
    read -p "Enter selection [1]: " FINISH_IDX
    case "${FINISH_IDX:-1}" in
        2) STAPLE_REQ="staple"; PUNCH_REQ="none"   ;;
        3) STAPLE_REQ="none";   PUNCH_REQ="punch"  ;;
        4) STAPLE_REQ="staple"; PUNCH_REQ="punch"  ;;
        *) STAPLE_REQ="none";   PUNCH_REQ="none"   ;;
    esac
}

# prompt_accounting: enable/disable job accounting once, then ask for the code
# once per driver vendor among the selected queues (stored in CODE_<Vendor>).
prompt_accounting() {
    local ANS v i first q RAW_CODE KY_FIRST KY_LAST code
    echo ""
    read -p "Enable job accounting? [y/N]: " ANS
    ACCT_REQ="no"
    SHARP_LOGIN=""; ACCT_LOGIN=""; ACCT_PASS=""; ACCT_PIN=""
    CODE_Canon=""; CODE_Ricoh=""; CODE_Sharp=""; CODE_Kyocera=""
    [[ "$ANS" =~ ^[Yy] ]] || return 0
    ACCT_REQ="yes"

    for v in Canon Kyocera Ricoh Sharp; do
        first=""
        for i in "${!SEL_V[@]}"; do
            [ "${SEL_V[i]}" = "$v" ] && { first="${SEL_Q[i]}"; break; }
        done
        [ -z "$first" ] && continue
        echo ""
        echo "-- $v queues (e.g. $first) --"
        case "$v" in
            Sharp)
                echo "Sharp accounting method:"
                echo "  [1] User code (user number) [Default]"
                echo "  [2] Login name and password"
                read -p "Enter selection [1]: " SHARP_METHOD
                if [ "${SHARP_METHOD:-1}" = "2" ]; then
                    SHARP_LOGIN=1
                    read -p "Login name (saved per user): " ACCT_LOGIN
                    read -s -p "Password (hidden): " ACCT_PASS
                    echo ""
                else
                    read -p "User code (saved per user; blank = none): " CODE_Sharp
                fi ;;
            Canon)
                read -p "Department ID (queue-wide, global mode only; blank = none): " CODE_Canon
                if [ -n "$CODE_Canon" ]; then
                    read -s -p "PIN (optional, hidden): " ACCT_PIN
                    echo ""
                fi ;;
            Kyocera)
                # The Kyocera PPD only offers a fixed list of codes (MG00000000...),
                # so accept plain digits, normalise them, and re-ask until one matches.
                load_queue "$first"
                KY_FIRST=$(echo "$OPTIONS" | grep "^KmManagment/" | tr -d '*' | grep -oE "MG[0-9]+" | head -n1)
                KY_LAST=$(echo "$OPTIONS" | grep "^KmManagment/" | grep -oE "MG[0-9]+" | tail -n1)
                echo "Kyocera accepts only the codes this driver lists: ${KY_FIRST#MG} to ${KY_LAST#MG}."
                while true; do
                    read -p "User code (saved per user; blank = none): " code
                    [ -z "$code" ] && break
                    RAW_CODE="$code"
                    [[ "$code" =~ ^[0-9]+$ ]] && code=$(printf "MG%08d" "$((10#$code))")
                    has_choice KmManagment "$code" && break
                    echo "[-] '$RAW_CODE' is not one of the driver's codes (${KY_FIRST#MG} to ${KY_LAST#MG}). Try again or leave blank."
                done
                CODE_Kyocera="$code" ;;
            Ricoh)
                read -p "User code (saved per user; blank = none): " CODE_Ricoh ;;
        esac
    done
}

# configure_queue INDEX: build this queue's settings from the answers above.
# Per-user changes are applied immediately; queue-wide (global) ones are appended
# to PRIV_FILE so that ALL queues are applied by a single sudo call afterwards.
configure_queue() {
    local i="$1" R S k codevar
    load_queue "${SEL_Q[i]}" || { QSTATUS[i]="failed"; return; }
    define_settings
    FLAGS=(); USER_FLAGS=(); CANON_SET=""; CANON_CLEAR=""; SHARP_CLEAR=""
    local applied=0

    [ "$DUPLEX_REQ" = "duplex" ] && R=1 || R=0
    CHOSEN_LABEL=""; build_setting DUPLEX "Duplex" $R
    if [ "$ADVANCED" -eq 1 ]; then
        [ "$CHOSEN_FIRST" = "$DUPLEX_OFF1" ] && SUM_DUPLEX="single" || SUM_DUPLEX="double ($CHOSEN_LABEL)"
    else
        [ $R -eq 1 ] && SUM_DUPLEX="double" || SUM_DUPLEX="single"
    fi

    [ "$COLOR_REQ" = "color" ] && R=1 || R=0
    CHOSEN_LABEL=""; build_setting COLOR "Color mode" $R
    if [ "$ADVANCED" -eq 1 ]; then
        if [ "$CHOSEN_FIRST" = "$COLOR_OFF1" ]; then SUM_COLOR="mono"
        elif [ "$CHOSEN_FIRST" = "$COLOR_ON1" ]; then SUM_COLOR="color"
        else SUM_COLOR="$CHOSEN_LABEL"; fi
    else
        [ $R -eq 1 ] && SUM_COLOR="color" || SUM_COLOR="mono"
    fi

    [ "$STAPLE_REQ" = "staple" ] && R=1 || R=0
    CHOSEN_LABEL=""; build_setting STAPLE "Staple" $R
    if [ "$ADVANCED" -eq 1 ]; then
        [ "$CHOSEN_FIRST" = "$STAPLE_OFF1" ] && SUM_STAPLE="none" || SUM_STAPLE="$CHOSEN_LABEL"
    else
        [ $R -eq 1 ] && SUM_STAPLE="enabled" || SUM_STAPLE="none"
    fi

    [ "$PUNCH_REQ" = "punch" ] && R=1 || R=0
    CHOSEN_LABEL=""; build_setting PUNCH "Hole punch" $R
    if [ "$ADVANCED" -eq 1 ]; then
        [ "$CHOSEN_FIRST" = "$PUNCH_OFF1" ] && SUM_PUNCH="none" || SUM_PUNCH="$CHOSEN_LABEL"
    else
        [ $R -eq 1 ] && SUM_PUNCH="enabled" || SUM_PUNCH="none"
    fi

    # ---- job accounting / user code ------------------------------------------
    # Enable switches follow the chosen scope; the code itself is always per user.
    codevar="CODE_$VENDOR"; USERCODE="${!codevar}"
    SUM_ACCT="disabled"; SUM_CODE="none"
    if [ "$ACCT_REQ" = "yes" ]; then
        SUM_ACCT="enabled"
        [ -n "$USERCODE" ] && SUM_CODE="${USERCODE#MG}"
        [ -n "$SHARP_LOGIN" ] && [ "$VENDOR" = "Sharp" ] && [ -n "$ACCT_LOGIN" ] && SUM_CODE="$ACCT_LOGIN (login)"
        case "$VENDOR" in
            Canon)
                # Department ID Management is an "Installed Option" on the queue, so
                # it only takes effect when applied globally (lpadmin).
                FLAGS+=("-o" "CNUseJobAccount=True" "-o" "CNUsrManagement=Dept")
                # The Dept ID/PIN live in the queue's PPD (like Canon's own Printer
                # Utility writes them), i.e. queue-wide, so they need global mode.
                if [ "$SCOPE" = "global" ]; then
                    [ -n "$USERCODE" ] && CANON_SET=1
                else
                    [ -n "$USERCODE" ] && SUM_CODE="none"
                    echo "[i] $QUEUE: Department ID Management and the Dept ID/PIN are queue-wide; use the global option to set them."
                fi ;;
            Ricoh)
                FLAGS+=("-o" "RIEnableUserCode=True")
                [ -n "$USERCODE" ] && USER_FLAGS+=("-o" "RIUserCode=Custom.$USERCODE") ;;
            Sharp)
                if [ -n "$SHARP_LOGIN" ]; then
                    [ -n "$ACCT_LOGIN" ] && USER_FLAGS+=("-o" "ARAccountLogin=Custom.$ACCT_LOGIN")
                    [ -n "$ACCT_PASS" ] && USER_FLAGS+=("-o" "ARAccountPassword=Custom.$ACCT_PASS")
                else
                    [ -n "$USERCODE" ] && USER_FLAGS+=("-o" "ARUserNumber=Custom.$USERCODE")
                fi ;;
            Kyocera)
                if [ -z "$USERCODE" ]; then
                    SUM_ACCT="disabled"
                    echo "[!] $QUEUE: Kyocera needs a code to enable job accounting."
                elif has_choice KmManagment "$USERCODE"; then
                    USER_FLAGS+=("-o" "KmManagment=$USERCODE")
                else
                    SUM_ACCT="disabled"; SUM_CODE="none"
                    echo "[!] $QUEUE: code '$USERCODE' is not in this driver's list (e.g. MG00000001)."
                fi ;;
        esac
    else # Accounting off
        case "$VENDOR" in
            Canon)   FLAGS+=("-o" "CNUseJobAccount=False" "-o" "CNUsrManagement=Off")
                     [ "$SCOPE" = "global" ] && CANON_CLEAR=1 ;;
            Ricoh)   FLAGS+=("-o" "RIEnableUserCode=False") ;;
            Kyocera) USER_FLAGS+=("-o" "KmManagment=Default") ;;  # code option is per user
            Sharp)   SHARP_CLEAR=1 ;;  # drop this user's saved code/login (done below)
        esac
    fi

    # ---- apply ---------------------------------------------------------------
    QSTATUS[i]="nothing"
    if [ "$SCOPE" = "global" ]; then
        if [ ${#FLAGS[@]} -gt 0 ] || [ -n "$CANON_SET$CANON_CLEAR" ]; then
            {
                [ ${#FLAGS[@]} -gt 0 ] && {
                    printf 'lpadmin -p %q' "$QUEUE"; printf ' %q' "${FLAGS[@]}"
                    printf ' || echo "FAIL %q" >> "$RES"\n' "$QUEUE"; }
                [ -n "$CANON_SET" ] && printf 'canon_set_account %q %q %q %q || echo "FAIL %q" >> "$RES"\n' "$PPD" "$USERCODE" "$ACCT_PIN" "$USER" "$QUEUE"
                [ -n "$CANON_CLEAR" ] && printf 'canon_set_account %q "" "" %q || echo "FAIL %q" >> "$RES"\n' "$PPD" "$USER" "$QUEUE"
            } >> "$PRIV_FILE"
            QSTATUS[i]="pending"
            PRIV_COUNT=$((PRIV_COUNT+1))
            # per-user overrides would mask the new global defaults; removed after success
            QCLEAN[i]=""
            for ((k=1; k<${#FLAGS[@]}; k+=2)); do QCLEAN[i]="${QCLEAN[i]} ${FLAGS[k]%%=*}"; done
        fi
    elif [ ${#FLAGS[@]} -gt 0 ]; then
        echo "[+] Applying per-user defaults to $QUEUE for $USER..."
        lpoptions -p "$QUEUE" "${FLAGS[@]}" && { QSTATUS[i]="applied"; applied=1; }
    fi

    if [ "$VENDOR" = "Sharp" ] && [ "$ACCT_REQ" = "yes" ]; then
        # Remove the unused method's saved values so only one method is active
        if [ -n "$SHARP_LOGIN" ]; then S="ARUserNumber"; else S="ARAccountLogin ARAccountPassword"; fi
        for k in $S; do lpoptions -p "$QUEUE" -r "$k" >/dev/null 2>&1; done
    fi
    if [ -n "$SHARP_CLEAR" ]; then
        echo "[+] Clearing saved Sharp accounting settings for $USER ($QUEUE)..."
        for k in ARUserNumber ARAccountLogin ARAccountPassword; do
            lpoptions -p "$QUEUE" -r "$k" >/dev/null 2>&1
        done
        applied=1
    fi
    if [ ${#USER_FLAGS[@]} -gt 0 ]; then
        echo "[+] Saving user code for $USER on $QUEUE (per user)..."
        lpoptions -p "$QUEUE" "${USER_FLAGS[@]}" && applied=1
    fi
    [ "$applied" -eq 1 ] && [ "${QSTATUS[i]}" = "nothing" ] && QSTATUS[i]="applied"

    QSUM[i]="Queue: $QUEUE
Color: $SUM_COLOR
Duplex: $SUM_DUPLEX
Staple: $SUM_STAPLE
Punch: $SUM_PUNCH
Accounting: $SUM_ACCT
Code: $SUM_CODE"
}

# run_privileged: everything queue-wide (lpadmin for every global queue, plus the
# Canon Department ID/PIN writes) runs in ONE sudo call, so there is a single
# admin prompt no matter how many queues were selected.
run_privileged() {
    local SUDO="" i k
    [ "$(id -u)" -ne 0 ] && SUDO="sudo"
    echo ""
    echo "[+] Applying queue-wide settings to $PRIV_COUNT queue(s) (may prompt for admin password)..."
    echo 'echo DONE >> "$RES"' >> "$PRIV_FILE"
    $SUDO bash "$PRIV_FILE"
    for i in "${!SEL_Q[@]}"; do
        [ "${QSTATUS[i]}" = "pending" ] || continue
        if grep -q '^DONE$' "$RES" 2>/dev/null && ! grep -qxF "FAIL ${SEL_Q[i]}" "$RES"; then
            QSTATUS[i]="applied"
            for k in ${QCLEAN[i]}; do lpoptions -p "${SEL_Q[i]}" -r "$k" >/dev/null 2>&1; done
        else
            QSTATUS[i]="failed"
        fi
    done
}

# run_session: one full pass (select queues, ask once, configure each, apply)
run_session() {
    local i
    echo "=================================================="
    echo " CUPS Printer Defaults Utility"
    echo " (Canon / Ricoh / Sharp / Kyocera)"
    echo "=================================================="
    echo "Fetching available printer queues..."
    echo ""

    select_queues || return 1
    # advanced-mode picks are remembered per driver within a session only
    unset $(compgen -v | grep '^ADVC_') 2>/dev/null

    echo ""
    echo "Apply settings:"
    echo "  [1] Globally - all users of this Mac (requires admin) [Default]"
    echo "  [2] Per user - only for $USER"
    echo "(A user code, if entered, is always saved per user.)"
    echo ""
    read -p "Enter selection [1]: " SCOPE_IDX
    case "${SCOPE_IDX:-1}" in
        2) SCOPE="user" ;;
        *) SCOPE="global" ;;
    esac

    DUPLEX_REQ="simplex"; COLOR_REQ="mono"; STAPLE_REQ="none"; PUNCH_REQ="none"
    [ "$ADVANCED" -eq 0 ] && prompt_layout
    prompt_accounting

    echo ""
    echo "[*] Compiling hardware instructions for driver execution..."

    QSTATUS=(); QSUM=(); QCLEAN=()
    PRIV_COUNT=0
    PRIV_FILE=$(mktemp); RES=$(mktemp); chmod 600 "$PRIV_FILE"
    { echo "RES=$(printf '%q' "$RES")"; declare -f canon_set_account; } > "$PRIV_FILE"

    for i in "${!SEL_Q[@]}"; do
        configure_queue "$i"
    done

    [ "$PRIV_COUNT" -gt 0 ] && run_privileged
    rm -f "$PRIV_FILE" "$RES"

    echo ""
    for i in "${!SEL_Q[@]}"; do
        case "${QSTATUS[i]}" in
            applied) echo "[+] Done: ${SEL_Q[i]}"; echo ""; echo "${QSUM[i]}" ;;
            failed)  echo "[-] Failed: ${SEL_Q[i]} (nothing was applied; see messages above)" ;;
            *)       echo "[-] Nothing was applied to ${SEL_Q[i]}." ;;
        esac
        echo ""
    done
}

# ==============================================================================
# MAIN LOOP: offer to run again so several printers can be set up in one go
# ==============================================================================
while true; do
    run_session || break
    read -p "Configure another printer? [y/N]: " AGAIN
    [[ "$AGAIN" =~ ^[Yy] ]] || break
    echo ""
done

if [ "$WEBUI_MODE" = "after" ]; then
    echo ""
    run_webui
fi
