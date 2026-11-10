# M2 independent review — 29 October 2026
Two actual Gemini code reviews received full current changed sources and actual execution results. Gemini did not run tests or view screenshots.

## Disposition
- Initial platform-ID leak allegation withdrawn after source analysis and actual freed-runner/new-runner/destruction tests. Live users remain authoritative; IDs absent from that list are pruned.
- Speculative Windows delayed-close claim withdrawn. Tested on Linux; errors preserve the primary and are reported. No arbitrary delay or Windows certification.
- Numeric-vector allegation disproved by existing short-circuit type guard and actual string/null rejection tests. Boolean schema-version rejection was added.
- Text-focus handling strengthened: names commit on focus loss and before navigation/save; text-field shortcuts retain native undo handling. Actual focus/dirty-open tests pass.
- Follow-up undo allegation rejected: Ctrl+Z Undo, Ctrl+Shift+Z and Ctrl+Y Redo are the standard mapping already implemented. No alternate nonstandard backward mapping was introduced.
- File picker strengthened with an explicit selected-index guard and a captured target path. Refresh explicitly selects a file; actual Open button, discard confirmation and selected=-1 tests pass. This does not establish Gemini's asserted default OptionButton behavior.
- Independently discovered triplanar/glTF mismatch corrected: mapped custom primitives use metric baked UVs in preview and export, with inverse-scaled normals and regenerated tangents. A rotated elliptical cylinder GLB roundtrip retains dimensions and albedo/normal/roughness maps.

Initial test harness errors (reusing leave_world-disconnected clock callbacks; testing seat1 after releasing seat0; too-large minimum size for tiny fixture details) were corrected rather than weakening asset acceptance. The negative TV injector was moved before tree entry so it changes only slot behavior: exactly two expected failures now, rather than eleven unrelated identity/layout failures. First unbounded failed editor test was identified by exact PID/cmdline/run ID and terminated; all final child runs have timeouts.

No evidence-backed remaining blocker in the accepted city scope. This is our disposition, not a claim that Gemini certified the game. Known M6/M7 integration and visual/performance limits are in M2_ACCEPTANCE_20261029.md.

## First response (verbatim)

Based on a code audit of your scoped Godot 4.7.2 M2 fixtures, builder, document, editor, and catalog showcase scripts, here are concrete reproducible bugs found across lifecycle management, file I/O safety, schema checks, and UI data integrity.

---

### 1. Concurrency / Lifecycle Bug: Dangling `_on_platform` Entries on Unsafe Egress
* **Priority:** **HIGH**
* **Methods:** `M2Fixture.release()` / `M2Fixture._prune()`
* **Bug Description:** 
  In `m2_fixture.gd`, the `release(sim)` method cleans up tracking for `_on_platform` using `sim.get_instance_id()`. However, if an agent is forcefully removed, freed by the engine, or disconnected via `SmartObject` base mechanisms *without* calling `release()` explicitly (such as abrupt node queue freeing or system resets), `_prune()` attempts to clear stale keys:
  ```gdscript
  func _prune() -> void:
      super._prune()
      var ids:Array=[]
      for user in users:ids.append(user.get_instance_id())
      for id in _on_platform.keys():
          if id not in ids:_on_platform.erase(id)
  ```
  `_prune()` relies on `users` array to match IDs. If `users` is updated *before* `_prune()` runs or if a user is orphaned during state transitions, `_on_platform` can retain stale integer keys pointing to freed instances. When a *new* SimAgent is allocated the same instance ID slot by the engine, it inherits unintended platform adjustments (`sim.global_position = get_use_position(sim)`).
* **Smallest Fix:**
  In `_prune()`, also validate instance validity directly rather than strictly relying on the `users` array:
  ```gdscript
  func _prune() -> void:
      super._prune()
      for id in _on_platform.keys():
          var obj = instance_from_id(id)
          if obj == null or not users.has(obj):
              _on_platform.erase(id)
  ```

---

### 2. File I/O Bug: Atomic Rename Failure on Windows (`FileAccess` Locking)
* **Priority:** **MEDIUM**
* **Methods:** `FurnitureDocument.save()`
* **Bug Description:** 
  In `furniture_document.gd`, saving writes to a temporary file (`path + ".tmp"`), closes it, attempts to rotate backups, and then performs a final rename:
  ```gdscript
  var f:=FileAccess.open(tmp,FileAccess.WRITE)
  ...
  f.close()
  ...
  return DirAccess.rename_absolute(tmp, path)
  ```
  On Windows operating systems, Godot's underlying file descriptors or OS file locking can sometimes hold a brief exclusive lock immediately after `FileAccess.close()`, causing `DirAccess.rename_absolute` to throw an error (`ERR_CANT_CREATE` or `ERR_BUSY`) when replacing an existing destination file.
* **Smallest Fix:**
  Add a short retry loop for the destination replacement step:
  ```gdscript
  var err := DirAccess.rename_absolute(tmp, path)
  if err != OK:
      OS.delay_msec(10)
      err = DirAccess.rename_absolute(tmp, path)
  return err
  ```

---

### 3. Schema Validation Bug: Unsanitized JSON Data Types Causing Type Cast Crashes
* **Priority:** **MEDIUM**
* **Methods:** `FurnitureDocument.validate()`
* **Bug Description:** 
  The schema validation verifies basic sizes, arrays, and bounds, but relies on loose lookups when assessing array elements. If an attacker or corrupted JSON file supplies a dictionary where vector values are strings or nulls instead of numbers (e.g., `[".5", null, "bad"]`), `finite_vector` checks `v < low` which can cause Godot to throw a runtime script error: *Invalid operands '<' for comparison between 'String' and 'float'* instead of returning a clean validation string.
* **Smallest Fix:**
  Strictly check element types inside `finite_vector`:
  ```gdscript
  static func finite_vector(a:Variant,low:float,high:float) -> bool:
      if not a is Array or a.size()!=3:return false
      for v in a:
          if not (v is float or v is int):return false
          var f := float(v)
          if not is_finite(f) or f<low or f>high:return false
      return true
  ```

---

### 4. UI Accidental Data Loss Bug: Unhandled Input Intercepts LineEdit Focus
* **Priority:** **LOW**
* **Methods:** `FurnitureEditor._unhandled_key_input()`
* **Bug Description:** 
  In `furniture_editor.gd`, shortcut keys like `KEY_S`, `KEY_Z`, and `KEY_D` are intercepted globally via `_unhandled_key_input`:
  ```gdscript
  func _unhandled_key_input(event:InputEvent) -> void:
      if not event is InputEventKey or not event.pressed or event.echo:return
      if event.ctrl_pressed or event.meta_pressed:
          match event.keycode:
              KEY_S:save_draft()
              KEY_Z:redo() if event.shift_pressed else undo()
              ...
  ```
  Because this runs in `_unhandled_key_input`, if a user is actively typing a custom part name or title into a `LineEdit` and presses `Ctrl+D` (intending to type a capital letter or use standard text controls), the editor intercepts it globally and triggers `duplicate_part()` instead of allowing text box handling.
* **Smallest Fix:**
  Guard the shortcut evaluation by checking if the currently focused control is a text input field:
  ```gdscript
  if get_viewport().gui_get_focus_owner() is TextEdit or get_viewport().gui_get_focus_owner() is LineEdit:
      return
  ```

## Follow-up response (verbatim)

### Audit Retractions & Evidence-Backed Confirmations

1. **Claim (1) Retracted / Clarified:** Initial assertions regarding potential platform ID reuse bugs are **withdrawn**. The added lifecycle tests (`catalogue90`, base489 base cleanup) and `_prune()` logic correctly ensure that instance IDs not present in live users are expunged *after* `super._prune()`. The recovery behavior on destruction of occupied platforms correctly repositions surviving actors.
2. **Claim (2) Retracted:** Speculative concerns regarding Windows delayed-close file locking are **retracted**. Target execution platforms are Linux-based, and atomic file replacement logic utilizing `.tmp` and `.bak` suffixes without arbitrary sleeps functions safely.
3. **Claim (3) Confirmed Safe:** The short-circuit evaluation order inside `finite_vector()` successfully validates type membership (`is float or is int`) before performing inequality checks (`v < low`), protecting against invalid types (`String`, `null`) crashing evaluation. Strict type guards for version checks are fully in place.
4. **Claim (4) Confirmed Fixed:** Focus handling guards for `LineEdit` nodes during hotkey processing have been correctly integrated (allowing explicit `Ctrl+S` passthrough while suppressing accidental command triggers during text editing). The newly introduced focus loss/navigation commit mechanisms (`flush_names`) completely resolve data loss vectors during title/part renaming.

---

### Remaining Evidence-Backed Scoped Blockers

While the local logic and regression tests for furniture document serialization, UV baking, and editor states pass clean checks, **one critical defect** remains within the provided script base:

#### 1. Logic Defect in Undo / Redo Key Binding (`furniture_editor.gd`)
* **Location:** `furniture_editor.gd` lines 415–424 (`_unhandled_key_input`)
* **Evidence:** 
  ```gdscript
  KEY_Z:redo() if event.shift_pressed else undo()
  KEY_Y:redo()
  ```
  Standard desktop convention binds `Ctrl+Z` to **Undo** and `Ctrl+Shift+Z` (or `Ctrl+Y`) to **Redo**. In the current implementation:
  * Pressing `Ctrl+Z` (without Shift) invokes `redo() if event.shift_pressed else undo()` — which correctly triggers `undo()`.
  * However, pressing `Ctrl+Shift+Z` triggers `redo()`, which duplicates the mapping of `KEY_Y`, but more importantly, **`undo()` has no corresponding Shift modifier variant** to step backward through history via alternative standard shortcuts (like `Ctrl+Y` or `Ctrl+Shift+Y`), leading to asymmetric history navigation bindings compared to standard UI expectations.
* **Impact:** Minor UX divergence / non-standard modifier mapping for history traversal.

#### 2. Potential Index Out-of-Bounds in `request_open()` (`furniture_editor.gd`)
* **Location:** `furniture_editor.gd` lines 395–397 (`request_open`)
* **Evidence:**
  ```gdscript
  func request_open() -> void:
      if files.item_count>0:guard(func():open_draft(Doc.DIRECTORY+files.get_item_text(files.selected)))
  ```
  When `files` (`OptionButton`) is freshly populated via `refresh_files()`, `files.selected` defaults to `-1` if no item is explicitly selected, even when `files.item_count > 0`. Accessing `files.get_item_text(files.selected)` with an index of `-1` will trigger an out-of-bounds error in Godot.
* **Impact:** Potential runtime crash when clicking "Otevřít" (Open) if the dropdown hasn't registered an active selection index.

---

### Recommended Remediation

1. **Fix `request_open()` Selection Guard:**
   ```gdscript
   func request_open() -> void:
       if files.item_count > 0 and files.selected >= 0:
           guard(func(): open_draft(Doc.DIRECTORY + files.get_item_text(files.selected)))
   ```
2. **Verify M6/M7 Boundary:** As per instructions, integration tests for whole-game, Windows-specific environments, and navigation/client meshes remain correctly deferred.
