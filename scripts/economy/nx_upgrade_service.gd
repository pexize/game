class_name NxUpgradeService
extends RefCounted
## Compra de melhorias (FR-07). Atômica: valida tudo antes de cobrar; se algo
## faltar (recurso, bloqueio, pré-requisito, nível máximo), nada muda.


static func purchase(state: NxGameState, defs: NxDefinitions, upgrade_id: String) -> NxResult:
	var available := NxUpgrades.availability(state, defs, upgrade_id)
	if not available.ok:
		return available
	var cost := NxUpgrades.next_cost(state, defs, upgrade_id)
	if not NxLedger.try_spend(state, cost):
		return NxResult.failure("insufficient_resources", "Recursos insuficientes para %s" % upgrade_id)
	var new_level := NxUpgrades.level(state, upgrade_id) + 1
	state.upgrades[upgrade_id] = new_level
	return NxResult.success({"level": new_level, "cost": cost})


## O que a interface mostra antes da compra: custo, efeito atual e do próximo
## nível, e por que não pode comprar. Só lê.
static func preview(state: NxGameState, defs: NxDefinitions, upgrade_id: String) -> Dictionary:
	var upgrade: Dictionary = defs.upgrades[upgrade_id]
	var current := NxUpgrades.level(state, upgrade_id)
	var available := NxUpgrades.availability(state, defs, upgrade_id)
	var maxed := current >= int(upgrade["max_level"])
	var cost := {} if maxed else NxUpgrades.next_cost(state, defs, upgrade_id)
	return {
		"id": upgrade_id,
		"level": current,
		"max_level": upgrade["max_level"],
		"available": available.ok,
		"reason": "" if available.ok else available.code,
		"cost": cost,
		"affordable": available.ok and NxLedger.can_afford(state, cost),
		"effect_now": _factor(upgrade, current),
		"effect_next": _factor(upgrade, mini(current + 1, int(upgrade["max_level"]))),
	}


## Fator aplicado ao alvo no nível dado (1.0 = sem efeito).
static func _factor(upgrade: Dictionary, at_level: int) -> float:
	if upgrade["effect_type"] == "output_multiplier":
		return 1.0 + float(upgrade["per_level"]) * at_level
	return 1.0 - float(upgrade["per_level"]) * at_level
