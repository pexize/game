extends SceneTree
## Simulador de economia sem interface (substitui a planilha de balanceamento).
##
## Uso (via tools/simulate.sh):
##   godot --headless --path . --script res://tools/simulate.gd -- \
##       [--steps=600] [--every=10] [--plan=collector,generator,...] \
##       [--auto=id_da_melhoria]
##
## Saída: CSV em stdout, uma linha a cada `every` passos. `--plan` troca a
## lista de prioridades do bot (cada item repetido conta uma unidade).
## `--auto` liga a automação nessa melhoria assim que ela for desbloqueada (D6).

const DATA_DIR := "res://data"


func _initialize() -> void:
	var steps := 600
	var every := 10
	var plan_arg := ""
	var auto_target := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--steps="):
			steps = int(arg.trim_prefix("--steps="))
		elif arg.begins_with("--every="):
			every = maxi(1, int(arg.trim_prefix("--every=")))
		elif arg.begins_with("--plan="):
			plan_arg = arg.trim_prefix("--plan=")
		elif arg.begins_with("--auto="):
			auto_target = arg.trim_prefix("--auto=")

	var defs := NxDefinitions.load_from_dir(DATA_DIR)
	if not defs.is_valid():
		for error in defs.errors:
			printerr("ERRO DE DADOS: " + error)
		quit(2)
		return

	var bot := NxGreedyBot.new(_parse_plan(plan_arg)) if not plan_arg.is_empty() else NxGreedyBot.new()
	var state := NxGameState.new_game(defs)
	var dt: int = defs.balance["dt_active_ms"]

	var header := ["t_s"]
	for rid in defs.resource_ids:
		header.append(rid)
	for cid in ["generator", "collector", "analyzer"]:
		header.append("n_" + cid)
	for rid in defs.resource_ids:
		header.append("net_" + rid + "_per_s")
	header.append("discoveries")
	print(",".join(header))

	for step in range(steps):
		bot.act(state, defs)
		if not auto_target.is_empty() and state.has_feature(NxAutomation.FEATURE) and not state.automation["enabled"]:
			var configured := NxAutomation.configure(state, defs, true, auto_target)
			if not configured.ok:
				printerr("ERRO: %s" % configured.message)
				quit(2)
				return
		var report := NxSimulation.tick(state, defs, dt)
		for purchase: Dictionary in report.auto_purchases:
			printerr("t=%ds: automação comprou %s (nível %d)" % [state.time_ms / 1000, purchase["id"], purchase["level"]])
		for discovery_id: String in report.granted:
			printerr("t=%ds: descoberta %s" % [state.time_ms / 1000, discovery_id])
		if (step + 1) % every == 0:
			var row := [str(state.time_ms / 1000)]
			for rid in defs.resource_ids:
				row.append("%.3f" % (state.amount(rid) / 1000.0))
			for cid in ["generator", "collector", "analyzer"]:
				row.append(str(state.count_of(cid)))
			for rid in defs.resource_ids:
				row.append("%.3f" % (report.net_rate(rid) / 1000.0))
			row.append(str(state.discoveries.size()))
			print(",".join(row))
	quit(0)


## "generator,collector,generator" -> [["generator", 2], ["collector", 1]]
## (a quantidade desejada é a contagem acumulada até aquela posição).
func _parse_plan(text: String) -> Array:
	var counts := {}
	var plan := []
	for id in text.split(",", false):
		counts[id] = int(counts.get(id, 0)) + 1
		plan.append([id, counts[id]])
	return plan
