# PrintDefaults

Interactive macOS/CUPS script that sets **system-wide default print options** on a printer queue, across Canon, Kyocera, Konica Minolta, Ricoh, Sharp and generic IPP Everywhere/AirPrint drivers. It reads the queue's actual PPD options (`lpoptions -l`) and maps your choices to whichever vendor-specific option names that driver uses.

## What it configures

| Setting | Choices |
|---|---|
| Layout | Simplex/Duplex × Monochrome/Color (default: simplex + mono) |
| Finishing | None, staple, hole punch, or both |
| Job accounting (optional) | Off (default) or on, with an optional user code and PIN |

## Usage

```sh
chmod +x printdefaults.sh
./printdefaults.sh
```

1. Pick a queue from the list of installed printers.
2. Choose layout and finishing options.
3. Answer `y` to "Enable job accounting?" if wanted, then enter the user code (and PIN, if the driver supports one).
4. The script applies everything with `lpadmin`.

Requires macOS (or any system with CUPS) and admin rights; the script calls `sudo` itself when not run as root.

## Global vs. per-user

Settings are written with `lpadmin`, which stores them on the CUPS server (`/etc/cups/printers.conf`), so they apply to **every user** of the Mac. Because per-user overrides in `~/.cups/lpoptions` take precedence over server defaults, the script also removes any override of the options it just set for the invoking user. Other users' own overrides are not touched.

## Job accounting support

Vendors expose accounting differently, so behaviour varies:

| Driver | Option | Behaviour |
|---|---|---|
| Canon | `CNUseJobAccount`, `CNUsrManagement` | Enables Department ID Management. Dept ID/PIN are not PPD options, so users enter them when printing. |
| Kyocera | `KmManagment` | Sets the accounting code; it must be one of the driver's listed codes (e.g. `MG00000001`). |
| Konica Minolta | `KMSection` | Enables Account Track; the account number is entered at print time. |
| Sharp | `ARAccountLogin`, `ARAccountPassword` | Sets login name/user code and password. |
| Ricoh | `*UserCode` option | Sets the user code. **Untested**, as no Ricoh queue was available. |

Answering `n` turns accounting off where the driver has a simple switch (Canon, Kyocera, Konica Minolta). Where no known option exists, the script says so and changes nothing for accounting.

Note: the PIN is passed to `lpadmin` on the command line, so it is briefly visible in the process list and stored in plain text in the CUPS configuration. Treat it as a convenience code, not a secret.

## Notes

- Drivers with no matching option for a setting are skipped silently for that setting.
- Test on a non-production queue first; option names come from each vendor's PPD and may differ between driver versions.
