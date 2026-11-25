class_name NxOfflineReport
extends RefCounted
## Resumo do que aconteceu durante a ausência (alimenta a janela Offline Summary).

## Ausência real, em segundos (pode ser negativa se o relógio andou para trás).
var elapsed_s := 0.0
## Tempo realmente simulado, em ms: min(ausência, limite) × eficiência offline.
var simulated_ms := 0
var steps := 0
## A ausência passou do limite e foi cortada.
var capped := false
## O relógio andou para trás: nenhum ganho é concedido.
var clock_went_back := false
## Ausência claramente inválida (relógio adiantado em semanas, por exemplo). O ganho
## continua limitado pelo teto; o aviso serve para a interface decidir o que mostrar.
var suspicious := false
## id do recurso -> variação do saldo (milli; negativa se a automação gastou mais do que entrou)
var resource_delta := {}
## id do recurso -> quanto foi produzido (milli, antes do limite de armazenamento)
var produced := {}
## ids das descobertas concedidas durante a ausência, em ordem
var discoveries: Array = []
## id da melhoria -> compras automáticas feitas
var purchases := {}
## O limite de compras automáticas da ausência foi atingido.
var purchase_limit_reached := false
