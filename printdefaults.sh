#!/bin/bash

# ==============================================================================
# PRINTER DEFAULTS INTERACTIVE WRAPPER
# Supports: Canon, Ricoh, Sharp, Kyocera
#
# Layout/finishing/accounting-enable can be applied globally (all users, via
# lpadmin + sudo) or per user (~/.cups/lpoptions). The user code is ALWAYS
# stored per user.
#
# Usage: printdefaults.sh [-a]
#   (default)  easy mode: simple menus for layout, finishing and accounting
#   -a         advanced mode: step through each setting and pick from the
#              values the printer's PPD offers (staple position, punch type...)
# ==============================================================================

ADVANCED=0
while getopts "ah" OPT; do
    case "$OPT" in
        a) ADVANCED=1 ;;
        *) echo "Usage: $0 [-a]   (-a = advanced mode)"; exit 1 ;;
    esac
done

# 1. DISCOVER AND SELECT PRINTER QUEUE
echo "=================================================="
echo " CUPS Printer Defaults Utility"
echo " (Canon / Ricoh / Sharp / Kyocera)"
echo "=================================================="
echo "Fetching available printer queues..."
echo ""

IFS=$'\n' read -r -d '' -a PRINTERS < <(lpstat -p | awk '{print $2}' && printf '\0')

if [ ${#PRINTERS[@]} -eq 0 ]; then
    echo "[-] No local printer queues discovered. Exiting."
    exit 1
fi

echo "Select a target printer queue:"
for i in "${!PRINTERS[@]}"; do
    printf "  [%d] %s\n" "$((i+1))" "${PRINTERS[i]}"
done
echo ""

while true; do
    read -p "Enter selection (1-${#PRINTERS[@]}): " PRINTER_IDX
    if [[ "$PRINTER_IDX" =~ ^[0-9]+$ ]] && [ "$PRINTER_IDX" -ge 1 ] && [ "$PRINTER_IDX" -le "${#PRINTERS[@]}" ]; then
        QUEUE="${PRINTERS[$((PRINTER_IDX-1))]}"
        break
    else
        echo "[-] Invalid selection. Please try again."
    fi
done

echo ""
echo "[+] Target Queue Selected: $QUEUE"
echo "=================================================="
echo ""

# Fetch all available options for this printer queue once
OPTIONS=$(lpoptions -p "$QUEUE" -l)

if [ -z "$OPTIONS" ]; then
    echo "[-] Error: Could not retrieve options for queue '$QUEUE'."
    exit 1
fi

# has_opt NAME           -> option exists in the driver
# has_choice NAME VALUE  -> option exists and offers VALUE
has_opt() { echo "$OPTIONS" | grep -q "^$1/"; }
has_choice() { echo "$OPTIONS" | grep "^$1/" | tr -d '*' | grep -qw -- "$2"; }

# Identify the vendor from driver-specific option names
if   has_opt CNColorMode;      then VENDOR="Canon"
elif has_opt RIEnableUserCode; then VENDOR="Ricoh"
elif has_opt ARCMode;          then VENDOR="Sharp"
elif has_opt KCStaple || has_opt KmManagment; then VENDOR="Kyocera"
else
    echo "[-] Unsupported driver: no Canon, Ricoh, Sharp or Kyocera options found on '$QUEUE'."
    exit 1
fi
echo "[+] Detected driver: $VENDOR"
echo ""

# 2. SCOPE: GLOBAL OR PER USER
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

if [ "$ADVANCED" -eq 0 ]; then
    # 3. SELECT CONFIGURATION COMBINATION (DEFAULT: SIMPLEX + MONO)
    echo ""
    echo "Select layout options (Default: [1] Simplex + Monochrome):"
    echo "  [1] Simplex / Monochrome"
    echo "  [2] Simplex / Color"
    echo "  [3] Duplex  / Monochrome"
    echo "  [4] Duplex  / Color"
    echo ""

    read -p "Enter selection [1]: " LAYOUT_IDX
    LAYOUT_IDX=${LAYOUT_IDX:-1}

    case "$LAYOUT_IDX" in
        2) DUPLEX_REQ="simplex"; COLOR_REQ="color" ;;
        3) DUPLEX_REQ="duplex";  COLOR_REQ="mono"  ;;
        4) DUPLEX_REQ="duplex";  COLOR_REQ="color" ;;
        *) DUPLEX_REQ="simplex"; COLOR_REQ="mono"  ;;
    esac

    # 4. SELECT FINISHING SUITE OPTIONS
    echo ""
    echo "Select finishing hardware profile:"
    echo "  [1] No Finishing (No Staple, No Punch) [Default]"
    echo "  [2] Staple Only"
    echo "  [3] Hole Punch Only"
    echo "  [4] Both Staple and Hole Punch"
    echo ""

    read -p "Enter selection [1]: " FINISH_IDX
    FINISH_IDX=${FINISH_IDX:-1}

    case "$FINISH_IDX" in
        2) STAPLE_REQ="staple"; PUNCH_REQ="none"   ;;
        3) STAPLE_REQ="none";   PUNCH_REQ="punch"  ;;
        4) STAPLE_REQ="staple"; PUNCH_REQ="punch"  ;;
        *) STAPLE_REQ="none";   PUNCH_REQ="none"   ;;
    esac
fi

echo ""
echo "[*] Compiling hardware instructions for driver execution..."

# ==============================================================================
# SETTING MAP
# Each setting has up to two driver keys (K1, K2) with an "on" and "off" value.
# Easy mode applies ON/OFF per the simple menus; advanced mode lets you pick any
# value the PPD offers for each key (ON values are shown as "recommended").
# ==============================================================================
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
        PUNCH_K1=KCPunch;       PUNCH_ON1=3Hole;          PUNCH_OFF1=None ;;
    Ricoh)
        DUPLEX_K1=Duplex;       DUPLEX_ON1=DuplexNoTumble; DUPLEX_OFF1=None
        COLOR_K1=ColorModel;    COLOR_ON1=CMYK;           COLOR_OFF1=Gray
        STAPLE_K1=StapleLocation; STAPLE_ON1=UpperLeft;   STAPLE_OFF1=None
        PUNCH_K1=RIPunch;       PUNCH_ON1=Left3;          PUNCH_OFF1=None ;;
    Sharp)
        DUPLEX_K1=Duplex;       DUPLEX_ON1=DuplexNoTumble; DUPLEX_OFF1=None
        COLOR_K1=ARCMode;       COLOR_ON1=CMColor;        COLOR_OFF1=CMBW
        STAPLE_K1=ARStaple;     STAPLE_ON1=Staple1;       STAPLE_OFF1=Staple0
        PUNCH_K1=ARPunch;       PUNCH_ON1=Punch3;         PUNCH_OFF1=PunchNone ;;
esac

# Drop second keys the driver doesn't actually have
for S in STAPLE PUNCH; do
    k="${S}_K2"
    if [ -n "${!k}" ] && ! has_opt "${!k}"; then printf -v "$k" ''; fi
done

# label_of KEY VALUE -> human label from the queue's PPD, or VALUE if unknown
PPD="/etc/cups/ppd/$QUEUE.ppd"
label_of() {
    local l=""
    [ -r "$PPD" ] && l=$(grep -F -m1 "*$1 $2/" "$PPD" | sed 's/^[^\/]*\///; s/:.*//')
    echo "${l:-$2}"
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
# Appends -o flags to FLAGS and records the chosen label in CHOSEN_<NAME>
build_setting() {
    local S="$1" title="$2" on="$3" n key onv offv val first_val="" label=""
    for n in 1 2; do
        eval "key=\${${S}_K$n}; onv=\${${S}_ON$n}; offv=\${${S}_OFF$n}"
        [ -z "$key" ] && continue
        if [ "$ADVANCED" -eq 1 ]; then
            # Second key (e.g. staple position) only matters if the first is on
            if [ "$n" -eq 2 ] && [ "$first_val" = "$(eval echo \${${S}_OFF1})" ]; then continue; fi
            pick_option "$key" "$title" "$onv" "$offv"
            val="$PICK_VAL"; label="$PICK_LABEL"
        else
            if [ "$on" -eq 1 ]; then val="$onv"; else val="$offv"; fi
            label=""
        fi
        [ "$n" -eq 1 ] && first_val="$val"
        [ -n "$val" ] && FLAGS+=("-o" "$key=$val")
        [ -n "$label" ] && CHOSEN_LABEL="$label"
    done
    CHOSEN_FIRST="$first_val"
}

FLAGS=()
USER_FLAGS=()
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

# 4. OPTIONAL JOB ACCOUNTING / USER CODE
echo ""
read -p "Enable job accounting? [y/N]: " ACCT_ANS
ACCT_REQ="no"
USERCODE=""
if [[ "$ACCT_ANS" =~ ^[Yy] ]]; then
    ACCT_REQ="yes"
    if [ "$VENDOR" = "Sharp" ]; then
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
            read -p "User code (saved per user; blank = none): " USERCODE
        fi
    elif [ "$VENDOR" = "Canon" ]; then
        read -p "Department ID (saved per user; blank = none): " USERCODE
        if [ -n "$USERCODE" ]; then
            read -s -p "PIN (optional, hidden): " ACCT_PIN
            echo ""
        fi
    elif [ "$VENDOR" = "Kyocera" ]; then
        # The Kyocera PPD only offers a fixed list of codes (MG00000000...), so
        # accept plain digits, normalise them, and re-ask until one matches.
        KY_FIRST=$(echo "$OPTIONS" | grep "^KmManagment/" | tr -d '*' | grep -oE "MG[0-9]+" | head -n1)
        KY_LAST=$(echo "$OPTIONS" | grep "^KmManagment/" | grep -oE "MG[0-9]+" | tail -n1)
        echo "Kyocera accepts only the codes this driver lists: ${KY_FIRST#MG} to ${KY_LAST#MG}."
        while true; do
            read -p "User code (saved per user; blank = none): " USERCODE
            [ -z "$USERCODE" ] && break
            RAW_CODE="$USERCODE"
            if [[ "$USERCODE" =~ ^[0-9]+$ ]]; then
                USERCODE=$(printf "MG%08d" "$((10#$USERCODE))")
            fi
            has_choice KmManagment "$USERCODE" && break
            echo "[-] '$RAW_CODE' is not one of the driver's codes (${KY_FIRST#MG} to ${KY_LAST#MG}). Try again or leave blank."
        done
    else
        read -p "User code (saved per user; blank = none): " USERCODE
    fi
fi

# ==============================================================================
# JOB ACCOUNTING / USER CODE
# Enable switches follow the chosen scope; the code itself is always per user.
# ==============================================================================
SUM_ACCT="disabled"; SUM_CODE="none"
if [ "$ACCT_REQ" = "yes" ]; then
    SUM_ACCT="enabled"
    [ -n "$USERCODE" ] && SUM_CODE="${USERCODE#MG}"
    [ -n "$SHARP_LOGIN" ] && [ -n "$ACCT_LOGIN" ] && SUM_CODE="$ACCT_LOGIN (login)"
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
                echo "[i] Canon: Department ID Management and the Dept ID/PIN are queue-wide; run again with the global option to set them."
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
                echo "[!] Kyocera: a code is required to enable job accounting."
            elif has_choice KmManagment "$USERCODE"; then
                USER_FLAGS+=("-o" "KmManagment=$USERCODE")
            else
                SUM_ACCT="disabled"; SUM_CODE="none"
                echo "[!] Kyocera: code '$USERCODE' is not in this driver's list (e.g. MG00000001)."
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

# canon_set_account PPD ID PIN OWNER
# Canon's Printer Utility stores the Department ID/PIN inside the queue's PPD as
# *%INFO_JoAc comment lines: a zlib-compressed XML blob (base64, 200-char lines,
# terminated by END_<xml length>) whose id/password values are base64 of the
# bitwise-NOT of each byte. Rewrite that block here (empty ID/PIN = clear).
# Runs as root, inside the single sudo call made by apply_global below.
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
# EXECUTION
# ==============================================================================
APPLIED=0

# apply_global FLAGS... : lpadmin stores defaults on the CUPS server, so they
# apply to all users. Everything that needs root (lpadmin, plus the Canon
# Department ID/PIN write when requested) runs in ONE sudo call, so there is a
# single admin prompt. A per-user override would mask the new defaults, so those
# are removed afterwards.
apply_global() {
    local SUDO="" k mode="none" id="" pin=""
    [ "$(id -u)" -ne 0 ] && SUDO="sudo"
    if [ -n "$CANON_SET" ]; then mode="set"; id="$USERCODE"; pin="$ACCT_PIN"
    elif [ -n "$CANON_CLEAR" ]; then mode="clear"; fi
    echo "[+] Applying queue-wide settings to $QUEUE (may prompt for admin password)..."
    if $SUDO bash -c '
        eval "$1"; mode=$2; ppd=$3; id=$4; pin=$5; owner=$6; queue=$7; shift 7
        if [ $# -gt 0 ]; then lpadmin -p "$queue" "$@" || exit 1; fi
        case "$mode" in
            set)   canon_set_account "$ppd" "$id" "$pin" "$owner" || exit 2 ;;
            clear) canon_set_account "$ppd" "" "" "$owner" || exit 2 ;;
        esac
    ' _ "$(declare -f canon_set_account)" "$mode" "$PPD" "$id" "$pin" "$USER" "$QUEUE" "$@"; then
        APPLIED=1
        for ((k=2; k<=$#; k+=2)); do
            lpoptions -p "$QUEUE" -r "${!k%%=*}" >/dev/null 2>&1
        done
    else
        echo "[-] Applying queue-wide settings failed; check the messages above."
        [ -n "$CANON_SET" ] && SUM_CODE="none"
        return 1
    fi
}

if [ "$SCOPE" = "global" ]; then
    { [ ${#FLAGS[@]} -gt 0 ] || [ -n "$CANON_SET$CANON_CLEAR" ]; } && apply_global "${FLAGS[@]}"
elif [ ${#FLAGS[@]} -gt 0 ]; then
    echo "[+] Applying per-user defaults to $QUEUE for $USER..."
    lpoptions -p "$QUEUE" "${FLAGS[@]}" && APPLIED=1
fi

if [ "$VENDOR" = "Sharp" ] && [ "$ACCT_REQ" = "yes" ]; then
    # Remove the unused method's saved values so only one method is active
    if [ -n "$SHARP_LOGIN" ]; then STALE="ARUserNumber"; else STALE="ARAccountLogin ARAccountPassword"; fi
    for o in $STALE; do lpoptions -p "$QUEUE" -r "$o" >/dev/null 2>&1; done
fi

if [ -n "$SHARP_CLEAR" ]; then
    echo "[+] Clearing saved Sharp accounting settings for $USER..."
    for o in ARUserNumber ARAccountLogin ARAccountPassword; do
        lpoptions -p "$QUEUE" -r "$o" >/dev/null 2>&1
    done
    APPLIED=1
fi

if [ ${#USER_FLAGS[@]} -gt 0 ]; then
    echo "[+] Saving user code for $USER (per user)..."
    lpoptions -p "$QUEUE" "${USER_FLAGS[@]}" && APPLIED=1
fi

if [ "$APPLIED" -eq 1 ]; then
    echo "[+] Done."
    echo ""
    echo "Queue: $QUEUE"
    echo "Color: $SUM_COLOR"
    echo "Duplex: $SUM_DUPLEX"
    echo "Staple: $SUM_STAPLE"
    echo "Punch: $SUM_PUNCH"
    echo "Accounting: $SUM_ACCT"
    echo "Code: $SUM_CODE"
else
    echo "[-] Nothing was applied."
fi
