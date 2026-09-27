extends RefCounted
class_name CombatEngine

# --- MATEMATIKAI ÉS SZABÁLYRENDSZERI FÜGGVÉNYEK ---

## 80-100% közötti sebzéskalkuláció felfelé kerekítve (ceili)
static func calculate_damage_roll(base_stat: int) -> int:
	var roll = randf_range(0.8, 1.0)
	return ceili(float(base_stat) * roll)

## Ütésenkénti XP és szintlépés feldolgozása a feladat szabályai szerint
static func apply_hero_xp(hero: Dictionary, amount: int = 1) -> Array[String]:
	var logs: Array[String] = []
	hero["xp"] += amount
	logs.append("    [XP] +%d XP jóváírva! (Állapot: %d/10 XP)" % [amount, hero["xp"]])

	if hero["xp"] >= 10:
		hero["xp"] -= 10
		hero["level"] += 1
		hero["attack_power"] += 1
		hero["defense"] += 1
		hero["max_hp"] += 10
		hero["current_hp"] = hero["max_hp"] # Szintlépéskor teljes gyógyulás
		hero["initiative"] *= 1.1            # +10% kezdeményezés
		hero["vision_limit"] *= 3            # Látótávolság szorzása 3-mal

		logs.append("    ★ ★ ★ SZINTLÉPÉS! ★ ★ ★")
		logs.append("    Új szint: %d | Életerő felgyógyítva: %d/%d | Támadás: %d | Védelem: %d | Kezdeményezés: %.2f | Látótáv: %d" % [
			hero["level"], hero["current_hp"], hero["max_hp"], hero["attack_power"], hero["defense"], hero["initiative"], hero["vision_limit"]
		])
	return logs

## Automatikus harc levezetése köztes helyzetjelentésekkel
static func simulate_battle(hero: Dictionary, monster: Dictionary, use_defense: bool = true) -> Dictionary:
	var logs: Array[String] = []
	logs.append("==================================================================")
	logs.append("CSATA KEZDŐDIK: %s (HP: %d) VS %s (HP: %d)" % [
		hero["hero_name"], hero["current_hp"], monster["monster_name"], monster["current_hp"]
	])
	logs.append("==================================================================")

	# Kezdeményezés vizsgálata: egyenlőség esetén a hős kezd
	var hero_starts = hero["initiative"] >= monster["initiative"]
	var hero_turn = hero_starts

	logs.append("Kezdeményezés vizsgálat: Hős (%.1f) vs Szörny (%.1f)" % [hero["initiative"], monster["initiative"]])
	logs.append("-> %s üthet először!\n" % ("A HŐS" if hero_starts else "A SZÖRNY"))

	var round_num: int = 1
	var max_rounds: int = 50

	while hero["current_hp"] > 0 and monster["current_hp"] > 0 and round_num <= max_rounds:
		logs.append("-- %d. KÖR --" % round_num)

		if hero_turn:
			# HŐS TÁMADÁSA
			var raw_dmg = calculate_damage_roll(hero["attack_power"])
			var def_val = monster["defense"] if use_defense else 0
			var actual_dmg = maxi(0, raw_dmg - def_val)
			monster["current_hp"] = maxi(0, monster["current_hp"] - actual_dmg)

			logs.append("  [HŐS TÁMAD] Alap: %d -> Dobott: %d | Védelem levonva: %d -> Tényleges sebzés: %d" % [
				hero["attack_power"], raw_dmg, def_val, actual_dmg
			])
			logs.append("  -> %s életereje: %d/%d" % [monster["monster_name"], monster["current_hp"], monster["max_hp"]])

			# Minden ütés után 1 XP jár
			var xp_logs = apply_hero_xp(hero, 1)
			logs.append_array(xp_logs)

			if monster["current_hp"] <= 0:
				logs.append("\n>>> %s ELESETT A CSATÁBAN!" % monster["monster_name"])
				break
		else:
			# SZÖRNY TÁMADÁSA
			var raw_dmg = calculate_damage_roll(monster["base_damage"])
			var def_val = hero["defense"] if use_defense else 0
			var actual_dmg = maxi(0, raw_dmg - def_val)
			hero["current_hp"] = maxi(0, hero["current_hp"] - actual_dmg)

			logs.append("  [%s TÁMAD] Alap: %d -> Dobott: %d | Védelem levonva: %d -> Tényleges sebzés: %d" % [
				monster["monster_name"].to_upper(), monster["base_damage"], raw_dmg, def_val, actual_dmg
			])
			logs.append("  -> Hős életereje: %d/%d" % [hero["current_hp"], hero["max_hp"]])

			if hero["current_hp"] <= 0:
				logs.append("\n>>> A HŐS ELESETT A CSATÁBAN!")
				break

		hero_turn = not hero_turn
		round_num += 1

	var winner = "HERO" if hero["current_hp"] > 0 else "MONSTER"
	logs.append("------------------------------------------------------------------")
	logs.append("CSATA VÉGE! Győztes: %s (%d kör alatt)" % [
		hero["hero_name"] if winner == "HERO" else monster["monster_name"], round_num
	])

	# Titulus megszerzése a feladat szerint
	if winner == "HERO" and monster.get("title", "") != "":
		var acquired = "the slayer of " + monster["title"]
		if not acquired in hero["hero_name"]:
			hero["hero_name"] = "%s, %s" % [hero["hero_name"], acquired]
			logs.append("★ ÚJ TITULUS MEGSZEREZVE: %s" % hero["hero_name"])

	logs.append("==================================================================\n")
	return {"winner": winner, "logs": logs}

## Ellépési támadás tesztelése
static func simulate_opportunity_attack(hero: Dictionary, monster: Dictionary) -> String:
	var msg = "[ELLÉPÉSI PRÓBA] A hős el akar lépni %s mellől...\n" % monster["monster_name"]
	msg += "  Kezdeményezés: Hős (%.1f) vs Szörny (%.1f)\n" % [hero["initiative"], monster["initiative"]]

	if monster["initiative"] > hero["initiative"]:
		var raw = calculate_damage_roll(monster["base_damage"])
		var actual = maxi(0, raw - hero["defense"])
		hero["current_hp"] = maxi(0, hero["current_hp"] - actual)
		msg += "  -> A szörny gyorsabb volt! Menekülés közben rásújt a hősre: %d sebzés (Védelem levonva: %d)!\n" % [actual, hero["defense"]]
		msg += "  -> Hős maradék életereje: %d/%d" % [hero["current_hp"], hero["max_hp"]]
	else:
		msg += "  -> A hős elég gyors volt (vagy egyenlő)! Sikeresen ellépett sebződés nélkül."

	return msg
