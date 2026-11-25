extends "res://tests/framework/suite.gd"
## Rede em árvore: ligações, portas, ativação, remoção, Processor.

const Fixtures := preload("res://tests/helpers/fixtures.gd")

const DT := 1000
const CORE := 1


func _defs_with_core_ports(ports: int) -> NxDefinitions:
	var components := Fixtures.raw_components()
	components[0]["output_ports"] = ports
	return NxDefinitions.from_dicts(Fixtures.raw_resources(), components, Fixtures.raw_balance())


func _link(state: NxGameState, defs: NxDefinitions, parent_id: int, def_id: String) -> int:
	var instance_id := state.add_component(def_id)
	var result := NxNetwork.connect_components(state, defs, parent_id, instance_id)
	if not result.ok:
		fail("ligação de teste falhou: %s" % result.code)
	return instance_id


# --- ligações --------------------------------------------------------------

func test_connect_sets_parent_and_consumes_a_port() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	var generator := _link(state, defs, CORE, "generator")
	assert_eq(state.components[generator]["parent"], CORE)
	assert_eq(NxNetwork.children_of(state, CORE), [generator])
	assert_eq(NxNetwork.free_ports(state, defs, CORE), 9, "10 portas - 1")
	return true


func test_new_components_start_disconnected() -> bool:
	var defs := Fixtures.defs()
	var state := NxGameState.new_game(defs)
	state.resources["energy"] = 50000
	var result := NxBuildService.build(state, defs, "generator")
	assert_eq(state.components[result.data["instance_id"]]["parent"], 0, "construir não liga")
	return true


func test_connect_rejections() -> bool:
	var defs := _defs_with_core_ports(2)
	var state := Fixtures.blank_state(defs)
	var a := _link(state, defs, CORE, "relay")
	var b := _link(state, defs, a, "generator")
	var orphan := state.add_component("generator")

	assert_eq(NxNetwork.connect_components(state, defs, CORE, 99).code, "unknown_instance")
	assert_eq(NxNetwork.connect_components(state, defs, a, a).code, "self_connection")
	assert_eq(NxNetwork.connect_components(state, defs, a, CORE).code, "core_has_no_parent")
	assert_eq(NxNetwork.connect_components(state, defs, CORE, b).code, "already_connected")
	_link(state, defs, CORE, "generator")  # ocupa a segunda e última porta do Core
	assert_eq(NxNetwork.connect_components(state, defs, CORE, orphan).code, "no_free_port")
	return true


func test_connect_rejects_cycles() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	var relay := state.add_component("relay")           # solto
	var child := state.add_component("generator")
	assert_true(NxNetwork.connect_components(state, defs, relay, child).ok, "filho sob o relay solto")
	# Ligar o relay sob o próprio filho fecharia um ciclo.
	var result := NxNetwork.connect_components(state, defs, child, relay)
	assert_eq(result.code, "would_create_cycle")
	assert_eq(int(state.components[relay]["parent"]), 0, "nada mudou")
	return true


func test_a_failed_connect_changes_nothing() -> bool:
	var defs := _defs_with_core_ports(1)
	var state := Fixtures.blank_state(defs)
	_link(state, defs, CORE, "generator")
	var extra := state.add_component("generator")
	var before := state.state_hash()
	assert_false(NxNetwork.connect_components(state, defs, CORE, extra).ok)
	assert_eq(state.state_hash(), before)
	return true


func test_disconnect() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	var generator := _link(state, defs, CORE, "generator")
	assert_true(NxNetwork.disconnect_component(state, generator).ok)
	assert_eq(state.components[generator]["parent"], 0)
	assert_eq(NxNetwork.free_ports(state, defs, CORE), 10, "a porta foi liberada")
	assert_eq(NxNetwork.disconnect_component(state, generator).code, "not_connected")
	assert_eq(NxNetwork.disconnect_component(state, 99).code, "unknown_instance")
	return true


func test_first_free_parent_prefers_nearest_to_core() -> bool:
	var defs := _defs_with_core_ports(1)
	var state := Fixtures.blank_state(defs)
	assert_eq(NxNetwork.first_free_parent(state, defs), CORE)
	var relay := _link(state, defs, CORE, "relay")      # enche a única porta do Core
	assert_eq(NxNetwork.first_free_parent(state, defs), relay, "o Core está cheio")
	return true


func test_first_free_parent_is_zero_when_network_is_full() -> bool:
	# "sink" não tem portas de saída: com o Core limitado a 1 porta, a rede enche.
	var components := Fixtures.raw_components()
	components[0]["output_ports"] = 1
	components.append({"id": "sink", "inputs": {"energy": 0.1}, "output_ports": 0})
	var defs := NxDefinitions.from_dicts(Fixtures.raw_resources(), components, Fixtures.raw_balance())
	assert_eq("\n".join(defs.errors), "", "definições do teste")
	var state := Fixtures.blank_state(defs)
	_link(state, defs, CORE, "sink")
	assert_eq(NxNetwork.first_free_parent(state, defs), 0, "nenhuma porta livre")
	return true


# --- ativação --------------------------------------------------------------

func test_only_connected_enabled_components_are_active() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	var relay := _link(state, defs, CORE, "relay")
	var under_relay := _link(state, defs, relay, "generator")
	var orphan := state.add_component("generator")
	var orphan_child := state.add_component("collector")
	NxNetwork.connect_components(state, defs, orphan, orphan_child)

	var active := NxNetwork.active_ids(state, defs)
	assert_true(active.has(CORE) and active.has(relay) and active.has(under_relay), "árvore do Core ativa")
	assert_false(active.has(orphan), "solto fica inativo")
	assert_false(active.has(orphan_child), "sub-árvore solta fica inativa")
	return true


func test_disabling_a_node_deactivates_its_subtree() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	var relay := _link(state, defs, CORE, "relay")
	var generator := _link(state, defs, relay, "generator")
	assert_true(NxNetwork.set_enabled(state, defs, relay, false).ok)
	var active := NxNetwork.active_ids(state, defs)
	assert_false(active.has(relay))
	assert_false(active.has(generator), "o caminho passa por um nó desabilitado")
	return true


func test_core_cannot_be_disabled() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	assert_eq(NxNetwork.set_enabled(state, defs, CORE, false).code, "not_removable")
	assert_true(state.components[CORE]["enabled"])
	return true


func test_disconnected_component_does_not_produce() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	state.add_component("generator")                    # solto
	NxEconomyEngine.step(state, defs, DT)
	assert_eq(state.amount("energy"), 1000, "só o Core produz")
	return true


func test_disconnecting_stops_the_whole_subtree() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	var relay := _link(state, defs, CORE, "relay")
	_link(state, defs, relay, "generator")
	state.resources["energy"] = 10000
	NxEconomyEngine.step(state, defs, DT)
	assert_eq(state.amount("energy"), 10000 + 1000 + 1500 - 300, "core + generator - relay")
	NxNetwork.disconnect_component(state, relay)
	state.resources["energy"] = 10000
	NxEconomyEngine.step(state, defs, DT)
	assert_eq(state.amount("energy"), 11000, "relay e generator inativos")
	return true


func test_inactive_components_have_no_efficiency_entry() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	var orphan := state.add_component("collector")
	var report := NxEconomyEngine.step(state, defs, DT)
	assert_false(report.efficiency.has(orphan))
	assert_true(report.efficiency.has(CORE))
	return true


# --- Processor -------------------------------------------------------------

func test_processor_multiplies_direct_children_output() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	var processor := _link(state, defs, CORE, "processor")
	_link(state, defs, processor, "generator")
	state.resources["energy"] = 10000
	NxEconomyEngine.step(state, defs, DT)
	# core 1000 + generator 1500 x 1.5 = 2250; processor consome 800.
	assert_eq(state.amount("energy"), 10000 + 1000 + 2250 - 800)
	return true


func test_processor_bonus_is_not_transitive() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	var outer := _link(state, defs, CORE, "processor")
	var inner := _link(state, defs, outer, "processor")
	_link(state, defs, inner, "generator")
	state.resources["energy"] = 10000
	NxEconomyEngine.step(state, defs, DT)
	# O gerador só recebe o bônus do pai imediato (x1.5), não x2.25.
	assert_eq(state.amount("energy"), 10000 + 1000 + 2250 - 1600)
	return true


func test_processor_does_not_boost_siblings_or_itself() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	var processor := _link(state, defs, CORE, "processor")
	_link(state, defs, processor, "generator")          # x1.5
	_link(state, defs, CORE, "generator")               # irmão do Processor: x1
	state.resources["energy"] = 10000
	NxEconomyEngine.step(state, defs, DT)
	assert_eq(state.amount("energy"), 10000 + 1000 + 2250 + 1500 - 800)
	return true


func test_disabled_or_disconnected_processor_gives_no_bonus() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	var processor := _link(state, defs, CORE, "processor")
	_link(state, defs, processor, "generator")
	NxNetwork.set_enabled(state, defs, processor, false)
	state.resources["energy"] = 10000
	NxEconomyEngine.step(state, defs, DT)
	assert_eq(state.amount("energy"), 11000, "filho inativo; só o Core produz")
	return true


# --- remoção ---------------------------------------------------------------

func test_remove_refunds_part_of_the_cost_and_orphans_children() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	var relay := _link(state, defs, CORE, "relay")
	var child := _link(state, defs, relay, "generator")
	var result := NxNetwork.remove_component(state, defs, relay)
	assert_true(result.ok)
	assert_eq(result.data["refund"], {"matter": 7500}, "50% de 15")
	assert_eq(state.amount("matter"), 7500)
	assert_false(state.components.has(relay), "instância removida")
	assert_eq(state.components[child]["parent"], 0, "filho fica desconectado")
	assert_eq(NxNetwork.validate(state, defs).size(), 0, "árvore continua válida")
	return true


func test_refund_respects_storage_cap() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	var generator := _link(state, defs, CORE, "generator")
	state.resources["energy"] = 98000
	NxNetwork.remove_component(state, defs, generator)
	assert_eq(state.amount("energy"), 100000, "reembolso de 5 limitado ao máximo")
	return true


func test_core_cannot_be_removed() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	var before := state.state_hash()
	assert_eq(NxNetwork.remove_component(state, defs, CORE).code, "not_removable")
	assert_eq(state.state_hash(), before)
	return true


func test_last_collector_is_protected() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	var first := _link(state, defs, CORE, "collector")
	assert_eq(NxNetwork.remove_component(state, defs, first).code, "last_protected")
	var second := _link(state, defs, CORE, "collector")
	assert_true(NxNetwork.remove_component(state, defs, second).ok, "o segundo pode sair")
	assert_eq(NxNetwork.remove_component(state, defs, first).code, "last_protected", "o último continua protegido")
	assert_eq(state.count_of("collector"), 1)
	return true


func test_remove_unknown_instance() -> bool:
	var defs := Fixtures.defs()
	assert_eq(NxNetwork.remove_component(Fixtures.blank_state(defs), defs, 42).code, "unknown_instance")
	return true


# --- invariantes -----------------------------------------------------------

func test_validate_accepts_a_well_formed_tree() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	var relay := _link(state, defs, CORE, "relay")
	_link(state, defs, relay, "generator")
	assert_eq("\n".join(NxNetwork.validate(state, defs)), "")
	return true


func test_validate_detects_corrupted_trees() -> bool:
	var defs := _defs_with_core_ports(1)
	var state := Fixtures.blank_state(defs)
	var a := _link(state, defs, CORE, "relay")
	var b := _link(state, defs, a, "relay")

	state.components[a]["parent"] = b                   # ciclo a <-> b
	assert_true(NxNetwork.validate(state, defs).size() > 0, "ciclo")
	state.components[a]["parent"] = 77                  # pai inexistente
	assert_true("\n".join(NxNetwork.validate(state, defs)).contains("não existe"), "pai inexistente")
	state.components[a]["parent"] = CORE
	state.components[CORE]["parent"] = a                # Core com pai
	assert_true("\n".join(NxNetwork.validate(state, defs)).contains("Core"), "Core com pai")
	state.components[CORE]["parent"] = 0
	var extra := state.add_component("generator")
	state.components[extra]["parent"] = CORE            # Core tem 1 porta e já tem o relay
	assert_true("\n".join(NxNetwork.validate(state, defs)).contains("portas"), "mais filhos que portas")
	return true


func test_cyclic_data_never_hangs_the_engine_queries() -> bool:
	# Um save corrompido com ciclo não pode travar a consulta de ativos.
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	var a := state.add_component("relay")
	var b := state.add_component("relay")
	state.components[a]["parent"] = b
	state.components[b]["parent"] = a
	var active := NxNetwork.active_ids(state, defs)
	assert_false(active.has(a) or active.has(b), "o ciclo não é alcançável a partir do Core")
	assert_true(NxNetwork.validate(state, defs).size() > 0)
	return true


# --- determinismo ----------------------------------------------------------

func test_result_is_independent_of_instance_ids() -> bool:
	# Mesma topologia, ids atribuídos em ordens diferentes.
	var defs := Fixtures.defs()
	var first := Fixtures.blank_state(defs)
	var g1 := first.add_component("generator")
	var c1 := first.add_component("collector")
	var a1 := first.add_component("analyzer")
	NxNetwork.connect_components(first, defs, CORE, g1)
	NxNetwork.connect_components(first, defs, CORE, c1)
	NxNetwork.connect_components(first, defs, g1, a1)

	var second := Fixtures.blank_state(defs)
	var a2 := second.add_component("analyzer")
	var c2 := second.add_component("collector")
	var g2 := second.add_component("generator")
	NxNetwork.connect_components(second, defs, g2, a2)
	NxNetwork.connect_components(second, defs, CORE, c2)
	NxNetwork.connect_components(second, defs, CORE, g2)

	for state in [first, second]:
		state.resources["energy"] = 5000
		state.resources["matter"] = 30000
		for i in range(150):
			NxEconomyEngine.step(state, defs, DT)
	for rid in defs.resource_ids:
		assert_eq(first.amount(rid), second.amount(rid), "saldo de %s" % rid)
	return true


func test_state_with_network_round_trips() -> bool:
	var defs := Fixtures.defs()
	var state := Fixtures.blank_state(defs)
	var relay := _link(state, defs, CORE, "relay")
	_link(state, defs, relay, "generator")
	var copy := NxGameState.from_dict(state.to_dict())
	assert_eq(copy.state_hash(), state.state_hash(), "parent sobrevive à ida e volta")
	assert_eq(NxNetwork.active_ids(copy, defs).size(), 3)
	return true
