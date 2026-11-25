class_name NxEconomyEngine
extends RefCounted
## Passo de simulação determinístico (ECONOMY.md §5).
##
## Os recursos são resolvidos em ordem de tier (Energy → Matter → Data).
## Para cada recurso R:
##   disponível = saldo + produção de R neste passo
##   razão      = min(1, disponível / demanda nominal)
## Todo consumidor de R recebe a mesma razão, então o resultado não
## depende da ordem dos componentes. A eficiência de um componente é a
## menor razão entre as suas entradas; ela escala consumo e produção.
##
## Aritmética inteira (milli) com arredondamento para baixo na produção
## e no consumo: o motor nunca cria recursos por arredondamento.
##
## Fase 1: todo componente habilitado é considerado ativo. Conectividade
## e o multiplicador do Processor entram na Fase 2.


static func step(state: NxGameState, defs: NxDefinitions, dt_ms: int) -> NxStepReport:
	var report := NxStepReport.new()
	report.dt_ms = dt_ms
	if dt_ms <= 0:
		return report

	var active: Array = []
	for instance_id: int in state.components:
		var inst: Dictionary = state.components[instance_id]
		if inst["enabled"]:
			active.append({"id": instance_id, "def": defs.components[inst["def"]]})

	var production := {}
	var consumption := {}
	for rid in defs.resource_ids:
		consumption[rid] = 0

	# 1) Resolver recursos em ordem de tier. A produção de R só depende de
	#    razões de tiers menores, que já foram calculadas.
	for rid in defs.resource_ids:
		var produced := 0
		var demand := 0
		for entry: Dictionary in active:
			var def: Dictionary = entry["def"]
			if def["outputs"].has(rid):
				produced += floori(_nominal(def["outputs"][rid], dt_ms) * _efficiency(def, report.ratios))
			if def["inputs"].has(rid):
				demand += _nominal(def["inputs"][rid], dt_ms)
		production[rid] = produced
		var available: int = state.amount(rid) + produced
		report.ratios[rid] = 1.0 if demand == 0 else minf(1.0, float(available) / float(demand))

	# 2) Consumo de cada componente com a sua eficiência final.
	for entry: Dictionary in active:
		var def: Dictionary = entry["def"]
		var eff := _efficiency(def, report.ratios)
		report.efficiency[entry["id"]] = eff
		for rid: String in def["inputs"]:
			consumption[rid] += floori(_nominal(def["inputs"][rid], dt_ms) * eff)

	# 3) Aplicar produção e consumo juntos, com limite de armazenamento.
	for rid in defs.resource_ids:
		var after: int = maxi(state.amount(rid) + production[rid] - consumption[rid], 0)
		var cap := defs.max_storage(rid)
		var lost := 0
		if cap != NxDefinitions.UNLIMITED and after > cap:
			lost = after - cap
			after = cap
		state.resources[rid] = after
		state.lifetime_produced[rid] = int(state.lifetime_produced.get(rid, 0)) + production[rid]
		report.produced[rid] = production[rid]
		report.consumed[rid] = consumption[rid]
		report.lost[rid] = lost

	state.time_ms += dt_ms
	return report


## Quantidade nominal (milli) de uma taxa (milli/s) em `dt_ms`.
static func _nominal(rate: int, dt_ms: int) -> int:
	return floori(float(rate) * float(dt_ms) / 1000.0)


## Menor razão entre as entradas do componente; 1 se não tiver entradas.
static func _efficiency(def: Dictionary, ratios: Dictionary) -> float:
	var eff := 1.0
	for rid: String in def["inputs"]:
		eff = minf(eff, float(ratios.get(rid, 1.0)))
	return eff
