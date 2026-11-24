# Careers and workplace rivalry (K1, 24 November 2026)

Work is where adults spend most of their waking hours, and it is a source of money, pride, pressure and
dirty politics. K1 adds legal careers to the household simulation. Illegal careers, living costs and the
wider economy (debt, rent) are planned as separate steps.

Code: `scripts/sim/career.gd` (pure data and rules, lives in `HouseholdDynamics.career`, saved with the
household), `scripts/sim/career_hooks.gd` (applies outcomes to characters, the lot budget and the network).
Test: `tests/test_career.tscn` (146 checks).

## Tracks, levels and schedule

| Track | Starts | Workdays | Notes |
|---|---|---|---|
| Retail (`retail`) | 08:00 | Mon–Fri | boss rarely understanding |
| Office (`office`) | 09:00 | Mon–Fri | |
| Care (`care`) | 07:00 | Mon, Tue, Thu, Sat, Sun | heavier load, most understanding boss |
| Kitchen (`kitchen`) | 11:00 | Tue–Sat | high stress, least understanding boss |
| Warehouse (`warehouse`) | 06:00 | Mon–Fri | |

Each track has five levels with a title in three grammatical forms (masculine, feminine, neutral
paraphrase). The form follows the character's chosen grammatical gender, never the body. Wages rise with
the level (850–2,200 kr per 8-hour shift) and are paid into the household budget (`LotGrid.funds`, ledger
kind `wage`). A character starts in the track that matches `CharacterData.story.past_work`; characters
without a matching past job start unemployed. Characters under 18 never get a career.

## The shift happens off the lot

A shift is one of four actions: `work_shift` (normal), `work_hard`, `work_slack` and `work_scheme`. They are
`player_only`, so the utility planner never picks them; the AI is sent by `Career.ai_choice` instead (see
below). The character walks to the end of the sidewalk (`main.work_exit()`, a non-buildable corridor), and
then leaves the lot: the node is hidden and parked far below the world, so every distance-based system
(friction, witnesses, rival proximity, crowding) ignores it, and lock / wall checks explicitly skip it.
The public state is only the label "V práci" and posture `away` (client puppets hide). After the shift the
character comes back via the sidewalk. Locked doors or walls that make the sidewalk unreachable mean the
character cannot leave for work.

There is an arrival window: from one hour before the start until two hours after it (late from +30 min).
The shift start tolerates 20 extra minutes for the walk, and absence is checked only after that. A sleeping
character with a shift coming up wakes up (an alarm clock), unless they have already decided not to go.

## Performance, boss and burnout

`resolve_shift` computes:

* **Performance** (0–100): mode (hard > normal > slack) × **capacity**. Capacity (0.25–1) drops with
  depression, stress above 45, low energy and accumulated strain. It is what the character can do today,
  not a punishment.
* **Boss opinion** (−100..100): mode, lateness, leaving early, being caught slacking.
* **Strain** (burnout, 0–1): rises with hard work, falls on days off. High strain adds stress and moodlets.
* **A workplace event** (40 %): praise, a colleague stealing credit, being blamed, the boss yelling, a
  colleague asking how you are (more likely when the character is visibly struggling), small talk, a near
  breakdown when burnt out.
* **Leaving early**: a panic attack at work sends the character home. An understanding boss (care) barely
  holds it against them; a less understanding one treats it as failure — the character feels the stigma.
  Other early departures cost more.

## Attendance, sick days, firing, job search

* A workday without a shift and without a sick call is an **absence**: a warning and a worse boss opinion.
  The day of hiring never counts.
* **Calling in sick** is allowed until the arrival window closes. Two excused days per 14; more are allowed
  but annoy the boss. When the reason is the character's mental health (only with mental-health content
  enabled), the boss reacts by track: understanding or stigma. The reason itself is never stored.
* **Three warnings** (or very poor performance with a boss who hates you) mean the character is **fired**.
  Ten clean shifts erase one warning.
* **Job search** (`job_search`, every 4 game hours at most): the chance drops after a fresh firing and a
  little with depression. A hired character starts at level 0 after being fired, otherwise one level lower
  than before.
* **Quitting** (`quit_job`) is allowed at any time; quitting while burnt out brings relief.

## Promotion as a contest, and scheming

Good performance and enough shifts at the current level open a **promotion contest** (5 game days) with a
colleague at the same level: a real character of the same track (another player or AI) if there is one,
otherwise the most ambitious NPC colleague (NPC colleagues are names with ambition and honesty, not world
characters). Each shift adds points; at the deadline the score (points + performance + boss) decides. The
winner is promoted. Losing to a real character feeds a **status rivalry** (`Rivalry`), losing to an NPC
makes that colleague a source of resentment.

During a contest the character can **scheme** (`work_scheme`): steal credit, put obstacles in the rival's
way. It may work (the rival loses contest points and a little performance — at most once per victim per
day), or the character gets caught (warning, the boss is furious) and the rival learns who it was. Even a
successful scheme may be discovered later. A rival who learns about it gets a status rivalry and a worse
opinion of the schemer. Honest characters feel guilty about scheming. The game never rewards scheming for
sure.

## AI

Once per game day (cached in the record, so the character's RNG is drawn once) an AI character in the
arrival window decides: heavy depression, a recent panic attack, exhaustion or extreme stress → call in sick
(while excused days remain). A high initiation barrier from depression also leads to a sick call while
excused days remain; only when they are used up may the character fail to get up or call — and the absence
has real consequences. Dishonest characters in a promotion contest scheme, lazy or exhausted ones slack,
rested ones sometimes work hard, otherwise they work normally. Unemployed characters look for work once a
day.

## Multiplayer and privacy

All career data is server-side and private. Career commands are validated by the server
(`main.career_command_block`): schedule window, employment, sick/worked today, a contest for scheming,
unemployment and cooldown for job search. Players can only command their own character (existing ownership
and rate limits). Clients see only "V práci"; the owner's private HUD lines (offline/host) show the job,
performance and boss in words (no numbers), warnings, a running contest and burnout. Harm to another
player's character via scheming is capped to once per victim per day and is only possible within a promotion
contest between characters of the same track and level.

## Saving

`dynamics.career` (version 1). `Career.validate_snapshot` is strict (exact keys, types, ranges, limits,
contest ↔ record cross-references); `from_dict` is tolerant (invalid records are sanitized, contests without
valid participants dropped; a future version is dropped as a whole). A character saved during a shift stays
at work after loading and returns via the sidewalk.

## Defaults

Careers are on in the windowed game and on a dedicated server (`mode == "server"`). Isolated headless tests
keep their calibrated baseline unless they opt in with `cfg["careers"] = true`.

## Known limitations

* No living costs yet: wages only increase the household budget (planned with the economy step).
* Workplaces are abstract (no 3D workplace scene); NPC colleagues exist only inside the career module.
* Private career lines are visible offline and to the host, not yet to remote clients (same as rivalry).
* Illegal careers are planned as a separate step (K2).
