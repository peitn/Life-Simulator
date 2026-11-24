extends SceneTree
## Jednorázová úprava dokumentace po běhu main-claude-20261121b-rivalry (idempotentní: nic nepřidá dvakrát).

func _ins_after(path: String, anchor_prefix: String, text: String) -> bool:
	var s := FileAccess.get_file_as_string(path)
	if s.contains(text.left(60)):
		return true
	var lines := s.split("\n")
	for i in lines.size():
		if lines[i].begins_with(anchor_prefix):
			lines.insert(i + 1, text)
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string("\n".join(lines))
			f.close()
			return true
	return false


func _ins_before(path: String, anchor_prefix: String, text: String) -> bool:
	var s := FileAccess.get_file_as_string(path)
	if s.contains(text.left(60)):
		return true
	var lines := s.split("\n")
	for i in lines.size():
		if lines[i].begins_with(anchor_prefix):
			lines.insert(i, text)
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string("\n".join(lines))
			f.close()
			return true
	return false


func _replace(path: String, a: String, b: String) -> int:
	var s := FileAccess.get_file_as_string(path)
	var c := s.count(a)
	if c == 1:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(s.replace(a, b))
		f.close()
	return c


func _init() -> void:
	print(_ins_before("res://README.md", "- **21 Nov 2026:** betrayal aftermath", "- **21 Nov 2026 (evening):** rivalry, slander and manipulation defense (`scripts/sim/rivalry.gd`, `tests/test_rivalry.tscn` 152/152): directed rivalries (love / status) from competing for the same person, fights, a revealed lover and exposed slander; \"Slander a rival\" (the server picks the rival, the listener may see through it and tell the victim) and \"Bury the hatchet\"; manipulation now meets the target's defense (healthy self-worth, support, recognising the pattern). Never rewarded, private to the owner, saved with the household."))
	print(_ins_after("res://docs/testing.md", "| `test_betrayal_privacy_enet`", "| `test_rivalry` | Rivalry: composition/decay/rewind, sources, slander gates, listener defense, hatchet, limits, strict snapshot (18 malformed variants), 300-case save fuzz, GossipNetwork.slander (truth first, fabrication, content gating, doubt, report), real household: player slander (seen through → reported → payback rivalry), credulous listener, server rejections, AI scores, hatchet, manipulation defense, betrayal → rival, disk save/load, performance | 152/152 (exit 0, ~17 s) |"))
	var rel := FileAccess.get_file_as_string("res://docs/relationships.md")
	if not rel.contains("## Rivalry, slander and manipulation defense"):
		rel += "\n\n## Rivalry, slander and manipulation defense (21 November 2026)\n\n" \
		+ "`scripts/sim/rivalry.gd` (inside `HouseholdDynamics`, authority only, saved as `dynamics.rivalry`).\n\n" \
		+ "- **Directed rivalry** `A>B`: A sees B as a rival; B may not know. Two arenas with their own decay: *love* (τ 14 days) and *status* (τ 21 days); `heat = 1 − (1 − love)(1 − status)`. Respect (after reconciliation) dampens new gains by up to 60 %. Rewinding time never strengthens or erases values.\n" \
		+ "- **Sources:** a once-a-day scan – A is interested in C (relationship ≥ 45 or an infidelity spark ≥ 0.3, A attracted to C, both adults, A not aromantic) while C dates B → A rivals B; arguments while the relationship is below 10; the betrayed partner learns about the lover (+0.5 love); exposed slander (+0.4 status when the victim knows the originator, +0.15 toward someone who only passed it on).\n" \
		+ "- **Slander as a weapon** (`slander_rival`): the target is the *listener*; the server picks the rival (strongest rival other than the listener), so a client cannot choose a victim. The rumour goes through `GossipNetwork.slander`: known negative rumours first (true ones preferred – they cannot be debunked), otherwise a fabrication with the slanderer as origin (\"talks behind your back\" if the listener likes the victim, else \"takes other people's things\"). Content settings still apply. The listener's reaction uses `RivalryPressure.resolve_pressure`: boundaries = listener honesty, support = listener's relationship with the victim, evidence = trust in the victim. Outcomes: *swayed* (stronger hit, still within the gossip per-pair daily cap), *doubted*, *saw through* (belief damped ×0.3, the listener thinks worse of the slanderer and may tell the victim → the victim can confront, rivalry comes back). Gates: 2 h between slanders by the same author, once a day per listener and rival. Slander is never rewarded (no \"good gossip\" mood); an honest slanderer feels guilt.\n" \
		+ "- **Bury the hatchet** (`bury_hatchet`): accepted → both directions drop to 35 % and respect grows; refused → 2 days of distance. Another player's character never answers through AI (rejected by the server).\n" \
		+ "- **Manipulation with defense** (`social_pressure.gd`): healthy self-worth (1 − the private self-defectiveness value, read only), the strongest supportive relationship and recognising the pattern (grudge toward the manipulator) reduce guilt, shame, fear and uncertainty (never below 25 % of the hit). Relationship and trust damage are always full; manipulation never creates consent. Resisting gives the target a small \"didn't let myself be manipulated\" mood and the manipulator \"it didn't work\".\n" \
		+ "- **AI:** only low-honesty characters (HEXACO honesty < 0.5) with a strong rival consider slander (at most once a day), preferring listeners who like the rival; forgiving, honest characters consider reconciliation. Ordinary contact with a rival is reduced (×0.4–1).\n" \
		+ "- **Privacy:** rivalry data never leaves the authority; the owner sees only lines such as \"Rival: Eliška (status)\". Known limitation: a slander listener may be another player's character – their character's beliefs change through the same model as ordinary gossip (a memory entry records who said what).\n" \
		+ "- **Save format:** version 1 with a strict `validate_snapshot` (exact keys, ranges, limits) and a tolerant `from_dict` (bad entries dropped or clamped; a snapshot from a future version is discarded; older saves without the section start with no rivals).\n" \
		+ "- **Not yet:** workplace rivalry (needs careers), visible rival indicators in the 3D scene.\n"
		var f := FileAccess.open("res://docs/relationships.md", FileAccess.WRITE)
		f.store_string(rel)
		f.close()
	print(_replace("res://docs/roadmap.md", "- ⬜ Rivalry, manipulation, gossip, infidelity, break-ups;", "- 🟨 Rivalry (love/status), slander as a weapon, manipulation with defense ✅ (21 Nov); still open: workplace rivalry (needs careers). Gossip, infidelity, break-ups;"))
	print(_ins_after("res://docs/roadmap.md", "- 21 Nov 2026 (morning): **(c) betrayal aftermath**", "- 21 Nov 2026 (evening): **(c) rivalry and manipulation** ✅ – `Rivalry`: directed love/status rivalries from real sources, server-picked slander through the gossip network with listener defense, exposure and payback, \"bury the hatchet\", manipulation defense in `SocialPressure`, save v1 (strict + tolerant), server validation, HUD lines. `test_rivalry` 152/152. Next: (b) B2 build mode and Blender catalogue assets."))
	print(_replace("res://ROADMAP.md", "- ⬜ Rivalry, manipulation, gossip, infidelity, breakups;", "- 🟨 Rivalita (láska/postavení), pomluva jako zbraň, manipulace s obranou ✅ (21. 11. večer); zbývá rivalita v práci (čeká na kariéry). Gossip, infidelity, breakups;"))
	print(_ins_after("res://ROADMAP.md", "- 21. 11. 2026 ráno (main-claude-20261121a-wound)", "- 21. 11. 2026 večer (main-claude-20261121b-rivalry): (c) **rivalita a manipulace** ✅ – Rivalry: směrovaná rivalita (láska/postavení) ze skutečných zdrojů, pomluva soka (soka vybírá server; drb přes GossipNetwork – pravda má přednost, jinak výmysl), obrana posluchače (prokouknutí → donesení oběti → rivalita oplátkou), „zakopat válečnou sekeru“, obrana proti manipulaci v SocialPressure, save v1 (striktní + tolerantní), validace na serveru, HUD. test_rivalry 152/152. Další: (b) B2 režim stavění + Blender assety katalogu; rivalita v práci až s kariérami."))
	quit()
