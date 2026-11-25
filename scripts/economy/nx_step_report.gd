class_name NxStepReport
extends RefCounted
## Resultado de um passo de simulação. Produção e consumo são medidos
## antes do limite de armazenamento (D-028); a perda por limite vem à parte.

var dt_ms := 0
## id do recurso -> milli produzidos / consumidos / perdidos por limite neste passo
var produced := {}
var consumed := {}
var lost := {}
## id do recurso -> fração atendida da demanda (0..1)
var ratios := {}
## instance_id -> eficiência operacional (0..1) dos componentes ativos
var efficiency := {}


## Taxa líquida em milésimos por segundo (produção − consumo).
func net_rate(resource_id: String) -> float:
	if dt_ms <= 0:
		return 0.0
	return float(int(produced.get(resource_id, 0)) - int(consumed.get(resource_id, 0))) * 1000.0 / float(dt_ms)
