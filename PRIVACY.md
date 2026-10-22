# Privacy

DragWheel processes files on your computer and nowhere else.

- **No network access.** The apps contain no networking code. There are no accounts, analytics, crash reporting, telemetry, advertising or update checks.
- **Files.** DragWheel opens only the files you drop on it or pick in its window. It writes new files next to the originals, or in a folder you choose. It never modifies or deletes your originals. Undo moves a result to the Trash or Recycle Bin.
- **Keyboard and mouse.** DragWheel needs to know when you're dragging a file and press **Shift**. On macOS it uses system event monitors, which need the Accessibility permission. On Windows it uses low-level input hooks. The only keys it reacts to are Shift, Tab and Esc, and only while the wheel is open. Typed text is never read, stored or sent anywhere.
- **Settings.** Your preferences stay on your machine:
  - macOS: `~/Library/Preferences/io.github.nico43245.dragwheel.plist`
  - Windows: `%APPDATA%\DragWheel\settings.json`
- **Helpers.** For video and audio, DragWheel runs your own copy of ffmpeg, and on macOS also `cwebp`. They run as local programs with your files as input.
