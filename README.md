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

## Global vs. per user

| | Global | Per user |
|---|---|---|
| Mechanism | `sudo lpadmin` (stored in `/etc/cups/printers.conf`) | `lpoptions` (stored in `~/.cups/lpoptions`) |
| Applies to | Every user of the Mac | Only the current user |
| Needs admin | Yes (script calls `sudo`) | No |

With global scope, the script also removes the current user's own overrides of the options it just set, since `~/.cups/lpoptions` would otherwise mask the new global default. Other users' overrides are left alone.

**The user code is always saved per user**, even when everything else is global, so each person keeps their own code.

## Job accounting and user codes

| Driver | Enable switch (follows scope) | User code (always per user) |
|---|---|---|
| Canon | `CNUseJobAccount` + `CNUsrManagement=Dept` | Not settable: Dept ID/PIN aren't PPD options, so users enter them when printing |
| Ricoh | `RIEnableUserCode` | `RIUserCode` |
| Sharp | none | Your choice of user code (`ARUserNumber=Custom.<code>`) or login name + password (`ARAccountLogin`, `ARAccountPassword`) |
| Kyocera | none | `KmManagment`; must be one of the driver's listed codes (e.g. `MG00000001`) |

Answering `n` turns accounting off (Canon, Ricoh) resets Kyocera's code to `Default`, or clears your saved Sharp user number / login / password. On Sharp, picking one method also clears the other's saved values.

User codes (and Sharp passwords) are stored in plain text in `~/.cups/lpoptions`.

## Testing status

Per-user mode was exercised against Canon, Ricoh, Kyocera and Sharp queues. Global mode (sudo/`lpadmin`) has not been run end to end. Option names come from vendor PPDs and may differ between driver versions, so try a test queue first.
