# GSSiK Addon — Multimedia

Development version 0.1.0-dev1 for Project Zomboid B42.20+. Requires
`GlobalStorageSiK` and `SiKUIFramework`. Workshop ID: `3798890105`.
This is a development candidate; its first Workshop upload was performed by Kava.

Find or build the GS Multimedia housing, heads and power supply, then assemble
the GS Multimedia player. Learn its magazine and the separate GS Multimedia
disk-programming magazine.
Recording the program produces an installation disk in the player's inventory.
Installing the player on a terminal enables Multimedia for that terminal.
The normal Core reader, disk and installation checks remain in force.

The installed peripheral turns the terminal into the player. No nearby TV or
radio is required. In Multimedia, filter network VHS tapes by title or skill,
sort by title or skill, and select multiple rows across pages. Play uses the
selection, or all filtered results when nothing is selected. All plays the
entire accessible catalogue. Only the current tape is borrowed; each successor
starts after its predecessor returns. Stop preserves filters and selection,
tracking the exact returned successor when vanilla changes the item ID.

Switch the same player to Radio, enter a frequency in MHz and tune it. Volume
controls affect the native receiver at the terminal. Playback, sound, subtitles
and learning belong to Project Zomboid; learned status belongs to the viewing
character. There is no added video renderer or custom XP system. Closing the
window, walking away, dying or disconnecting does not stop playback or its queue.
Other nearby players hear and learn through the native rules. Any player with
current access to the terminal can control it. Removing its peripheral or losing
power stops the queue and attempts a safe return.

Vanilla ejection creates a new inventory item with the same recorded content.
Its old ID and custom metadata are not preserved. Multimedia observes that exact
successor directly into the source container through Core custody; it never
substitutes an already held identical VHS. If the source is unavailable or full,
the tape remains inside the receiver. Recover retries that return. Destroying
a device or interrupting an ambiguous engine
operation does not authorize the addon to manufacture missing media.

Catalogs are read on demand with bounded pages. The server validates the player,
network, installed player, device and distance before accepting a command.
Once accepted, the job belongs to the terminal: later queue transitions validate
the terminal, installation and exact tape in an originally authorized source,
without requiring the initiating character to remain nearby or online.
Progress and learned lines are never stored in network or global addon caches.
The catalogue/queue safety ceiling is 16,384 tapes; exceeding it returns an error
instead of silently truncating a selection. Selection is transmitted in batches
of at most 64 and cannot start until the complete request has been received.
Unloading the area or closing/reloading the world cancels the playlist. Loading
leaves the receiver switched off and reconciles the inserted tape; it does not
restart playback. An ordinary autosave does not interrupt a loaded receiver.
If safe return is unavailable, the last tape stays inserted until recovery.
If the terminal was removed, reinstall a terminal
and the peripheral at its original anchor to access a parked tape. No replacement
tape is manufactured if native custody cannot be proven.

Languages: EN, ES, DE, FR, IT, PL, PTBR, RU, CN, CH.
Diagnostics: [DEBUGGING.md](docs/DEBUGGING.md). SP validation does not certify
dedicated/hosted multiplayer or split-screen behavior.
