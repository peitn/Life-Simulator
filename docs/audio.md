# Audio

Music design v3 (2026-10-22, scheduled run 17). Ambience, tension layer and argument voices come from design v2
(written the same day from the main chat).

All sound is rendered offline by the project's own synthesizer (`scripts/audio/synth.gd`) into 16-bit WAV
(`tools/build_audio.gd`) and loaded at runtime by `WavLoader`. Nothing is downloaded; everything is deterministic
(fixed seeds).

## Music (`scripts/audio/music_data.gd`, `DESIGN_VERSION = 3`)

History: v1 was the original soundtrack (run 2). v2 rewrote all five tracks darker (felt piano, cello, tape
texture). The owner preferred v1 and named the v1 night track as the reference for the game's tone. v3 therefore
restores the v1 tracks and their renderer unchanged and replaces only the morning track, which the owner did not
like, with a new one written in the spirit of the night track.

| id | title | key | tempo | character |
|---|---|---|---|---|
| `rano` | Mlhavé ráno (new in v3) | F Lydian / D minor: Fmaj7 – Am7 – Dm7 – Cadd9 – Fmaj7 – Em7 – Dm7 – Gsus4 | 70 | like the night track (sparse bell melody, long bass, no drums, lots of reverb) with a brighter pad and a slow e-piano arpeggio; the loop ends on an unresolved sus chord |
| `den` | Odpoledne na dvorku | G major | 104 | v1 (flute, plucked arpeggio, light drums); only the title changed |
| `vecer` | Večer u gauče | B♭ major, jazz | 84 | v1 (e-piano comping, walking bass, brushes) |
| `noc` | Noční ticho | A minor | 66 | v1, **tone reference** (`TONE_REFERENCE`): bell melody, dark pad, long bass, no drums |
| `melancholie` | Když se nedaří | E minor | 70 | v1 (e-piano, dark pad, slow arpeggio) |

The v2 instruments (`felt`, `cello`, `drone`, `pluck_muted`), tape effects (`wow`, `texture`) and `duck_range` stay
in `synth.gd` for sound recipes; no music track uses them. The v2 track data is archived outside the repository
(`previews/archive/music_data_v2.gd`).

Brightness check (zero crossings per second of the rendered files): night 590, morning 597, day 717. The morning
track sits right next to the night track and well below the day track.

## Apartment ambience (`AudioManager.ambience_weights`)

| layer | when |
|---|---|
| `amb_fridge` | always (the flat is never silent), slightly louder at night |
| `amb_traffic` | daytime, morning and afternoon rush; almost nothing at night |
| `amb_neighbors` | evening 18–24 h, a little after midnight: muffled talk, their bass, a thump |
| `amb_dawn`, `amb_birds` | short morning window, faint by day (max combined 0.44) |
| `amb_crickets`, `amb_wind` | night, quiet |

## Tension layer

`layer_tension` (32 s loop, atonal so it sits under any track: sub-rumble, beating inharmonic metal partials,
60 bpm muffled pulse, faint high tone) plays on the Music bus. Level = max of
- selected character's stress (`smoothstep(45, 90, stress) × 0.6`),
- a nearby argument (`conflict_env`, 1 at the argument, scaled by distance to the selected character up to 16 m,
  half-life 14 s),
- anxiety from PsycheFX (`psyche_level × 0.5`).

It rises fast (0.6/s) and fades slowly (0.12/s). Music is ducked at full tension (the test measures about −10 dB on
the Music bus including its base level).

## Arguments you can hear

`social_event(sim, positive=false, …)` (argument or insult; emitted for both participants) triggers:
- a raised **voice** at the character's head as `AudioStreamPlayer3D` – formant synthesis of Czech vowels and noise
  consonants, unintelligible by design (no words); 4 clips (`vox_argue_a/b`, `vox_argue_rough_a/b`);
- pitch from `CharacterData.voice.pitch` (−1..1 → ±~5 semitones), rough variant when `voice.roughness > 0.45`;
  **never** derived from grammatical gender or name;
- distance attenuation with a low-pass ("through the wall");
- the second participant cuts in 0.35–0.9 s later; per-character cooldown 5 s; max 3 voices at once; no voices at
  game speed ≥ 3 (tension still rises);
- 30 % chance of a **door slam** 3.5–6 s later near the argument (open: tie it to argument intensity and temperament).

Purely cosmetic and local to each peer: no effect on simulation or network.

## Tests

`tests/test_audio_tone.tscn` – 222 checks: song data (all five tracks, known instruments, ranges, no v2
instruments in music, the night track unchanged, the morning track in the night track's spirit: slow, no drums, no
flute or bright arpeggios, same melody instrument, sparse melody, at least three minor chords, unresolved ending),
brightness of the rendered morning track between night and day, v2 instruments (finite, deterministic), loop seams
(seam jump compared with the file's own 99th percentile of sample-to-sample differences, minimum tolerance 0.035),
rendered files (no clipping, not silent, loop flags), ambience by hour, argument voices (pitch from voice data,
rough variant, cooldown, limit, fast time, cleanup), tension rise/duck/fade, door slam with freed parent.

## Rebuilding

`godot --headless -s res://tools/build_audio.gd -- [id ...]` (no ids = everything). Music takes about 40 s.
