# PinShot 📌

![Platform](https://img.shields.io/badge/Platform-macOS-lightgrey.svg)
![Swift](https://img.shields.io/badge/Swift-5.0-orange.svg)
![License](https://img.shields.io/badge/License-MIT-blue.svg)

<img src="./icon.png" alt="PinShot Icon" width="160" />

**PinShot** is a lightweight, native macOS utility that lets you take screenshots and instantly pin them to your screen as floating, always-on-top windows. It's designed to help you keep reference materials, code snippets, or designs visible while you work.

## ✨ Features

* **Screenshot Editor (`Option + A`):** Freeze the screen, drag a region or click a window once, then annotate, copy, save, or pin the locked selection.
* **Screenshot Annotations:** Add rectangles, ellipses, arrows, freehand strokes, text, or mosaic with selectable colors and stroke widths. Undo and redo edits before exporting at the display's original pixel resolution.
* **Instant Screen Freeze:** The exact moment you press the shortcut, the screen freezes, allowing you to capture transient states like hover menus or tooltips.
* **Smart Window Selection:** Hover over any open window to highlight it, and simply **click** to capture the entire window perfectly.
* **Custom Region Capture:** Click and **drag** to select and capture a specific region of your screen.
* **Multi-Monitor Support:** Works seamlessly across all your connected displays.
* **Always on Top:** Pinned screenshots float above all other windows, ensuring your reference material is never hidden.
* **Quick Save Screenshot:** Press `Option + 2` to save a screenshot to the macro folder and reuse the last selected region.
* **Region Overlay Preview:** When you save with `Option + 2`, the saved area stays highlighted until you press `Esc`.
* **Pixel Magnifier:** While selecting a save region, a zoom lens shows cursor-adjacent pixels with pixel coordinates.
* **Opt+2 Macro Panel:** With `Option + 2`, a macro panel appears below the region so you can run a loop: screenshot -> after-shortcut -> post-delay -> configurable rest -> optional periodic shortcut -> repeat.
* **Lightweight & Native:** Built purely with Swift and AppKit (No Electron, minimal resource usage).
* **Automatic Updates:** Sparkle checks for updates and downloads them automatically. Use **Check for Updates…** in the menu to check manually. Releases are signed with Developer ID, notarized by Apple, and verified against signed update packages and feeds.
* **Settings Window:** Manage launch at login, history, separate save folders, screenshot framing, and global shortcuts.
* **Screenshot Frames:** Open **Frame…** for corner sliders, independent top/bottom/left/right padding, and background controls. Adjust all corners together or select one corner; the blue selection outline follows each corner's radius live. Capture outlines, saved-region indicators, and the magnifier share the same blue color. The embedded color picker supports presets, RGB sliders, and hex colors. Padding appears in the Frame preview and final output, not around the selected screen region. Changed values are remembered for subsequent captures.
* **Pin History:** Capture & Pin automatically saves PNGs in the pinned screenshot folder and keeps a persistent history. Disable new history saves in Settings without losing previous captures.
* **Draw on Pins:** Use the pencil button on a pin to draw with a pen, rectangles, ellipses, arrows, or mosaic. Choose a color and stroke width, undo/redo, and finish with Done or Escape. Edited pins update their history image.

## ⌨️ Shortcuts

| Shortcut | Action |
| --- | --- |
| `Option + A` | Select a screenshot range once, then annotate or export |
| `Option + 1` | Capture & Pin; automatically save to history when enabled |
| `Option + 2` | Save screenshot to the macro folder (uses remembered region; first time asks for drag selection) |
| `Option + 3` | Set screenshot region (drag to reselect and save immediately) |
| `Cmd + Option + W` | Close all pinned screenshot windows |
| `Esc` | Cancel capture mode / hide saved-region overlay |

*Pinned screenshots have native circular buttons for Close, Copy, Save, Draw, and History, with glass styling on macOS 26 and later. Drag the image to move it when drawing mode is off.*
*Open **Settings…** from the PinShot menu to change global shortcuts or restore their defaults under **Keyboard Shortcuts**. Click the current shortcut and press the new keys. New shortcuts require Command, Control or Option; existing saved shortcuts remain unchanged.*
*Under **Features**, use **Set Region…** to reselect the saved region and save a screenshot immediately. **General** includes Launch at Login, language and appearance.*
*Use `Play Macro` / `Stop Macro` in the Opt+2 macro panel to start or stop loop playback.*

### Screenshot editor

1. Press `Option + A` or choose **Take Screenshot…** from the menu bar.
2. Drag to select an area, or click a highlighted window. Releasing the mouse locks that range for the entire capture session, including other displays. Moving, resizing, and selecting another range are disabled. The size label shows the captured region's pixels, excluding padding. To choose a different range, cancel with Esc and start a new capture.
3. Choose a tool: `V` pointer, `R` rectangle, `O` ellipse, `A` arrow, `P` pen, `T` text, or `M` mosaic. Click to enter text and press Return to finish the label. Choose a color and stroke width in the toolbar.
4. Press **Return**, `Command + C`, or double-click with the Pointer tool to copy. Use `Command + S` to save PNG to the screenshot editor folder, or click the pin button to keep it on screen.

`Command + Z` undoes an annotation; `Shift + Command + Z` redoes it. Before selecting a range, `Command + A` can select and lock the current display. After selection, arrow keys, `Command + A`, and right-click leave the range unchanged. `Esc` cancels without copying or saving. Each capture selects a region on one display. Starting the editor stops any running capture macro.

Change the global shortcut in **Settings… → Keyboard Shortcuts → Take Screenshot**. If iShot or another app owns `Option + A`, the menu and settings show **Shortcut Unavailable**; the menu action still works. Quit the conflicting app, then save the shortcut again or restart PinShot. Alternatively, choose a different shortcut. Existing `Option + 1/2/3` shortcuts keep their current behavior and settings.

### Save folders and history

**Settings… → Features → Save Locations** provides independent folder pickers for:

| Capture type | Default folder |
| --- | --- |
| Screenshot Editor (`Option + A`) | `~/Pictures/PinShotCaptures/Screenshots` |
| Capture & Pin (`Option + 1`) | `~/Pictures/PinShotCaptures/Pins` |
| Saved-region and macro captures (`Option + 2/3`) | `~/Pictures/PinShotCaptures/Macro` |

Changing folders affects new saves. Existing files are not moved. The screenshot editor's frame settings also appear under **Settings… → Features → Screenshot Frame**. Padding and rounded corners have separate enable switches; the four padding edges and four corner radii are independent. Frame changes are saved immediately and restored for every new capture, including after restarting PinShot. Padding is hidden in the selection overlay but remains visible in the Frame preview and final image. Values use output pixels, so Retina screenshots retain their original image resolution. Enter commits a frame input; Escape closes the frame panel while preserving the selection.

Pin history is enabled by default. Under **Settings… → Features**, turn **Save Capture & Pin history automatically** off to stop automatically saving new pins. Existing history remains available through **Screenshot History…** in the menu, the clock button on a pin, or **Open History…** in Settings. History appears below the menu bar on the current display, with the newest screenshots first in a horizontal strip. Browse with the trackpad, mouse wheel, or navigation buttons; click a thumbnail to reopen it as a pin. The left/right arrow keys select a capture, Return opens it, and **Show in Finder** reveals the selected file. Press Escape, click outside, or start a capture to dismiss history. PNGs live in the chosen pin folder; the history index lives in `~/Library/Application Support/PinShot/History`. Keep the saved files at their original locations to continue opening them from history.

**History Limit** defaults to **30 captures**. Choose **10, 30, 50, 100**, or **Never Delete** in **Settings… → Features**. After each new capture is saved successfully, excess history entries and their original PNG files are deleted oldest first (FIFO). A lower limit takes effect on the next saved capture; changing the setting or turning history off does not immediately remove existing captures. Manually saved copies are kept. If cleanup fails, PinShot reports the error and retries the remaining old entries after the next capture.

Use **Clear History…** beside **Open History…** to permanently remove all history and its automatically saved PNG files, including files in previous save folders. A confirmation appears before deletion. Manually saved copies and open pins are kept. The history window refreshes immediately; any files that could not be deleted stay indexed so you can retry. Clearing also works when automatic history saving is turned off.

Use **Done**, Escape, or close the pin to finish drawing and update its saved history image. `Command + Z` and `Shift + Command + Z` undo and redo while drawing. Copy and Save include the current drawing and exclude the controls. Save uses the pin folder for Capture & Pin, or the screenshot folder for pins created by the screenshot editor.

## 🚀 Installation & Build

PinShot is built with Swift Package Manager and packaged as an app by `Makefile`. No Xcode project setup is required.

### Install via Homebrew

```bash
brew tap elixirevo/tap
brew install --cask pinshot
```

If you already tapped `elixirevo/tap`, this also works:

```bash
brew install --cask pinshot
```

### Prerequisites

* macOS 13.0 or later
* Xcode 26 or later with Icon Composer (required to compile `pinshot.icon`)
* The MacAppEssentials checkout at `../tools/library`, or set `MAC_APP_ESSENTIALS_PATH` to its location. The package and its `Integrations/MacAppUpdatesSparkle` subpackage must stay together.
* Internet access for the first build to resolve the pinned Sparkle 2.10.0 package. SwiftPM verifies and caches its binary artifact.

### Build Steps

1. Clone the repository:

   ```bash
   git clone https://github.com/elixirevo/pinshot.git
   cd pinshot
   ```

2. Build the app using `make`:

   ```bash
   make
   ```

   The build compiles `pinshot.icon` into `Assets.car` and `pinshot.icns`,
   and refreshes the 1024×1024 `icon.png` from the same design. To regenerate
   only the icons, run `make icons`. If Command Line Tools is selected, the
   icon script uses `/Applications/Xcode.app` automatically; for a different
   Xcode installation, set `DEVELOPER_DIR` to its `Contents/Developer` directory.
   Swift compilation also uses this Xcode toolchain, including its Intel compatibility libraries.

   Release build with version metadata:

   ```bash
   make release VERSION=1.3.0 BUILD=1301 ARCH=arm64
   ```

   Build a universal app (`arm64 + x86_64`) and apply ad-hoc signing:

   ```bash
   make sign-adhoc VERSION=1.2.0 BUILD=1201
   ```

   Build a distributable universal DMG (includes app, Applications link, and drag-to-install arrow layout):

   ```bash
   make dmg-universal VERSION=1.2.0 BUILD=1201
   ```

3. The built application will be located at `build/PinShot.app`.
4. Move it to your Applications folder:

   ```bash
   mv build/PinShot.app /Applications/
   ```

### Verification

Run `make test` for crop coordinates, 1×/2× resolution, annotations and pin drawing, asymmetric padding and transparent corners, separate save destinations, history persistence and opt-out, FIFO retention at every limit, unlimited retention, folder changes, save/cleanup failure recovery, corrupt-index protection, history shelf placement, scrolling, live updates, and keyboard navigation, plus independent frame corners, legacy settings migration, capture-level color input handling, fixed capture ranges, hidden selection padding, and remembered frame values across captures. `make preview-screenshot-editor` opens the real editor with a generated test image, so its UI can be checked without Screen Recording permission. Preview exports go to `.build/editor-preview.png`. `make preview-pins` shows the pin controls and horizontal history shelf with temporary sample captures.

### Distribution and updates

Official releases provide separate Apple Silicon (`arm64`) and Intel (`x86_64`) DMGs. See [the release guide](docs/releasing.md) for Developer ID signing, notarization, Sparkle feed generation, and GitHub/Homebrew publishing.

**1.1.2 and earlier do not include Sparkle.** Install 1.2.0 once through the DMG or run `brew update` and `brew upgrade --cask --greedy pinshot`; subsequent releases can update inside the app. Sparkle checks daily by default and can install downloaded updates when the app quits. Automatic downloads can be changed in Sparkle's update dialog.

## 🔒 Permissions

The first-run guide and **Settings… → Permissions** share the same permission controls. They read status without prompting. Permission requests only happen after you choose the request button and confirm the guidance:

1. **Screen Recording:** Required to capture the screen and window contents.
2. **Accessibility:** Used for macro keyboard actions and dismissing overlays with Escape while another app is active.

Open **Settings… → Permissions** to see each status. **Request Access…** opens shared guidance before the native request; **Open System Settings…** remains available for denied permissions. Returning to the app or using **Refresh Status** reads status again. Screen Recording is required for capture; Accessibility is optional for keyboard macros and global Escape. If macOS requires restarting PinShot, quit and reopen it.


`make preview-settings` opens this UI with simulated permissions, so it can be checked without granting or changing real macOS permissions.

*Note: Screenshot capture and editing work offline. Update checks connect to GitHub to retrieve release information and packages; screenshots are never uploaded. Sparkle system profiling is disabled by default.*

## First run, settings and legal documents

PinShot uses MacAppEssentials for its settings window, status menu, standard app menu, language, login items, permission guidance, lifecycle and Sparkle adapter. It remains a menu-bar app when settings or onboarding is open. Reopening PinShot from Finder opens the unfinished setup or settings.

The first run shows capture and pin guides with screenshots taken from PinShot's actual UI, a privacy explanation, versioned Terms of Use and individual permission pages. Terms acceptance is explicit and stored separately from onboarding completion. Capture shortcuts and updates start only after acceptance and finishing or dismissing the remaining setup. A changed Terms version uses a separate agreement window. Closing before agreement exits without accepting. Permissions are not required to finish onboarding.

**Settings → Help & Support** provides **Show Introduction…**, read-only Korean/English Terms and Privacy Policy, help, private email support and GitHub issues. Documents are bundled for offline reading; reading or copying them does not record agreement. Common settings and onboarding use the same System/English/Korean language preference, applied after relaunch. The capture editor retains its app-specific controls.

**General → Restore Defaults** offers scoped capture-preference and shortcut resets with confirmation. Resetting preferences does not delete images, change OS permissions or erase agreement/onboarding records. The restored history limit applies after the next saved capture.

See [the integration notes](docs/mac-app-essentials.md) for module ownership, build/resource details, verification and legal sources. `make preview-onboarding` uses simulated permissions and temporary agreement records.

## 🛠 Contributing

Contributions are welcome! If you have ideas for new features, bug fixes, or improvements, feel free to open an issue or submit a pull request.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.

### Optional crash reports

**Settings → General → Diagnostics → Send crash reports** enables optional Sentry crash reporting after restarting PinShot. It is off by default and also available during onboarding. It sends technical fatal-exception details to help diagnose crashes; screenshots are not attached. Changes, including turning reporting off, apply on the next launch. Read **Help & Support → Privacy Policy** for data, cache, retention and international-processing details.

Developers: the app uses the shared `MacAppDiagnosticsSentry` adapter and its public bundled configuration. Release symbols are saved beside the app as `PinShot.app.dSYM`; upload each build with `python3 scripts/upload_sentry_symbols.py build/PinShot.app.dSYM`. See [integration notes](docs/mac-app-essentials.md#sentry).
