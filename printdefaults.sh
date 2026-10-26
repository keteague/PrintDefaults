#!/bin/bash

# ==============================================================================
# UNIVERSAL PRINTER CONFIGURATION INTERACTIVE WRAPPER
# Supports: Canon, Ricoh, Kyocera, Sharp, and IPP Everywhere/AirPrint
# ==============================================================================

# 1. DISCOVER AND SELECT PRINTER QUEUE
echo "=================================================="
echo " Modern CUPS Fleet Printer Configuration Utility"
echo "=================================================="
echo "Fetching available printer queues..."
echo ""

# Get array of local printer queues
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

# 2. SELECT CONFIGURATION COMBINATION (DEFAULT: SIMPLEX + MONO)
echo "Select layout options (Default: [1] Simplex + Monochrome):"
echo "  [1] Simplex / Monochrome"
echo "  [2] Simplex / Color"
echo "  [3] Duplex  / Monochrome"
echo "  [4] Duplex  / Color"
echo ""

read -p "Enter selection [1]: " LAYOUT_IDX
LAYOUT_IDX=${LAYOUT_IDX:-1} # Default to 1 if empty

case "$LAYOUT_IDX" in
    2) DUPLEX_REQ="simplex"; COLOR_REQ="color" ;;
    3) DUPLEX_REQ="duplex";  COLOR_REQ="mono"  ;;
    4) DUPLEX_REQ="duplex";  COLOR_REQ="color" ;;
    *) DUPLEX_REQ="simplex"; COLOR_REQ="mono"  ;; # Default fallback
esac

# 3. SELECT FINISHING SUITE OPTIONS
echo ""
echo "Select finishing hardware profile:"
echo "  [1] No Finishing (No Staple, No Punch) [Default]"
echo "  [2] Staple Only"
echo "  [3] Hole Punch Only"
echo "  [4] Both Staple and Hole Punch"
echo ""

read -p "Enter selection [1]: " FINISH_IDX
FINISH_IDX=${FINISH_IDX:-1} # Default to 1 if empty

case "$FINISH_IDX" in
    2) STAPLE_REQ="staple"; PUNCH_REQ="none"   ;;
    3) STAPLE_REQ="none";   PUNCH_REQ="punch"  ;;
    4) STAPLE_REQ="staple"; PUNCH_REQ="punch"  ;;
    *) STAPLE_REQ="none";   PUNCH_REQ="none"   ;; # Default fallback
esac

# 4. OPTIONAL JOB ACCOUNTING / USER CODE
echo ""
read -p "Enable job accounting? [y/N]: " ACCT_ANS
ACCT_REQ="no"
USERCODE=""
if [[ "$ACCT_ANS" =~ ^[Yy] ]]; then
    ACCT_REQ="yes"
    read -p "User code / account ID (leave blank to enable accounting without a code): " USERCODE
    if [ -n "$USERCODE" ]; then
        read -s -p "PIN / password for this code (optional, hidden): " ACCT_PIN
        echo ""
    fi
fi

echo ""
echo "[*] Compiling hardware instructions for driver execution..."

# Array to collect our on-the-fly lpadmin flags
LPADMIN_FLAGS=()

# ==============================================================================
# VENDOR LOGIC MAP: DUPLEX
# ==============================================================================
if [ "$DUPLEX_REQ" = "duplex" ]; then
    if echo "$OPTIONS" | grep -q "CNDuplex"; then                       # Canon
        LPADMIN_FLAGS+=("-o" "CNDuplex=DuplexFront")
    elif echo "$OPTIONS" | grep -q "JobDuplex"; then                     # Kyocera
        LPADMIN_FLAGS+=("-o" "JobDuplex=SimplexDuplex")
    elif echo "$OPTIONS" | grep -q "Duplex"; then                        # Sharp / Ricoh / Fallback
        if echo "$OPTIONS" | grep -F "Duplex=" | grep -q "DuplexNoTumbleK"; then
            LPADMIN_FLAGS+=("-o" "Duplex=DuplexNoTumbleK")              # Sharp specific
        elif echo "$OPTIONS" | grep -F "Duplex=" | grep -q "DuplexNoTumble"; then
            LPADMIN_FLAGS+=("-o" "Duplex=DuplexNoTumble")
        else
            LPADMIN_FLAGS+=("-o" "Duplex=Vertical")
        fi
    elif echo "$OPTIONS" | grep -q "TwoSided"; then                      # Generics
        LPADMIN_FLAGS+=("-o" "TwoSided=LongEdge")
    elif echo "$OPTIONS" | grep -F "sides=" | grep -q "two-sided-long-edge"; then
        LPADMIN_FLAGS+=("-o" "sides=two-sided-long-edge")
    fi
else # Simplex requested
    if echo "$OPTIONS" | grep -q "CNDuplex"; then
        LPADMIN_FLAGS+=("-o" "CNDuplex=None")
    elif echo "$OPTIONS" | grep -q "JobDuplex"; then
        LPADMIN_FLAGS+=("-o" "JobDuplex=SimplexNone")
    elif echo "$OPTIONS" | grep -q "Duplex"; then
        LPADMIN_FLAGS+=("-o" "Duplex=None")
    elif echo "$OPTIONS" | grep -q "TwoSided"; then
        LPADMIN_FLAGS+=("-o" "TwoSided=None")
    elif echo "$OPTIONS" | grep -F "sides=" | grep -q "one-sided"; then
        LPADMIN_FLAGS+=("-o" "sides=one-sided")
    fi
fi

# ==============================================================================
# VENDOR LOGIC MAP: COLOR MODE
# ==============================================================================
if [ "$COLOR_REQ" = "mono" ]; then
    if echo "$OPTIONS" | grep -q "CNColorMode"; then                      # Canon
        LPADMIN_FLAGS+=("-o" "CNColorMode=mono")
    elif echo "$OPTIONS" | grep -q "KCColorMode"; then                    # Kyocera
        LPADMIN_FLAGS+=("-o" "KCColorMode=KCMono")
    elif echo "$OPTIONS" | grep -q "ColorMode"; then                      # Ricoh / Sharp
        if echo "$OPTIONS" | grep -F "ColorMode=" | grep -q "BW"; then LPADMIN_FLAGS+=("-o" "ColorMode=BW")
        elif echo "$OPTIONS" | grep -F "ColorMode=" | grep -q "Mono"; then LPADMIN_FLAGS+=("-o" "ColorMode=Mono")
        elif echo "$OPTIONS" | grep -F "ColorMode=" | grep -q "BlackWhite"; then LPADMIN_FLAGS+=("-o" "ColorMode=BlackWhite")
        fi
    elif echo "$OPTIONS" | grep -q "ColorModel"; then                    # Fallbacks
        if echo "$OPTIONS" | grep -F "ColorModel=" | grep -q "Gray"; then LPADMIN_FLAGS+=("-o" "ColorModel=Gray")
        elif echo "$OPTIONS" | grep -F "ColorModel=" | grep -q "Monochrome"; then LPADMIN_FLAGS+=("-o" "ColorModel=Monochrome")
        fi
    fi
else # Color requested
    if echo "$OPTIONS" | grep -q "CNColorMode"; then
        LPADMIN_FLAGS+=("-o" "CNColorMode=color")
    elif echo "$OPTIONS" | grep -q "KCColorMode"; then
        LPADMIN_FLAGS+=("-o" "KCColorMode=KCColor")
    elif echo "$OPTIONS" | grep -q "ColorMode"; then
        LPADMIN_FLAGS+=("-o" "ColorMode=Color")
    elif echo "$OPTIONS" | grep -q "ColorModel"; then
        if echo "$OPTIONS" | grep -F "ColorModel=" | grep -q "RGB"; then LPADMIN_FLAGS+=("-o" "ColorModel=RGB")
        elif echo "$OPTIONS" | grep -F "ColorModel=" | grep -q "Color"; then LPADMIN_FLAGS+=("-o" "ColorModel=Color")
        fi
    fi
fi

# ==============================================================================
# VENDOR LOGIC MAP: STAPLE
# ==============================================================================
if [ "$STAPLE_REQ" = "staple" ]; then
    if echo "$OPTIONS" | grep -q "CNStaple"; then                        # Canon
        LPADMIN_FLAGS+=("-o" "CNStaple=True" "-o" "StapleLocation=TopLeft")
    elif echo "$OPTIONS" | grep -q "KCStaple"; then                      # Kyocera
        LPADMIN_FLAGS+=("-o" "KCStaple=UpperLeft")
    elif echo "$OPTIONS" | grep -q "StapleLocation"; then                # Ricoh / Fallback
        if echo "$OPTIONS" | grep -F "StapleLocation=" | grep -q "UpperLeft"; then
            LPADMIN_FLAGS+=("-o" "StapleLocation=UpperLeft")
        else
            LPADMIN_FLAGS+=("-o" "StapleLocation=SinglePortrait")
        fi
    elif echo "$OPTIONS" | grep -q "StaplePos"; then                     # Sharp
        LPADMIN_FLAGS+=("-o" "StaplePos=1StapleFront")
    fi
else # Disable stapling
    if echo "$OPTIONS" | grep -q "CNStaple"; then LPADMIN_FLAGS+=("-o" "CNStaple=False")
    elif echo "$OPTIONS" | grep -q "KCStaple"; then LPADMIN_FLAGS+=("-o" "KCStaple=None")
    elif echo "$OPTIONS" | grep -q "StapleLocation"; then LPADMIN_FLAGS+=("-o" "StapleLocation=None")
    elif echo "$OPTIONS" | grep -q "StaplePos"; then LPADMIN_FLAGS+=("-o" "StaplePos=None")
    fi
fi

# ==============================================================================
# VENDOR LOGIC MAP: HOLE PUNCH
# ==============================================================================
if [ "$PUNCH_REQ" = "punch" ]; then
    if echo "$OPTIONS" | grep -q "CNPuncher"; then                       # Canon
        PUNCH_MOD=$(echo "$OPTIONS" | grep "CNPuncher" | grep -oE "PUNU23|PUNF24|PUNU24" | head -n1)
        [ -n "$PUNCH_MOD" ] && LPADMIN_FLAGS+=("-o" "CNPuncher=$PUNCH_MOD")
        echo "$OPTIONS" | grep -q "CNMultiPunch" && LPADMIN_FLAGS+=("-o" "CNMultiPunch=PUNU3")
    elif echo "$OPTIONS" | grep -q "KCPunch"; then                       # Kyocera
        LPADMIN_FLAGS+=("-o" "KCPunch=On")
    elif echo "$OPTIONS" | grep -q "PunchOption"; then                    # Ricoh
        LPADMIN_FLAGS+=("-o" "PunchOption=On")
    elif echo "$OPTIONS" | grep -q "PunchType"; then                     # Sharp
        PUNCH_VAL=$(echo "$OPTIONS" | grep "PunchType" | grep -oE "3Holes|2Or3Holes|On" | head -n1)
        [ -n "$PUNCH_VAL" ] && LPADMIN_FLAGS+=("-o" "PunchType=$PUNCH_VAL")
    fi
else # Disable punching
    if echo "$OPTIONS" | grep -q "CNPuncher"; then 
        LPADMIN_FLAGS+=("-o" "CNPuncher=None")
        echo "$OPTIONS" | grep -q "CNMultiPunch" && LPADMIN_FLAGS+=("-o" "CNMultiPunch=Off")
    elif echo "$OPTIONS" | grep -q "KCPunch"; then LPADMIN_FLAGS+=("-o" "KCPunch=None")
    elif echo "$OPTIONS" | grep -q "PunchOption"; then LPADMIN_FLAGS+=("-o" "PunchOption=None")
    elif echo "$OPTIONS" | grep -q "PunchType"; then LPADMIN_FLAGS+=("-o" "PunchType=None")
    fi
fi

# ==============================================================================
# VENDOR LOGIC MAP: JOB ACCOUNTING / USER CODE
# ==============================================================================
# Canon's Dept ID / PIN are entered in the driver dialog and are not exposed as
# PPD options, so for Canon only the enable switch can be set from here.
if [ "$ACCT_REQ" = "yes" ]; then
    if echo "$OPTIONS" | grep -q "CNUseJobAccount"; then                   # Canon
        LPADMIN_FLAGS+=("-o" "CNUseJobAccount=True")
        echo "$OPTIONS" | grep -q "CNUsrManagement" && LPADMIN_FLAGS+=("-o" "CNUsrManagement=Dept")
        [ -n "$USERCODE" ] && echo "[!] Canon: Department ID/PIN cannot be preset; users enter them at print time."
    elif echo "$OPTIONS" | grep -q "KmManagment"; then                     # Kyocera
        if [ -z "$USERCODE" ]; then
            echo "[!] Kyocera: an accounting code is required to enable job accounting."
        elif echo "$OPTIONS" | grep -F "KmManagment/" | grep -qw -- "$USERCODE"; then
            LPADMIN_FLAGS+=("-o" "KmManagment=$USERCODE")
        else
            echo "[!] Kyocera: code '$USERCODE' is not in this driver's accounting list (e.g. MG00000001)."
        fi
    elif echo "$OPTIONS" | grep -q "KMSection"; then                      # Konica Minolta
        LPADMIN_FLAGS+=("-o" "KMSection=True")
        echo "[!] Konica Minolta: Account Track enabled; the account number is entered at print time."
    elif echo "$OPTIONS" | grep -q "ARAccountLogin"; then                  # Sharp
        if [ -n "$USERCODE" ]; then
            LPADMIN_FLAGS+=("-o" "ARAccountLogin=Custom.$USERCODE")
            [ -n "$ACCT_PIN" ] && LPADMIN_FLAGS+=("-o" "ARAccountPassword=Custom.$ACCT_PIN")
        else
            echo "[!] Sharp: a login name/user code is required."
        fi
    elif echo "$OPTIONS" | grep -qiE "^[A-Za-z]*UserCode"; then            # Ricoh (unverified)
        UC_OPT=$(echo "$OPTIONS" | grep -iE "^[A-Za-z]*UserCode" | head -n1 | cut -d/ -f1)
        [ -n "$USERCODE" ] && LPADMIN_FLAGS+=("-o" "$UC_OPT=Custom.$USERCODE")
    else
        echo "[!] No known job accounting option found for this driver."
    fi
else # Accounting not requested: turn it off where a simple switch exists
    if echo "$OPTIONS" | grep -q "CNUseJobAccount"; then
        LPADMIN_FLAGS+=("-o" "CNUseJobAccount=False")
        echo "$OPTIONS" | grep -q "CNUsrManagement" && LPADMIN_FLAGS+=("-o" "CNUsrManagement=Off")
    elif echo "$OPTIONS" | grep -q "KmManagment"; then LPADMIN_FLAGS+=("-o" "KmManagment=Default")
    elif echo "$OPTIONS" | grep -q "KMSection"; then LPADMIN_FLAGS+=("-o" "KMSection=False")
    fi
fi

# ==============================================================================
# EXECUTION (GLOBAL / SYSTEM-WIDE)
# ==============================================================================
# lpadmin writes the queue defaults to the CUPS server (/etc/cups/printers.conf),
# so they apply to every user. It needs root; re-run under sudo if necessary.
# Per-user overrides in ~/.cups/lpoptions would mask these defaults, so any
# override of the options we set is removed for the invoking user.
if [ ${#LPADMIN_FLAGS[@]} -gt 0 ]; then
    SUDO=""
    [ "$(id -u)" -ne 0 ] && SUDO="sudo"
    echo "[+] Applying global defaults to $QUEUE (may prompt for admin password)..."
    if $SUDO lpadmin -p "$QUEUE" "${LPADMIN_FLAGS[@]}"; then
        REAL_USER="${SUDO_USER:-$USER}"
        USER_HOME=$(eval echo "~$REAL_USER")
        if [ -f "$USER_HOME/.cups/lpoptions" ]; then
            for ((k=1; k<${#LPADMIN_FLAGS[@]}; k+=2)); do
                OPT_NAME="${LPADMIN_FLAGS[k]%%=*}"
                lpoptions -p "$QUEUE" -r "$OPT_NAME" >/dev/null 2>&1
            done
        fi
        echo "[+] Done. Global defaults set for all users of $QUEUE."
    else
        echo "[-] lpadmin failed; no changes were applied."
        exit 1
    fi
else
    echo "[-] No valid target driver options matched configuration profiles."
fi
