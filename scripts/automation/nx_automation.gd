class_name NxAutomation
extends RefCounted
## Primeira automação (GDD §10, FR-08): comprar sozinha a melhoria escolhida
## quando houver recursos. Exige o recurso "automation" (descoberta D6) e
## pode ser ligada, desligada e trocada pelo jogador.
##
## No máximo uma compra por tick. Compra pelo mesmo NxUpgradeService do
## jogador, então valida custo, bloqueio, pré-requisitos e nível máximo do
## mesmo jeito, e nunca deixa saldo negativo.

const FEATURE := "automation"


static func configure(state: NxGameState, defs: NxDefinitions, enabled: bool, target: String) -> NxResult:
	if not state.has_feature(FEATURE):
		return NxResult.failure("locked", "A automação ainda não foi desbloqueada.")
	if not target.is_empty() and not defs.upgrades.has(target):
		return NxResult.failure("unknown_upgrade", "Melhoria desconhecida: %s" % target)
	state.automation = {"enabled": enabled, "target": target}
	return NxResult.success()


## Roda no fim do tick. Devolve as compras feitas: [{"id": String, "level": int}].
static func run(state: NxGameState, defs: NxDefinitions) -> Array:
	var bought := []
	if not state.has_feature(FEATURE):
		return bought
	if not bool(state.automation.get("enabled", false)):
		return bought
	var target := str(state.automation.get("target", ""))
	if target.is_empty() or not defs.upgrades.has(target):
		return bought
	var result := NxUpgradeService.purchase(state, defs, target)
	if result.ok:
		bought.append({"id": target, "level": result.data["level"]})
	return bought
