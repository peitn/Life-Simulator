extends RefCounted
## Hudba Life Simulator – skladby jako data (akordy z Audio Engine music_progression,
## melodie komponované ručně; téma „Ráno“ je i v knihovně Audio Engine jako
## Surge render: lifesim/sounds/theme_rano_surge_mix.wav).
##
## Každá skladba = 8 taktů akordů × 2 průchody. 1. průchod je „intro“ bez melodie
## (méně ohraná hudba v pozadí), 2. průchod přidá melodii a rytmiku.

const Synth := preload("res://scripts/audio/synth.gd")

const SONGS := {
	"rano": {
		"title": "Ráno v Lipové ulici", "tempo": 92.0, "reverb": 0.32,
		"chords": [[50, 54, 57], [57, 61, 64], [59, 62, 66], [55, 59, 62], [50, 54, 57], [54, 57, 61], [55, 59, 62], [57, 61, 64]],
		"melody_instr": "epiano", "chord_instr": "pad", "arp_instr": "pluck", "arp": "up", "drums": "shaker",
		"melody": [
			[66, 0, 1, 84], [69, 1, 1, 80], [74, 2, 1.5, 90], [73, 3.5, 0.5, 76],
			[76, 4, 1.5, 88], [73, 5.5, 0.5, 76], [69, 6, 2, 80],
			[71, 8, 1, 82], [74, 9, 1, 84], [78, 10, 1.5, 92], [76, 11.5, 0.5, 78],
			[74, 12, 1, 84], [71, 13, 1, 80], [67, 14, 2, 78],
			[69, 16, 1, 82], [66, 17, 0.5, 74], [69, 17.5, 0.5, 78], [74, 18, 2, 88],
			[73, 20, 1, 84], [69, 21, 1, 80], [66, 22, 1, 78], [64, 23, 1, 74],
			[62, 24, 0.5, 74], [64, 24.5, 0.5, 76], [67, 25, 1, 80], [71, 26, 1, 84], [74, 27, 1, 86],
			[73, 28, 1.5, 86], [76, 29.5, 0.5, 80], [69, 30, 2, 80],
		],
	},
	"den": {
		"title": "Sluníčko na zahradě", "tempo": 104.0, "reverb": 0.22,
		"chords": [[55, 59, 62], [52, 55, 59], [57, 60, 64], [50, 54, 57], [55, 59, 62], [48, 52, 55], [57, 60, 64], [50, 54, 57]],
		"melody_instr": "flute", "chord_instr": "pad", "arp_instr": "pluck", "arp": "pop", "drums": "light",
		"melody": [
			[74, 0, 1, 84], [71, 1, 0.5, 78], [67, 1.5, 0.5, 76], [69, 2, 1, 80], [71, 3, 1, 82],
			[67, 4, 1.5, 80], [64, 5.5, 0.5, 74], [71, 6, 2, 82],
			[72, 8, 1, 84], [76, 9, 1, 86], [74, 10, 0.5, 80], [72, 10.5, 0.5, 78], [69, 11, 1, 80],
			[66, 12, 1, 78], [69, 13, 1, 80], [74, 14, 1.5, 86], [72, 15.5, 0.5, 76],
			[71, 16, 1, 84], [74, 17, 1, 86], [79, 18, 1.5, 92], [78, 19.5, 0.5, 80],
			[76, 20, 1, 84], [72, 21, 1, 80], [67, 22, 2, 78],
			[69, 24, 0.5, 78], [71, 24.5, 0.5, 80], [72, 25, 1, 82], [76, 26, 1, 86], [74, 27, 1, 84],
			[78, 28, 1, 88], [76, 29, 0.5, 80], [74, 29.5, 0.5, 78], [69, 30, 2, 80],
		],
	},
	"vecer": {
		"title": "Večer u gauče", "tempo": 84.0, "reverb": 0.38,
		"chords": [[58, 62, 65, 69], [57, 60, 64, 67], [55, 58, 62, 65], [53, 57, 60, 64], [58, 62, 65, 69], [48, 52, 55, 58], [57, 60, 64, 67], [50, 53, 57, 60]],
		"melody_instr": "epiano", "chord_instr": "epiano_comp", "arp_instr": "", "arp": "", "drums": "brush_swing", "bass": "walk",
		"melody": [
			[77, 0, 1.5, 84], [76, 1.5, 0.5, 76], [74, 2, 1, 80], [72, 3, 1, 78],
			[76, 4, 2, 84], [72, 6, 1, 78], [69, 7, 1, 74],
			[70, 8, 1, 80], [74, 9, 1, 82], [77, 10, 1, 86], [76, 11, 1, 80],
			[72, 12, 3, 82],
			[74, 16, 1, 80], [77, 17, 1, 84], [81, 18, 1.5, 90], [79, 19.5, 0.5, 78],
			[76, 20, 1, 82], [79, 21, 1, 84], [82, 22, 1, 88], [79, 23, 1, 80],
			[76, 24, 1.5, 82], [74, 25.5, 0.5, 76], [72, 26, 2, 80],
			[69, 28, 1, 78], [72, 29, 1, 80], [74, 30, 2, 82],
		],
	},
	"noc": {
		"title": "Noční ticho", "tempo": 66.0, "reverb": 0.5,
		"chords": [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62], [57, 60, 64], [50, 53, 57], [53, 57, 60], [52, 55, 59]],
		"melody_instr": "bell", "chord_instr": "pad_dark", "arp_instr": "", "arp": "", "drums": "", "bass": "long",
		"melody": [
			[76, 0, 2, 70], [81, 2, 2, 74],
			[84, 4, 3, 78], [83, 7, 1, 68],
			[79, 8, 2, 72], [76, 10, 2, 68],
			[74, 12, 4, 70],
			[76, 16, 1, 68], [81, 17, 1, 72], [83, 18, 1, 74], [84, 19, 1, 76],
			[86, 20, 2, 78], [84, 22, 1, 72], [81, 23, 1, 70],
			[84, 24, 2, 74], [81, 26, 1, 70], [77, 27, 1, 68],
			[76, 28, 4, 70],
		],
	},
	"melancholie": {
		"title": "Když se nedaří", "tempo": 70.0, "reverb": 0.42,
		"chords": [[52, 55, 59], [48, 52, 55], [55, 59, 62], [50, 54, 57], [52, 55, 59], [57, 60, 64], [48, 52, 55], [47, 51, 54, 57]],
		"melody_instr": "epiano", "chord_instr": "pad_dark", "arp_instr": "epiano", "arp": "slow", "drums": "", "bass": "long",
		"melody": [
			[71, 0, 1.5, 78], [67, 1.5, 0.5, 70], [64, 2, 2, 74],
			[76, 4, 1.5, 82], [74, 5.5, 0.5, 72], [72, 6, 2, 76],
			[71, 8, 1, 76], [74, 9, 1, 78], [79, 10, 2, 84],
			[78, 12, 1.5, 80], [76, 13.5, 0.5, 72], [74, 14, 2, 76],
			[67, 16, 1, 72], [71, 17, 1, 76], [76, 18, 2, 80],
			[72, 20, 1, 76], [76, 21, 1, 80], [81, 22, 2, 86],
			[79, 24, 1, 80], [76, 25, 1, 76], [72, 26, 1, 74], [71, 27, 1, 72],
			[75, 28, 2, 78], [78, 30, 1, 76], [71, 31, 1, 72],
		],
	},
}


static func song_length(id: String) -> float:
	var s: Dictionary = SONGS[id]
	return 64.0 * 60.0 / float(s["tempo"])


static func render(id: String, sample_rate := 22050) -> Object:
	var s: Dictionary = SONGS[id]
	var beat := 60.0 / float(s["tempo"])
	var syn = Synth.new(song_length(id), sample_rate, true, hash(id))
	var chords: Array = s["chords"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + 7
	for bar in 16:
		var ch: Array = chords[bar % 8]
		var t0 := bar * 4.0 * beat
		var second := bar >= 8
		var root: int = ch[0]
		# Akordy
		match String(s["chord_instr"]):
			"pad", "pad_dark":
				for i in ch.size():
					syn.note(s["chord_instr"], ch[i], t0, 4.0 * beat, 0.55, -0.3 + 0.2 * i, 0.8)
			"epiano_comp":
				# jazzové „komping“ na 2a a 4
				for hit in [1.5, 3.5]:
					for i in ch.size():
						syn.note("epiano", ch[i], t0 + hit * beat, 0.45 * beat, 0.45 + rng.randf() * 0.1, -0.2 + 0.13 * i, 0.7)
		# Arpeggio / doprovod
		var arp: String = s["arp"]
		if arp != "":
			var instr: String = s["arp_instr"]
			match arp:
				"up":
					var seq := [ch[0], ch[1], ch[2], ch[0] + 12, ch[2], ch[1] + 12, ch[2] + 12, ch[1] + 12]
					for k in 8:
						syn.note(instr, seq[k] + 12, t0 + k * 0.5 * beat, 0.5 * beat, 0.5 + 0.1 * float(k % 2 == 0), 0.35, 0.55)
				"pop":
					var seq2 := [ch[0] + 12, ch[2] + 12, ch[1] + 12, ch[2] + 12]
					for k in 8:
						var acc := 0.6 if k % 4 == 0 else 0.42
						syn.note(instr, seq2[k % 4], t0 + k * 0.5 * beat, 0.4 * beat, acc, 0.4, 0.6)
				"slow":
					for k in 4:
						syn.note(instr, ch[k % ch.size()] + 12, t0 + k * beat, beat, 0.35, -0.35, 0.5)
		# Basa
		var bass_style: String = s.get("bass", "root")
		match bass_style:
			"walk":
				var tones := [root - 12, ch[1] - 12, ch[2] - 12, chords[(bar + 1) % 8][0] - 13]
				for k in 4:
					syn.note("bass", tones[k], t0 + k * beat, 0.9 * beat, 0.7, 0.0, 0.9)
			"long":
				syn.note("bass", root - 12, t0, 3.8 * beat, 0.6, 0.0, 0.8)
			_:
				syn.note("bass", root - 12, t0, 1.9 * beat, 0.75, 0.0, 0.9)
				syn.note("bass", ch[2] - 24 if ch[2] - 24 > root - 17 else root - 12, t0 + 2.0 * beat, 1.9 * beat, 0.6, 0.0, 0.9)
		# Bicí
		var drums: String = s["drums"]
		match drums:
			"shaker":
				if second:
					for k in 8:
						syn.drum("shaker", t0 + k * 0.5 * beat, 0.5 if k % 2 == 0 else 0.8, 0.3)
			"light":
				syn.drum("kick", t0, 0.8)
				syn.drum("kick", t0 + 2.5 * beat, 0.5)
				syn.drum("brush", t0 + beat, 0.7, -0.1)
				syn.drum("brush", t0 + 3.0 * beat, 0.7, -0.1)
				if second:
					for k in 8:
						syn.drum("hat", t0 + k * 0.5 * beat, 0.7 if k % 2 == 1 else 0.45, 0.35)
			"brush_swing":
				for k in 4:
					syn.drum("ohat" if k % 2 == 1 else "hat", t0 + k * beat, 0.5, 0.3)
					syn.drum("hat", t0 + (k + 0.66) * beat, 0.35, 0.3)
				if second:
					syn.drum("kick", t0, 0.45)
					syn.drum("brush", t0 + beat, 0.45)
					syn.drum("brush", t0 + 3.0 * beat, 0.45)
	# Melodie ve 2. průchodu (takty 9–16)
	var mel_instr: String = s["melody_instr"]
	var off := 32.0 * beat
	for m in s["melody"]:
		var vel: float = float(m[3]) / 127.0
		syn.note(mel_instr, m[0], off + float(m[1]) * beat, float(m[2]) * beat, vel, 0.05, 1.0)
	syn.reverb(float(s["reverb"]), 0.82, 0.35)
	syn.normalize(0.8)
	return syn
