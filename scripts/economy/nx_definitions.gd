class_name NxDefinitions
extends RefCounted
## Definições de conteúdo (recursos, componentes, balanceamento) carregadas
## de JSON e validadas. É somente leitura depois de construída.
##
## Unidades internas (D-030): todas as quantidades são inteiros em
## milésimos de unidade, e as taxas em milésimos por segundo. O JSON usa
## unidades "humanas" (10 = dez unidades, 0.5 = meia unidade por segundo).
##
## Regras validadas aqui (ECONOMY.md):
##  - cada recurso tem um `tier`; toda saída de um componente precisa ter
##    tier maior que todas as suas entradas. Isso torna a cadeia de
##    recursos acíclica por construção (nenhum ciclo cria recursos);
##  - referências a recursos e componentes existem;
##  - quantidades e taxas são positivas;
##  - início sem bloqueio (D-014): todo componente liberado no início
##    pode ser pago na primeira construção.
## Erros são devolvidos em `errors`; nada aqui usa push_error.

const MILLI := 1000
const UNLIMITED := -1

const _RESOURCE_KEYS := ["id", "name_key", "tier", "max_storage", "_file"]
const _COMPONENT_KEYS := [
	"id", "name_key", "cost", "inputs", "outputs", "output_ports",
	"removable", "protect_last", "child_multiplier", "build_limit", "_file",
]
const _BALANCE_KEYS := [
	"notes", "core_component", "start_resources", "start_unlocked",
	"dt_active_ms", "dt_offline_ms", "offline_cap_s", "offline_efficiency",
	"offline_auto_purchase_limit", "removal_refund",
]

var errors := PackedStringArray()
## Ids dos recursos em ordem de tier (cadeia de resolução).
var resource_ids := PackedStringArray()
## id -> {"tier": int, "max_storage": int (milli, ou UNLIMITED)}
var resources := {}
## id -> {"cost": {res: milli}, "inputs": {res: milli/s}, "outputs": {...},
##        "output_ports": int, "removable": bool, "protect_last": bool,
##        "child_multiplier": float, "build_limit": int (0 = sem limite)}
var components := {}
## core_component, start_resources (milli), start_unlocked, dt_active_ms,
## dt_offline_ms, offline_cap_s, offline_efficiency, offline_auto_purchase_limit,
## removal_refund
var balance := {}
## id -> descoberta normalizada (ver NxDiscoveryRules)
var discoveries := {}
## ids em ordem topológica: pré-requisitos sempre antes de quem depende deles
var discovery_order := PackedStringArray()
## id -> melhoria normalizada (ver NxUpgradeRules)
var upgrades := {}


func is_valid() -> bool:
	return errors.is_empty()


static func load_from_dir(dir_path: String) -> NxDefinitions:
	var defs := NxDefinitions.new()
	var raw_resources := defs._read_dir(dir_path.path_join("resources"))
	var raw_components := defs._read_dir(dir_path.path_join("components"))
	var raw_discoveries := defs._read_dir(dir_path.path_join("discoveries"))
	var raw_upgrades := defs._read_dir(dir_path.path_join("upgrades"))
	var raw_balance: Variant = defs._read_file(dir_path.path_join("balance.json"))
	defs._build(raw_resources, raw_components, raw_balance if raw_balance is Dictionary else {}, raw_discoveries, raw_upgrades)
	return defs


static func from_dicts(raw_resources: Array, raw_components: Array, raw_balance: Dictionary, raw_discoveries: Array = [], raw_upgrades: Array = []) -> NxDefinitions:
	var defs := NxDefinitions.new()
	defs._build(raw_resources, raw_components, raw_balance, raw_discoveries, raw_upgrades)
	return defs


func max_storage(resource_id: String) -> int:
	return resources[resource_id]["max_storage"]


# --- leitura ---------------------------------------------------------------

func _read_dir(dir_path: String) -> Array:
	var out := []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_err("diretório não encontrado: %s" % dir_path)
		return out
	var files := Array(dir.get_files())
	files.sort()
	for file_name: String in files:
		if not file_name.ends_with(".json"):
			continue
		var parsed: Variant = _read_file(dir_path.path_join(file_name))
		if parsed is Dictionary:
			parsed["_file"] = file_name.get_basename()
			out.append(parsed)
	return out


func _read_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		_err("arquivo não encontrado: %s" % path)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		_err("%s: JSON inválido (linha %d): %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	if not (json.data is Dictionary):
		_err("%s: o conteúdo deve ser um objeto JSON" % path)
		return null
	return json.data


# --- validação -------------------------------------------------------------

func _build(raw_resources: Array, raw_components: Array, raw_balance: Dictionary, raw_discoveries: Array, raw_upgrades: Array) -> void:
	_build_resources(raw_resources)
	_build_components(raw_components)
	_build_balance(raw_balance)
	NxDiscoveryRules.build(self, raw_discoveries)
	NxUpgradeRules.build(self, raw_upgrades)
	_check_winnable_with_discoveries()


## D-014 sobre tudo o que o jogo pode liberar: componentes do início mais os
## liberados por recompensas de descobertas.
func _check_winnable_with_discoveries() -> void:
	var core_id: String = balance.get("core_component", "")
	if not components.has(core_id) or not balance.has("start_unlocked"):
		return
	var all_unlocked: Array = balance["start_unlocked"].duplicate()
	for id in discovery_order:
		for reward: Dictionary in discoveries[id]["rewards"]:
			if reward["type"] == "unlock_component" and not all_unlocked.has(reward["component"]):
				all_unlocked.append(reward["component"])
	_check_start_is_winnable(core_id, balance["start_resources"], all_unlocked, "balance")


func _build_resources(raw_list: Array) -> void:
	for raw: Variant in raw_list:
		if not (raw is Dictionary):
			_err("recurso: entrada não é um objeto")
			continue
		var id := str(raw.get("id", ""))
		var where := "recurso '%s'" % id
		_check_keys(raw, _RESOURCE_KEYS, where)
		if id.is_empty():
			_err("%s: falta 'id'" % where)
			continue
		if resources.has(id):
			_err("%s: id duplicado" % where)
			continue
		if raw.has("_file") and raw["_file"] != id:
			_err("%s: o id difere do nome do arquivo '%s'" % [where, raw["_file"]])
		if not _is_whole_number(raw.get("tier")):
			_err("%s: 'tier' deve ser um inteiro" % where)
			continue
		var cap := UNLIMITED
		if raw.has("max_storage"):
			if _is_number(raw["max_storage"]) and raw["max_storage"] > 0:
				cap = _milli(raw["max_storage"])
			else:
				_err("%s: 'max_storage' deve ser um número positivo" % where)
		resources[id] = {"tier": int(raw["tier"]), "max_storage": cap}

	var ids := resources.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var tier_a: int = resources[a]["tier"]
		var tier_b: int = resources[b]["tier"]
		return tier_a < tier_b or (tier_a == tier_b and a < b))
	resource_ids = PackedStringArray(ids)


func _build_components(raw_list: Array) -> void:
	for raw: Variant in raw_list:
		if not (raw is Dictionary):
			_err("componente: entrada não é um objeto")
			continue
		var id := str(raw.get("id", ""))
		var where := "componente '%s'" % id
		_check_keys(raw, _COMPONENT_KEYS, where)
		if id.is_empty():
			_err("%s: falta 'id'" % where)
			continue
		if components.has(id):
			_err("%s: id duplicado" % where)
			continue
		if raw.has("_file") and raw["_file"] != id:
			_err("%s: o id difere do nome do arquivo '%s'" % [where, raw["_file"]])

		var comp := {
			"cost": _amount_map(raw, "cost", where),
			"inputs": _amount_map(raw, "inputs", where),
			"outputs": _amount_map(raw, "outputs", where),
			"output_ports": _whole(raw, "output_ports", 0, where),
			"removable": _boolean(raw, "removable", true, where),
			"protect_last": _boolean(raw, "protect_last", false, where),
			"child_multiplier": 1.0,
			"build_limit": _whole(raw, "build_limit", 0, where),
		}
		if raw.has("child_multiplier"):
			if _is_number(raw["child_multiplier"]) and raw["child_multiplier"] >= 1.0:
				comp["child_multiplier"] = float(raw["child_multiplier"])
			else:
				_err("%s: 'child_multiplier' deve ser um número ≥ 1" % where)

		# Cadeia de recursos acíclica: saída precisa ser de tier maior que toda entrada.
		for out_id: String in comp["outputs"]:
			for in_id: String in comp["inputs"]:
				if resources[out_id]["tier"] <= resources[in_id]["tier"]:
					_err("%s: a saída '%s' (tier %d) não é posterior à entrada '%s' (tier %d); isso quebra a cadeia de recursos" % [
						where, out_id, resources[out_id]["tier"], in_id, resources[in_id]["tier"]])
		components[id] = comp


func _build_balance(raw: Dictionary) -> void:
	_check_keys(raw, _BALANCE_KEYS, "balance")
	var where := "balance"
	var core_id := str(raw.get("core_component", ""))
	if not components.has(core_id):
		_err("%s: 'core_component' ('%s') não existe" % [where, core_id])
	elif components[core_id]["removable"]:
		_err("%s: o Core deve ter 'removable': false" % where)

	var start := {}
	var raw_start: Variant = raw.get("start_resources", null)
	if not (raw_start is Dictionary):
		_err("%s: falta 'start_resources'" % where)
	else:
		for rid: String in raw_start:
			if not resources.has(rid):
				_err("%s: 'start_resources' usa recurso desconhecido '%s'" % [where, rid])
			elif _is_number(raw_start[rid]) and raw_start[rid] >= 0:
				start[rid] = _milli(raw_start[rid])
			else:
				_err("%s: 'start_resources.%s' deve ser um número ≥ 0" % [where, rid])

	var unlocked := []
	var raw_unlocked: Variant = raw.get("start_unlocked", null)
	if not (raw_unlocked is Array):
		_err("%s: falta 'start_unlocked'" % where)
	else:
		for cid: Variant in raw_unlocked:
			if components.has(str(cid)):
				unlocked.append(str(cid))
			else:
				_err("%s: 'start_unlocked' usa componente desconhecido '%s'" % [where, cid])

	var dt_active := _required_whole(raw, "dt_active_ms", where)
	var dt_offline := _required_whole(raw, "dt_offline_ms", where)
	var cap_s := _required_whole(raw, "offline_cap_s", where)
	if dt_active <= 0 or dt_offline < dt_active or cap_s <= 0:
		_err("%s: exige 0 < dt_active_ms ≤ dt_offline_ms e offline_cap_s > 0" % where)
	var auto_limit := _required_whole(raw, "offline_auto_purchase_limit", where)
	if auto_limit < 0:
		_err("%s: 'offline_auto_purchase_limit' deve ser ≥ 0" % where)
	var efficiency := float(raw.get("offline_efficiency", -1.0)) if _is_number(raw.get("offline_efficiency")) else -1.0
	if efficiency <= 0.0 or efficiency > 1.0:
		_err("%s: 'offline_efficiency' deve estar em (0, 1]" % where)
	var refund := float(raw.get("removal_refund", -1.0)) if _is_number(raw.get("removal_refund")) else -1.0
	if refund < 0.0 or refund > 1.0:
		_err("%s: 'removal_refund' deve estar em [0, 1]" % where)

	balance = {
		"core_component": core_id,
		"start_resources": start,
		"start_unlocked": unlocked,
		"dt_active_ms": dt_active,
		"dt_offline_ms": dt_offline,
		"offline_cap_s": cap_s,
		"offline_efficiency": efficiency,
		"offline_auto_purchase_limit": auto_limit,
		"removal_refund": refund,
	}


## D-014 (início sem bloqueio): todo componente liberado no início precisa
## ser construível por algum caminho. Um recurso do custo é aceito se a
## reserva inicial o cobre ou se algo já construível o produz. Parte do
## Core e vai ampliando o conjunto de recursos produzíveis até estabilizar.
## É uma checagem conservadora sobre os dados; o teste de cenários
## confirma o caminho jogando.
func _check_start_is_winnable(core_id: String, start: Dictionary, unlocked: Array, where: String) -> void:
	var producible := {}
	for rid: String in components[core_id]["outputs"]:
		producible[rid] = true
	var pending: Array = unlocked.filter(
		func(cid: String) -> bool: return cid != core_id and components.has(cid))

	var progress := true
	while progress and not pending.is_empty():
		progress = false
		for cid: String in pending.duplicate():
			var comp: Dictionary = components[cid]
			var affordable := true
			for rid: String in comp["cost"]:
				if int(start.get(rid, 0)) < int(comp["cost"][rid]) and not producible.has(rid):
					affordable = false
			if not affordable:
				continue
			pending.erase(cid)
			progress = true
			var fed := true
			for rid: String in comp["inputs"]:
				if not producible.has(rid):
					fed = false
			if fed:
				for rid: String in comp["outputs"]:
					producible[rid] = true

	for cid: String in pending:
		_err("%s: '%s' não pode ser construído partindo do início (reserva e produção não cobrem o custo; risco de bloqueio, D-014)" % [where, cid])


# --- utilitários -----------------------------------------------------------

func _amount_map(raw: Dictionary, key: String, where: String) -> Dictionary:
	var out := {}
	var value: Variant = raw.get(key, {})
	if not (value is Dictionary):
		_err("%s: '%s' deve ser um objeto {recurso: quantidade}" % [where, key])
		return out
	for rid: String in value:
		if not resources.has(rid):
			_err("%s: '%s' usa recurso desconhecido '%s'" % [where, key, rid])
		elif _is_number(value[rid]) and value[rid] > 0:
			out[rid] = _milli(value[rid])
		else:
			_err("%s: '%s.%s' deve ser um número positivo" % [where, key, rid])
	return out


func _whole(raw: Dictionary, key: String, default: int, where: String) -> int:
	if not raw.has(key):
		return default
	if _is_whole_number(raw[key]) and raw[key] >= 0:
		return int(raw[key])
	_err("%s: '%s' deve ser um inteiro ≥ 0" % [where, key])
	return default


func _required_whole(raw: Dictionary, key: String, where: String) -> int:
	if not _is_whole_number(raw.get(key)):
		_err("%s: '%s' deve ser um inteiro" % [where, key])
		return 0
	return int(raw[key])


func _boolean(raw: Dictionary, key: String, default: bool, where: String) -> bool:
	if not raw.has(key):
		return default
	if raw[key] is bool:
		return raw[key]
	_err("%s: '%s' deve ser verdadeiro ou falso" % [where, key])
	return default


func _check_keys(raw: Dictionary, allowed: Array, where: String) -> void:
	for key: Variant in raw:
		if not allowed.has(key):
			_err("%s: campo desconhecido '%s' (erro de digitação?)" % [where, key])


func _is_number(value: Variant) -> bool:
	return value is float or value is int


func _is_whole_number(value: Variant) -> bool:
	return _is_number(value) and float(value) == floorf(float(value))


func _milli(value: Variant) -> int:
	return roundi(float(value) * MILLI)


func _err(message: String) -> void:
	errors.append(message)
