# turnOffSiri.sh

Bulk-enable, disable, or restore per-application Siri learning and suggestions for the current macOS user.

By default, the script turns both settings **off**. It creates a backup before changing preferences and can print each application's status and action as it processes that application.

## Scope

The script updates two arrays in the `com.apple.suggestions` preference domain:

| Preference | Purpose |
| --- | --- |
| `SiriCanLearnFromAppBlacklist` | Apps excluded from Siri learning |
| `AppCanShowSiriSuggestionsBlacklist` | Apps excluded from showing Siri suggestions |

These are underlying preference keys, not a documented Apple management API. The learning key was checked against the “Learn from this application” switch on macOS 27.0.1. This script has **not** been established to manage the newer **Siri → Excluded Apps** list or every Siri data-access permission. It also does not turn Siri itself on or off.

## Requirements

- macOS with `/bin/zsh`, `defaults`, `plutil`, and `PlistBuddy`.
- A writable Desktop folder for backups.
- An ANSI-compatible terminal for colored output.

Developed against macOS 27.0.1. Other versions have not been verified. No additional packages are required. The script does not work in iSH or on a standard iPhone.

## Setup

Place the script in your preferred folder and make it executable:

```zsh
chmod +x turnOffSiri.sh
```

Run it from that folder using `./turnOffSiri.sh`, or invoke it with `zsh turnOffSiri.sh`. Do not invoke it with `sh` or `bash`. Run it as the user whose settings you want to change; `sudo` is unnecessary.

If your copy is named `turnOffSiriLearn.sh`, substitute that filename in the examples below.

## Commands

```text
./turnOffSiri.sh [-v] [-on | -off | -restore path-to-file]
```

| Parameter | Behavior |
| --- | --- |
| No parameters | Turn learning and suggestions off. |
| `-off` | Explicitly turn both settings off. This is the default. |
| `-on` | Remove discovered apps from both blacklists, allowing learning and suggestions. |
| `-v` | Print colored per-application rows as each app is processed. |
| `-restore path-to-file` | Restore both preference arrays from a backup plist. Always prints per-application rows, even without `-v`. |
| `-h`, `--help` | Display parameter descriptions and examples, then exit without changes. |

Use only one of `-on`, `-off`, or `-restore`. The `-v` flag can appear before or after the selected operation. Quiet mode still prints the operation message, backup location, and errors.

### Turn settings off

```zsh
./turnOffSiri.sh -v
```

Equivalent explicit command:

```zsh
./turnOffSiri.sh -off -v
```

### Turn settings on

```zsh
./turnOffSiri.sh -on -v
```

This enables both settings for discovered apps. To recover a previous mix of enabled and disabled settings, restore its backup instead.

### Restore a backup

```zsh
./turnOffSiri.sh -restore "$HOME/Desktop/siri-settings-20261101-123456-AbCdEf.plist"
```

Replace the example path with an actual backup file. Quote paths containing spaces. Restore also creates a new backup of the settings it is about to replace.

### Show help

```zsh
./turnOffSiri.sh -h
```

## Output

The script begins with one of these messages:

```text
Turning off Siri settings for all Applications
Turning on Siri settings for all Applications
Restoring Siri settings from backup
```

Verbose mode and every restore operation include these columns:

```text
APPLICATION                                                      - CURRENT - ACTION         - APPLICATION PATH
Example                                                          - ON      - Turning OFF    - /Applications/Example.app
Another App                                                      - OFF     -                - /Applications/Another App.app
```

| Column | Meaning and appearance |
| --- | --- |
| `APPLICATION` | Application name in cyan, padded to a minimum width of 64 characters. Longer names are not truncated. |
| `CURRENT` | State before processing that app: green `ON`, red `OFF`, or red `SKIP`. |
| `ACTION` | Red `Turning OFF`, green `Turning ON`, red `FAILED`, or `No bundle ID`. Blank when no change is needed. |
| `APPLICATION PATH` | Full app path in blue. |

`ON` means at least one of learning or suggestions is allowed by these arrays. `OFF` means the app appears in both blacklists. This is a combined status, not a separate report for each setting.

During restore, the action follows the saved settings. An app currently `OFF` that was enabled in the backup prints `OFF` with `Turning ON`. If the backup contains a mixed state, the script restores that exact combination; `Turning ON` may mean only one of the two settings is being enabled.

Each row is printed after that application's preference writes return, before the next app is processed. Already-correct apps are printed immediately without a write. The script verifies the complete preference arrays once at the end. A printed action therefore indicates a completed write attempt, not independent confirmation that every macOS service has adopted it.

## Application discovery

The script searches these folders:

- `/Applications`
- `/System/Applications`
- `/System/Library/CoreServices/Applications`
- `~/Applications`, when present

It processes `.app` bundles using their `CFBundleIdentifier`. Bundles without a readable identifier are skipped. It does not descend into app bundles to process embedded helper apps, and it does not search arbitrary external folders or volumes.

“All Applications” in the opening message refers to the apps discovered in these folders. Newly installed apps require another run.

## Backups and restoration

Backups are saved on the current user's Desktop using this pattern:

```text
siri-settings-YYYYMMDD-HHMMSS-XXXXXX.plist
```

The backup contains an export of the entire `com.apple.suggestions` domain. Restoration writes only the two Siri preference arrays listed above, leaving other preferences unchanged.

Restore also recovers saved entries for apps that are no longer installed. Per-app output covers discovered installed apps; restoring entries for absent apps happens in the final array restoration step.

A missing array in an otherwise accepted backup is restored by removing that preference key. A plist containing neither Siri array is rejected. Backups created by the earlier `defaults export com.apple.suggestions ...` command are supported when they contain at least one of the two arrays.

## Verification and troubleshooting

After a run, close and reopen System Settings and inspect several apps' learning and suggestion controls. Preference readback is checked automatically, but the script does not restart Siri or other system services.

| Problem | Action |
| --- | --- |
| `Permission denied` when launching | Run `chmod +x turnOffSiri.sh`, or use `zsh turnOffSiri.sh`. |
| Parse error | Check with `zsh -n turnOffSiri.sh`. Replace the entire file with the current version rather than combining fragments from older versions. |
| Backup cannot be created | Check that `~/Desktop` exists and is writable. No preference writes occur before the backup succeeds. |
| Backup not found | Check the filename and quote the full path. |
| `FAILED` or final verification error | Some writes may already have succeeded. Inspect the reported backup and use `-restore` if recovery is needed. |
| Settings appear unchanged | Reopen System Settings. Confirm that you are checking learning/suggestions controls rather than assuming these keys control the newer Excluded Apps feature. |

Run only one copy at a time and avoid manually changing the same settings while it runs. The script caches the arrays during processing; simultaneous edits can be overwritten or cause final verification to fail.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Completed without a detected preference-write/readback failure, or displayed help. Apps without bundle identifiers may still have been skipped. |
| `1` | A setup, backup, preference read/write, or verification operation failed. |
| `2` | Invalid parameters or conflicting operations. |
| `130` | Interrupted with Ctrl-C. |
| `143` | Terminated by a TERM signal. |

Changes are applied incrementally, not as a transaction. Interrupting the script can leave some apps changed and others unchanged; the backup remains available for recovery.

## Validation status

Syntax and isolated preference tests cover default-off behavior, enabling, exact restoration, restore output, preservation of unrelated settings, and conflicting arguments. Full bulk changes have not been verified end-to-end against every app's Settings interface.
