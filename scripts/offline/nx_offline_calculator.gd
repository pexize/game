class_name NxOfflineCalculator
extends RefCounted
## Progresso offline (FR-09, ECONOMY §7). Não avança segundo a segundo: usa a
## MESMA função de tick da partida ativa com passos grandes (`dt_offline_ms`),
## então produção, consumo, gargalos, descobertas e automação seguem as
## mesmas regras. Não presume a taxa do momento em que o jogo fechou.
##
##   tempo simulado = min(ausência, limite) × eficiência offline
##
## A eficiência é aplicada ao TEMPO, não só à produção: produção e consumo
## encolhem juntos, e a taxa líquida nunca fica negativa por causa do offline.
##
## Relógio (sem servidor não há antifraude): ausência negativa vale 0 e o
## ganho tem teto; valores absurdos são marcados como `suspicious`, mas o teto
## já limita qualquer avanço de relógio.

## Ausência acima disso (30 dias) é marcada como suspeita.
const SUSPICIOUS_ELAPSED_S := 30.0 * 24.0 * 3600.0


static func apply(state: NxGameState, defs: NxDefinitions, elapsed_s: float) -> NxOfflineReport:
	var report := NxOfflineReport.new()
	report.elapsed_s = elapsed_s
	report.clock_went_back = elapsed_s < 0.0
	report.suspicious = elapsed_s < 0.0 or elapsed_s > SUSPICIOUS_ELAPSED_S

	var cap_s := float(defs.balance["offline_cap_s"])
	var counted := minf(maxf(elapsed_s, 0.0), cap_s)
	report.capped = elapsed_s > cap_s
	report.simulated_ms = floori(counted * float(defs.balance["offline_efficiency"]) * 1000.0)

	var resources_before := state.resources.duplicate()
	var produced_before := state.lifetime_produced.duplicate()
	var step_ms: int = defs.balance["dt_offline_ms"]
	var budget: int = defs.balance["offline_auto_purchase_limit"]
	var bought := 0
	var remaining := report.simulated_ms

	while remaining > 0:
		var dt := mini(step_ms, remaining)
		var tick := NxSimulation.tick(state, defs, dt, bought < budget)
		report.steps += 1
		remaining -= dt
		report.discoveries.append_array(tick.granted)
		for purchase: Dictionary in tick.auto_purchases:
			bought += 1
			report.purchases[purchase["id"]] = int(report.purchases.get(purchase["id"], 0)) + 1
		if bought >= budget and not tick.auto_purchases.is_empty():
			report.purchase_limit_reached = true

	for rid in defs.resource_ids:
		report.resource_delta[rid] = state.amount(rid) - int(resources_before.get(rid, 0))
		report.produced[rid] = int(state.lifetime_produced.get(rid, 0)) - int(produced_before.get(rid, 0))
	return report
