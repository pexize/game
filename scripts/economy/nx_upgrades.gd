class_name NxUpgrades
extends RefCounted
## Consultas puras sobre melhorias: níveis, curva de custo, disponibilidade e
## multiplicadores. Quem altera saldos e níveis é o NxUpgradeService.

## Teto de qualquer custo (milli), abaixo de 2^53 para continuar exato em
## ponto flutuante. Níveis altos saturam aqui em vez de estourar.
const MAX_COST := 9000000000000000
## Tolerância ao arredondar para cima: ruído de ponto flutuante (por exemplo
## 32000.000000000004) não pode custar uma unidade a mais.
const CEIL_TOLERANCE := 0.000001


static func level(state: NxGameState, upgrade_id: String) -> int:
	return int(state.upgrades.get(upgrade_id, 0))


## Custo do próximo nível quando o nível atual é `current_level`:
## ceil(base × growth^nível), em milésimos. A potência é feita por
## multiplicações repetidas (deterministas em IEEE 754, ao contrário de pow
## entre arquiteturas) e satura em MAX_COST.
static func cost_at_level(upgrade: Dictionary, current_level: int) -> Dictionary:
	var out := {}
	for rid: String in upgrade["cost"]:
		var value := float(upgrade["cost"][rid])
		for _i in range(current_level):
			value = minf(value * float(upgrade["growth"]), float(MAX_COST))
		out[rid] = clampi(ceili(value - CEIL_TOLERANCE), 1, MAX_COST)
	return out


static func next_cost(state: NxGameState, defs: NxDefinitions, upgrade_id: String) -> Dictionary:
	return cost_at_level(defs.upgrades[upgrade_id], level(state, upgrade_id))


## ok = pode ser comprada agora (exceto recursos). Códigos: unknown_upgrade,
## locked, prerequisite_missing, max_level.
static func availability(state: NxGameState, defs: NxDefinitions, upgrade_id: String) -> NxResult:
	if not defs.upgrades.has(upgrade_id):
		return NxResult.failure("unknown_upgrade", "Melhoria desconhecida: %s" % upgrade_id)
	var upgrade: Dictionary = defs.upgrades[upgrade_id]
	for feature: String in upgrade["requires_features"]:
		if not state.has_feature(feature):
			return NxResult.failure("locked", "Melhoria ainda bloqueada: %s" % upgrade_id)
	for prereq: String in upgrade["prerequisites"]:
		if level(state, prereq) < 1:
			return NxResult.failure("prerequisite_missing", "Falta a melhoria '%s'." % prereq)
	if level(state, upgrade_id) >= int(upgrade["max_level"]):
		return NxResult.failure("max_level", "Nível máximo atingido: %s" % upgrade_id)
	return NxResult.success()


## Multiplicadores por componente: {"out": {def_id: float}, "in": {def_id: float}}.
## Melhorias diferentes se multiplicam entre si; componentes sem melhoria
## ficam sem entrada (valem 1.0). Percorre as melhorias em ordem de id para
## o resultado em ponto flutuante ser sempre o mesmo.
static func modifiers(state: NxGameState, defs: NxDefinitions) -> Dictionary:
	var out := {}
	var inputs := {}
	var ids := state.upgrades.keys()
	ids.sort()
	for upgrade_id: String in ids:
		var current := level(state, upgrade_id)
		if current <= 0 or not defs.upgrades.has(upgrade_id):
			continue
		var upgrade: Dictionary = defs.upgrades[upgrade_id]
		var targets: Array = defs.components.keys() if upgrade["target"] == "all" else [upgrade["target"]]
		for def_id: String in targets:
			if upgrade["effect_type"] == "output_multiplier":
				out[def_id] = float(out.get(def_id, 1.0)) * (1.0 + float(upgrade["per_level"]) * current)
			else:
				inputs[def_id] = float(inputs.get(def_id, 1.0)) * (1.0 - float(upgrade["per_level"]) * current)
	return {"out": out, "in": inputs}
