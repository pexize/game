class_name NxDiscoveryView
extends RefCounted
## O que a interface pode mostrar de cada descoberta (GDD §7, Visibilidade).
## Só lê o estado; não concede nada.
##
##   obtained  -> título, dica, recompensas completas, ordem e tempo
##   available -> pré-requisitos cumpridos: título, dica e as CATEGORIAS dos
##                requisitos, sem os números
##   distant   -> pré-requisitos pendentes: só o título (pista temática)
##   hidden    -> descoberta secreta ainda não obtida: nada


static func status(state: NxGameState, defs: NxDefinitions, discovery_id: String) -> Dictionary:
	var discovery: Dictionary = defs.discoveries[discovery_id]
	if state.discoveries.has(discovery_id):
		return {
			"state": "obtained", "id": discovery_id,
			"title_key": discovery["title_key"], "hint_key": discovery["hint_key"],
			"rewards": discovery["rewards"].duplicate(true),
			"order": state.discoveries[discovery_id]["order"],
			"time_ms": state.discoveries[discovery_id]["time_ms"],
		}
	if discovery["visibility"] == "secret":
		return {"state": "hidden", "id": discovery_id}
	var prerequisites_met := true
	for prereq: String in discovery["prerequisites"]:
		if not state.discoveries.has(prereq):
			prerequisites_met = false
	if prerequisites_met:
		return {
			"state": "available", "id": discovery_id,
			"title_key": discovery["title_key"], "hint_key": discovery["hint_key"],
			"categories": categories(discovery),
		}
	return {"state": "distant", "id": discovery_id, "title_key": discovery["title_key"]}


## Categorias de requisito (sem valores), em ordem fixa.
static func categories(discovery: Dictionary) -> Array:
	var found := {}
	for condition: Dictionary in discovery["conditions"]:
		found[NxDiscoveryRules.CATEGORY[condition["type"]]] = true
	var ordered := []
	for category: String in ["quantitative", "structural", "functional", "historical"]:
		if found.has(category):
			ordered.append(category)
	return ordered


## Primeira descoberta disponível (para "próxima descoberta" do Dashboard); "" se não houver.
static func next_available(state: NxGameState, defs: NxDefinitions) -> String:
	for id in defs.discovery_order:
		if status(state, defs, id)["state"] == "available":
			return id
	return ""
