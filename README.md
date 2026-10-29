# PrintDefaults

Interactive macOS/CUPS script that sets default print options on a printer queue for **Canon, Ricoh, Sharp and Kyocera** drivers. It reads the queue's actual PPD options (`lpoptions -l`), detects the vendor from the driver's option names, and maps your choices to that vendor's option keys.

## What it configures

| Setting | Choices |
|---|---|
| Scope | Global (all users) or per user |
| Layout | Simplex/Duplex × Monochrome/Color (default: simplex + mono) |
| Finishing | None, staple, hole punch, or both |
| Job accounting (optional) | Off (default) or on, with an optional user code |

## Usage

```sh
chmod +x printdefaults.sh
./printdefaults.sh
```

1. Pick a queue from the installed printers; the driver vendor is detected automatically.
2. Choose **global** or **per user**.
3. Choose layout and finishing options.
4. Answer `y` to "Enable job accounting?" if wanted, then enter a user code.

### Advanced mode (`-a`)

```sh
./printdefaults.sh -a
```

Without `-a` the script runs in easy mode (the simple menus above). With `-a`, the layout and finishing menus are replaced by a numbered list for each setting, built from the values the queue's PPD actually offers: duplex (long/short edge), color mode, staple (including position, e.g. top-right or 2 at left) and hole punch (e.g. 2 at top instead of 3 at left). Each list shows the PPD's human-readable labels, marks the **[current]** value and the easy-mode **[recommended]** value, and Enter keeps the "off" choice. For Canon, staple position and punch hole pattern are asked as a follow-up when stapling/punching is enabled. Scope selection and the accounting prompts work the same as in easy mode.

## Output

After the settings are applied, the script prints a summary:

```
Queue: zTest_Ricoh
Color: mono
Duplex: single
Staple: none
Punch: none
Accounting: enabled
Code: 12345
```

In advanced mode, staple and punch show the chosen position/pattern (e.g. `Staple: Top right`, `Punch: 2 at top`). Passwords are never printed.

## Global vs. per user

| | Global | Per user |
|---|---|---|
| Mechanism | `sudo lpadmin` (stored in `/etc/cups/printers.conf`) | `lpoptions` (stored in `~/.cups/lpoptions`) |
| Applies to | Every user of the Mac | Only the current user |
| Needs admin | Yes (script calls `sudo`) | No |

With global scope, the script also removes the current user's own overrides of the options it just set, since `~/.cups/lpoptions` would otherwise mask the new global default. Other users' overrides are left alone.

**The user code is saved per user** (in `~/.cups/lpoptions`), even when everything else is global, so each person keeps their own code. The exception is Canon: its Department ID/PIN live in the queue's PPD, so they are queue-wide and only written in global mode.

## Job accounting and user codes

| Driver | Enable switch (follows scope) | User code (always per user) |
|---|---|---|
| Canon | `CNUseJobAccount` + `CNUsrManagement=Dept` (queue-level installed option, set with `lpadmin`) | Department ID + PIN, written into the queue's PPD (`*%INFO_JoAc` block, the same place Canon's Printer Utility stores them). **Queue-wide**, so only written in global mode |
| Ricoh | `RIEnableUserCode` | `RIUserCode` |
| Sharp | none | Your choice of user code (`ARUserNumber=Custom.<code>`) or login name + password (`ARAccountLogin`, `ARAccountPassword`) |
| Kyocera | none | `KmManagment`; the PPD only offers a fixed list (typically `00000000`–`00000030`), so arbitrary codes can't be set. Enter plain digits (e.g. `7`) and the script maps them to `MG00000007`, re-asking if the code isn't in the list |

Answering `n` turns accounting off (Canon, Ricoh), resets Kyocera's code to `Default`, or clears your saved Sharp user number / login / password. On Sharp, picking one method also clears the other's saved values.

User codes (and Sharp passwords) are stored in plain text in `~/.cups/lpoptions`.

## Testing status

Per-user easy mode was exercised against Canon, Ricoh, Kyocera and Sharp queues, and advanced mode (`-a`) against Ricoh and Canon. Global mode (sudo/`lpadmin`) has not been run end to end. Option names come from vendor PPDs and may differ between driver versions, so try a test queue first.
