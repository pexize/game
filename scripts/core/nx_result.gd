class_name NxResult
extends RefCounted
## Resultado de uma ação de jogo (construir, comprar, conectar...).
## A interface usa `code` para escolher a mensagem e `data` para detalhes.

var ok := false
var code := ""
var message := ""
var data := {}


static func success(p_data: Dictionary = {}) -> NxResult:
	var result := NxResult.new()
	result.ok = true
	result.data = p_data
	return result


static func failure(p_code: String, p_message: String) -> NxResult:
	var result := NxResult.new()
	result.code = p_code
	result.message = p_message
	return result
