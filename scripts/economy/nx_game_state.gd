class_name NxGameState
extends RefCounted
## Estado da partida: dados puros, sem lógica de economia e sem nós.
## Só os serviços (Ledger, BuildService, EconomyEngine) o alteram; a
## interface apenas lê. Todas as quantidades são inteiros em milésimos.

## id do recurso -> quantidade (milli)
var resources := {}
## instance_id (int) -> {"def": String, "enabled": bool}
var components := {}
var next_instance_id := 1
## id do componente -> true
var unlocked := {}
## id do recurso -> total produzido desde o início (milli, antes do limite)
var lifetime_produced := {}
## tempo simulado em milissegundos
var time_ms := 0


static func new_game(defs: NxDefinitions) -> NxGameState:
	var state := NxGameState.new()
	for rid in defs.resource_ids:
		state.resources[rid] = int(defs.balance["start_resources"].get(rid, 0))
		state.lifetime_produced[rid] = 0
	for cid: String in defs.balance["start_unlocked"]:
		state.unlocked[cid] = true
	state.add_component(defs.balance["core_component"])
	return state


## Cria a instância sem cobrar nada; quem cobra é o BuildService.
func add_component(def_id: String) -> int:
	var instance_id := next_instance_id
	next_instance_id += 1
	components[instance_id] = {"def": def_id, "enabled": true}
	return instance_id


func count_of(def_id: String) -> int:
	var count := 0
	for instance_id: int in components:
		if components[instance_id]["def"] == def_id:
			count += 1
	return count


func is_unlocked(def_id: String) -> bool:
	return unlocked.has(def_id)


func amount(resource_id: String) -> int:
	return int(resources.get(resource_id, 0))


func to_dict() -> Dictionary:
	var comps := {}
	for instance_id: int in components:
		comps[str(instance_id)] = components[instance_id].duplicate()
	var unlocked_ids := unlocked.keys()
	unlocked_ids.sort()
	return {
		"resources": resources.duplicate(),
		"components": comps,
		"next_instance_id": next_instance_id,
		"unlocked": unlocked_ids,
		"lifetime_produced": lifetime_produced.duplicate(),
		"time_ms": time_ms,
	}


static func from_dict(data: Dictionary) -> NxGameState:
	var state := NxGameState.new()
	state.resources = _ints(data.get("resources", {}))
	state.lifetime_produced = _ints(data.get("lifetime_produced", {}))
	state.next_instance_id = int(data.get("next_instance_id", 1))
	state.time_ms = int(data.get("time_ms", 0))
	for key: String in data.get("components", {}):
		var inst: Dictionary = data["components"][key]
		state.components[int(key)] = {"def": str(inst["def"]), "enabled": bool(inst["enabled"])}
	for cid: String in data.get("unlocked", []):
		state.unlocked[cid] = true
	return state


## Hash estável do estado; chaves de dicionário são ordenadas na serialização.
func state_hash() -> String:
	return JSON.stringify(to_dict(), "", true).sha256_text()


static func _ints(source: Dictionary) -> Dictionary:
	var out := {}
	for key: String in source:
		out[key] = int(source[key])
	return out
