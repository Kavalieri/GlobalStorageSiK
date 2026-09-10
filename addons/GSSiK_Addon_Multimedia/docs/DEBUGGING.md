# Multimedia diagnostics

Version: 0.1.0-dev1. Logs are disabled by default. Enable only the relevant
category together with the master option in the sandbox menu.

| Key | Spanish label | English label | Purpose |
|---|---|---|---|
| DebugMode | Modo debug (Multimedia) | Debug mode (Multimedia) | Master switch |
| DebugRegistration | Registro del addon | Addon registration | Registration failures |
| DebugPlayback | Reproducción y devolución | Playback and return | Bounded requests, rejections and exact-unit playback |

Options belong to `GSSiK_Addon_Multimedia`. Output uses
`[SP][GSSiK_Addon_Multimedia:DEBUG][Playback] client command=start ok=false reason=...`
or `[SP][GSSiK_Addon_Multimedia:DEBUG][Playback] start terminal=... item=...`
or the actual `[CLI]`, `[SRV]`, `[HOST]` origin. Error level is `ERROR`.
Categories cap output at ten lines per second and 1024 characters per message.
There is no high-volume detail mode or continuous catalog polling.

Keep `console.txt` from the player and the dedicated server's console log for MP.
For a reproduction, retain the entire test save separately, including its ModData;
do not hand-edit the lease or device records. Exact IDs and sequences help distinguish
identical VHS copies. Personal names and unrelated logs are not required.

For ordinary UI/recipe checks leave all diagnostic options off. For playback,
stop, ejection or recovery use only DebugMode + DebugPlayback. Registration
investigation uses only DebugMode + DebugRegistration. Client-only success does
not prove authoritative MP completion.
