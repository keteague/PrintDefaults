#!/bin/bash

# ==============================================================================
# PRINTER DEFAULTS INTERACTIVE WRAPPER
# Supports: Canon, Ricoh, Sharp, Kyocera
#
# Layout/finishing/accounting-enable can be applied globally (all users, via
# lpadmin + sudo) or per user (~/.cups/lpoptions). The user code is ALWAYS
# stored per user.
# ==============================================================================

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

# 5. OPTIONAL JOB ACCOUNTING / USER CODE
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
    else
        read -p "User code (saved per user; blank = none): " USERCODE
    fi
fi

echo ""
echo "[*] Compiling hardware instructions for driver execution..."

# Flags following the chosen scope, and flags that are always per user
FLAGS=()
USER_FLAGS=()

# ==============================================================================
# DUPLEX
# ==============================================================================
case "$VENDOR" in
    Canon)
        if [ "$DUPLEX_REQ" = "duplex" ]; then FLAGS+=("-o" "CNDuplex=DuplexFront")
        else FLAGS+=("-o" "CNDuplex=None"); fi ;;
    *)  # Kyocera / Ricoh / Sharp use the standard Duplex key
        if [ "$DUPLEX_REQ" = "duplex" ]; then FLAGS+=("-o" "Duplex=DuplexNoTumble")
        else FLAGS+=("-o" "Duplex=None"); fi ;;
esac

# ==============================================================================
# COLOR MODE
# ==============================================================================
case "$VENDOR" in
    Canon)
        [ "$COLOR_REQ" = "color" ] && FLAGS+=("-o" "CNColorMode=color") || FLAGS+=("-o" "CNColorMode=mono") ;;
    Sharp)
        [ "$COLOR_REQ" = "color" ] && FLAGS+=("-o" "ARCMode=CMColor") || FLAGS+=("-o" "ARCMode=CMBW") ;;
    *)  # Kyocera / Ricoh
        [ "$COLOR_REQ" = "color" ] && FLAGS+=("-o" "ColorModel=CMYK") || FLAGS+=("-o" "ColorModel=Gray") ;;
esac

# ==============================================================================
# STAPLE
# ==============================================================================
if [ "$STAPLE_REQ" = "staple" ]; then
    case "$VENDOR" in
        Canon)   FLAGS+=("-o" "CNStaple=True" "-o" "StapleLocation=TopLeft") ;;
        Kyocera) FLAGS+=("-o" "KCStaple=Upperleft") ;;
        Ricoh)   FLAGS+=("-o" "StapleLocation=UpperLeft") ;;
        Sharp)   FLAGS+=("-o" "ARStaple=Staple1") ;;
    esac
else
    case "$VENDOR" in
        Canon)   FLAGS+=("-o" "CNStaple=False") ;;
        Kyocera) FLAGS+=("-o" "KCStaple=None") ;;
        Ricoh)   FLAGS+=("-o" "StapleLocation=None") ;;
        Sharp)   FLAGS+=("-o" "ARStaple=Staple0") ;;
    esac
fi

# ==============================================================================
# HOLE PUNCH
# ==============================================================================
if [ "$PUNCH_REQ" = "punch" ]; then
    case "$VENDOR" in
        Canon)
            PUNCH_MOD=$(echo "$OPTIONS" | grep "^CNPuncher/" | grep -oE "PUNU23|PUNF24|PUNU24" | head -n1)
            [ -n "$PUNCH_MOD" ] && FLAGS+=("-o" "CNPuncher=$PUNCH_MOD")
            has_opt CNMultiPunch && FLAGS+=("-o" "CNMultiPunch=PUNU3") ;;
        Kyocera) FLAGS+=("-o" "KCPunch=3Hole") ;;
        Ricoh)   FLAGS+=("-o" "RIPunch=Left3") ;;
        Sharp)   FLAGS+=("-o" "ARPunch=Punch3") ;;
    esac
else
    case "$VENDOR" in
        Canon)
            FLAGS+=("-o" "CNPuncher=None")
            has_opt CNMultiPunch && FLAGS+=("-o" "CNMultiPunch=Off") ;;
        Kyocera) FLAGS+=("-o" "KCPunch=None") ;;
        Ricoh)   FLAGS+=("-o" "RIPunch=None") ;;
        Sharp)   FLAGS+=("-o" "ARPunch=PunchNone") ;;
    esac
fi

# ==============================================================================
# JOB ACCOUNTING / USER CODE
# Enable switches follow the chosen scope; the code itself is always per user.
# ==============================================================================
if [ "$ACCT_REQ" = "yes" ]; then
    case "$VENDOR" in
        Canon)   # Dept ID/PIN are not PPD options; users enter them at print time
            FLAGS+=("-o" "CNUseJobAccount=True" "-o" "CNUsrManagement=Dept")
            [ -n "$USERCODE" ] && echo "[!] Canon: Department ID/PIN cannot be preset; enter them when printing." ;;
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
                echo "[!] Kyocera: a code is required to enable job accounting."
            elif has_choice KmManagment "$USERCODE"; then
                USER_FLAGS+=("-o" "KmManagment=$USERCODE")
            else
                echo "[!] Kyocera: code '$USERCODE' is not in this driver's list (e.g. MG00000001)."
            fi ;;
    esac
else # Accounting off
    case "$VENDOR" in
        Canon)   FLAGS+=("-o" "CNUseJobAccount=False" "-o" "CNUsrManagement=Off") ;;
        Ricoh)   FLAGS+=("-o" "RIEnableUserCode=False") ;;
        Kyocera) USER_FLAGS+=("-o" "KmManagment=Default") ;;  # code option is per user
        Sharp)   SHARP_CLEAR=1 ;;  # drop this user's saved code/login (done below)
    esac
fi

# ==============================================================================
# EXECUTION
# ==============================================================================
APPLIED=0

if [ ${#FLAGS[@]} -gt 0 ]; then
    if [ "$SCOPE" = "global" ]; then
        # lpadmin stores defaults on the CUPS server, so they apply to all users.
        SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
        echo "[+] Applying global defaults to $QUEUE (may prompt for admin password)..."
        if $SUDO lpadmin -p "$QUEUE" "${FLAGS[@]}"; then
            APPLIED=1
            # A per-user override would mask the new global default; remove those
            for ((k=1; k<${#FLAGS[@]}; k+=2)); do
                lpoptions -p "$QUEUE" -r "${FLAGS[k]%%=*}" >/dev/null 2>&1
            done
        else
            echo "[-] lpadmin failed; global settings were not applied."
        fi
    else
        echo "[+] Applying per-user defaults to $QUEUE for $USER..."
        lpoptions -p "$QUEUE" "${FLAGS[@]}" && APPLIED=1
    fi
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
else
    echo "[-] Nothing was applied."
fi
