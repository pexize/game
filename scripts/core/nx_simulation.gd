class_name NxSimulation
extends RefCounted
## Um tick completo da simulação, na ordem definida em ARCHITECTURE.md §6:
## economia (ativação → recursos → aplicação → estatísticas) e, em seguida,
## descobertas e, por último, a automação (no máximo uma compra por tick).
## É a única função que a partida ativa e o cálculo offline precisam chamar
## a cada passo.


static func tick(state: NxGameState, defs: NxDefinitions, dt_ms: int) -> NxStepReport:
	var report := NxEconomyEngine.step(state, defs, dt_ms)
	report.granted = NxDiscoveryEngine.evaluate(state, defs, report)
	report.auto_purchases = NxAutomation.run(state, defs)
	return report
