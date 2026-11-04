# Save versioning, migration, and robustness

Saves can outlive the code that wrote them. Reol keeps one current game model
and write format; supported old inputs are explicitly bounded by the
[compatibility policy](../../../../docs/COMPATIBILITY.md).

## The version field is non-negotiable

Stamp every save with an integer `version` (or a structured `{major, minor}` if
you need it). On load:

1. Read `version`.
2. If it is **unsupported**, whether newer or retired → refuse with a clear
   message. Do not guess at fields you don't know or rewrite the source save.
3. If it is an explicitly supported older input → apply the declared migrations
   to one current model.
4. Validate an independent candidate completely, then publish it; failure must
   leave the live world and source data unchanged.

Prefer a single monotonic integer. Semantic two-part versions are only worth it
if you genuinely branch save compatibility across release lines.

## The migration chain

For a declared compatibility window, write each migration as a **pure function**
`vN -> vN+1` and apply them in order. Runtime logic reads only the current model;
do not silently accept versions outside the declared window.

```python
SAVE_VERSION = 4

SUPPORTED_VERSIONS = {3, 4}  # example only; see Reol's policy for actual support
MIGRATIONS = {
    3: migrate_3_to_4,   # inventory items gained a "durability" field
}

def upgrade(data):
    v = read_version(data)  # reject missing or malformed versions
    if v not in SUPPORTED_VERSIONS:
        raise UnsupportedSaveError(v)
    validate_source(data, v)
    while v < SAVE_VERSION:
        data = MIGRATIONS[v](data)
        v += 1
        data["version"] = v
    return data
```

Guidelines:

- **Additive changes are easy**: new field with a default. The migration just
  inserts the default for old saves.
- **Renames/restructures**: move/transform in the migration; never read both old
  and new names in game code.
- **Removed fields**: drop them in the migration so later steps see a clean shape.
- **Bound compatibility explicitly**: retire migration paths according to the
  project policy, without editing historical fixtures or player saves.
- **Test supported boundaries**: exercise each declared migration and verify
  unsupported versions fail clearly and atomically; retain historical evidence
  as read-only fixtures rather than promising every version will load forever.

## Backups and rollback

- Before overwriting, copy the current save to `*.bak`. A backup recovery policy
  must not silently replace an unsupported save with a different history.
- For autosaves, rotate a small ring (autosave_0..2) so a bad autosave doesn't
  destroy the only recent state.
- Consider a checksum/hash of the payload to detect truncation or corruption
  (distinct from anti-tamper, which a determined local player can always defeat).

## Format trade-offs

| Format | Pros | Cons | Use when |
|---|---|---|---|
| JSON / text | Human-readable, debuggable, diff-able, easy migration | Larger, slower, trivially editable | Default; most games |
| Binary (engine) | Compact, fast, mildly opaque | Hard to debug/migrate, version-fragile | Large state, perf-critical |
| Key/value store | Simple, robust per-key | No structure, manual schema | Settings, small flag sets |
| Cloud KV (e.g. DataStore) | Cross-device | Quotas, latency, conflicts | Online/cross-device saves |

Whatever the on-disk format, keep an **in-memory dictionary/struct** as the
canonical shape and (de)serialize at the boundary. Migrations then operate on
that neutral shape, not on format-specific bytes.

## Load-time validation checklist

- Required keys present; types correct (string vs number vs bool).
- Numbers within sane ranges (no NaN/Infinity; hp ≥ 0; indices in bounds).
- Enum/id values still exist in current content; reject or use only an explicitly
  supported migration, without silently dropping or substituting owned objects.
- References resolve (a quest id points to a known quest).
- On any failure: report clearly without changing the live world or source save;
  use a backup only under an explicit recovery policy that preserves history.

## Where saves live, and cloud sync

Write saves to the per-user data folder the engine gives you, never next to the
executable (often read-only, and replaced by updates):

- **Godot 4.7** `user://` — Windows `%APPDATA%\Godot\app_userdata\[project]`,
  macOS `~/Library/Application Support/Godot/app_userdata/[project]`, Linux
  `~/.local/share/godot/app_userdata/[project]`. Turn on
  `application/config/use_custom_user_dir` (optionally with
  `custom_user_dir_name`) to drop the `Godot/app_userdata` part before you ship,
  because changing it later moves every player's saves. Web exports store
  `user://` in the browser's IndexedDB.
- **Unity 6.3** `Application.persistentDataPath` — Windows
  `%userprofile%\AppData\LocalLow\<company>\<product>`, Linux
  `~/.config/unity3d/<company>/<product>`, macOS player
  `~/Library/Application Support/unity.<company>.<product>`; Web uses IndexedDB;
  tvOS returns an empty string (no persistent folder). Changing the company or
  product name changes the folder.
- **Unreal 5.8** `UGameplayStatics::SaveGameToSlot` / `AsyncSaveGameToSlot`
  with a `USaveGame` subclass; the platform layer picks the folder and, on
  consoles, the platform save API.

**Steam Cloud.** Auto-Cloud syncs files under the root paths you configure in
Steamworks (for example `WinAppDataRoaming`, `WinAppDataLocalLow`,
`MacAppSupport`, `LinuxXdgDataHome`); the ISteamRemoteStorage API is the
alternative when you need control. Files upload after the game exits and
download before the next launch, so a save written while the game runs is not
in the cloud yet. Choose the Cross-Platform OS setting for each root (with root
overrides where the folder differs per OS) even for a single-platform game: a
root locked to one OS will not sync to other platforms if you add them later.
Set the per-user byte and file quotas in the app admin panel first; Steam Cloud
is not active without them. Keep the `.tmp` file out of the synced pattern.
Games that opt into Dynamic Cloud Sync (Steam Deck suspend) can receive changed
files mid-session and must reload them.

**Consoles and mobile** have platform save APIs, storage limits and
certification rules; follow the platform's documentation rather than raw file
paths there.

## What to store vs recompute

- **Store** authoritative, non-derivable state: choices, unlocked flags, RNG
  seed, inventory, positions.
- **Recompute** derived data on load (full stat tables from base + modifiers,
  procedural maps from the seed). Saving derived data invites desync when the
  formula changes in a patch — and bloats the file.
