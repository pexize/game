class_name NxSaveManager
extends RefCounted
## Salvamento local (FR-10, FR-11, ARCHITECTURE §7).
##
## Arquivo: JSON `{"checksum": sha256, "payload_json": "<texto>"}`. O payload é
## guardado como TEXTO e o checksum cobre exatamente esse texto, o que evita
## divergências de formato entre inteiros e decimais ao reler o JSON.
## payload = {schema_version, game_version, saved_at, state}.
##
## Escrita (save):
##   1. valida o estado e grava `save.tmp`, relê e confere;
##   2. se `save.json` for VÁLIDO, gira os backups (bak1 → bak2, main → bak1);
##      se estiver corrompido, move-o para `save.corrupt.json` sem tocar nos
##      backups válidos;
##   3. renomeia `save.tmp` para `save.json`.
## Uma queda entre os passos 2 e 3 deixa o último save bom em `bak1`, que o
## carregamento usa.
##
## Leitura (load_latest): tenta main, bak1 e bak2, nessa ordem, e usa o
## primeiro que passar em formato, checksum, versão e validação do estado.
## Nunca apaga nada ao ler. Um save de versão MAIS NOVA que o jogo não é
## ignorado em favor de um backup antigo (isso perderia progresso): o
## carregamento falha com `version_too_new` e o save recusa sobrescrevê-lo.

const SCHEMA_VERSION := 1
const MAIN := "save.json"
const BACKUPS := ["save.bak1.json", "save.bak2.json"]
const TMP := "save.tmp"
const CORRUPT := "save.corrupt.json"

var dir: String
var game_version: String
## Versão de esquema que este jogo escreve e entende.
var schema_version := SCHEMA_VERSION
## versão de origem (int) -> Callable(payload: Dictionary) -> Dictionary, que leva
## o payload da versão N para a N+1. Devolver {} sinaliza falha.
var migrations := {}
## Callable(path: String, text: String) -> bool que grava um arquivo. Existe para
## os testes simularem disco cheio ou gravação truncada.
var writer: Callable = _write_text


func _init(p_dir: String, p_game_version := "0.1.0") -> void:
	dir = p_dir
	game_version = p_game_version


func path_of(file_name: String) -> String:
	return dir.path_join(file_name)


## Grava o estado. Falhas: invalid_state, newer_save_present, write_failed.
func save(state: NxGameState, defs: NxDefinitions, now_unix: int) -> NxResult:
	var problems := NxStateValidator.validate_state(state, defs)
	if not problems.is_empty():
		return NxResult.failure("invalid_state", "Estado inválido, não salvo: %s" % problems[0])
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return NxResult.failure("write_failed", "Não foi possível criar o diretório de saves.")

	var existing := _read_payload(path_of(MAIN))
	if existing.ok and int(existing.data["payload"]["schema_version"]) > schema_version:
		return NxResult.failure("newer_save_present", "Há um save de uma versão mais nova do jogo; não será sobrescrito.")

	var payload := {
		"schema_version": schema_version, "game_version": game_version,
		"saved_at": now_unix, "state": state.to_dict(),
	}
	var tmp_path := path_of(TMP)
	if not writer.call(tmp_path, _encode(payload)):
		return NxResult.failure("write_failed", "Falha ao gravar o arquivo temporário.")
	if not _read_payload(tmp_path).ok:
		DirAccess.remove_absolute(tmp_path)
		return NxResult.failure("write_failed", "O arquivo temporário não passou na conferência.")

	if not _rotate(defs):
		return NxResult.failure("write_failed", "Falha ao girar os backups.")
	if DirAccess.rename_absolute(tmp_path, path_of(MAIN)) != OK:
		return NxResult.failure("write_failed", "Falha ao publicar o novo save.")
	return NxResult.success({"saved_at": now_unix})


## Sucesso: data = {state, saved_at, source ("main"|"backup1"|"backup2"),
## recovered (usou backup), skipped: [{file, code}]}. Falhas: no_save (nada
## no disco), version_too_new, all_invalid (há arquivos, nenhum utilizável).
func load_latest(defs: NxDefinitions) -> NxResult:
	var skipped := []
	var candidates := [[MAIN, "main"], [BACKUPS[0], "backup1"], [BACKUPS[1], "backup2"]]
	for candidate: Array in candidates:
		var file_name: String = candidate[0]
		if not FileAccess.file_exists(path_of(file_name)):
			continue
		var loaded := _load_file(path_of(file_name), defs)
		if loaded.ok:
			loaded.data["source"] = candidate[1]
			loaded.data["recovered"] = candidate[1] != "main"
			loaded.data["skipped"] = skipped
			return loaded
		if loaded.code == "version_too_new":
			return loaded
		skipped.append({"file": file_name, "code": loaded.code, "message": loaded.message})
	if skipped.is_empty():
		return NxResult.failure("no_save", "Nenhum save encontrado.")
	var failure := NxResult.failure("all_invalid", "Nenhum save utilizável (%d arquivo(s) inválido(s))." % skipped.size())
	failure.data = {"skipped": skipped}
	return failure


# --- leitura -----------------------------------------------------------------

func _load_file(path: String, defs: NxDefinitions) -> NxResult:
	var read := _read_payload(path)
	if not read.ok:
		return read
	var payload: Dictionary = read.data["payload"]
	var on_disk := int(payload["schema_version"])
	if on_disk > schema_version:
		return NxResult.failure("version_too_new", "O save é da versão %d, mais nova que a %d deste jogo." % [on_disk, schema_version])

	var version := on_disk
	while version < schema_version:
		if not migrations.has(version):
			return NxResult.failure("no_migration", "Não há migração da versão %d para a %d." % [version, version + 1])
		var migrated: Variant = (migrations[version] as Callable).call(payload.duplicate(true))
		if not (migrated is Dictionary) or migrated.is_empty():
			return NxResult.failure("migration_failed", "A migração da versão %d falhou." % version)
		payload = migrated
		version += 1
		payload["schema_version"] = version

	var problems := NxStateValidator.validate_dict(payload.get("state"), defs)
	if not problems.is_empty():
		return NxResult.failure("invalid_state", "Estado inválido: %s" % problems[0])
	return NxResult.success({
		"state": NxGameState.from_dict(payload["state"]),
		"saved_at": int(payload["saved_at"]),
		"game_version": str(payload.get("game_version", "")),
		"schema_version_on_disk": on_disk,
	})


## Lê e confere formato e checksum; não olha versão nem estado.
## Falhas: missing, unreadable, bad_format, checksum.
func _read_payload(path: String) -> NxResult:
	if not FileAccess.file_exists(path):
		return NxResult.failure("missing", "Arquivo inexistente.")
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return NxResult.failure("unreadable", "Arquivo vazio ou ilegível.")
	var outer := JSON.new()
	if outer.parse(text) != OK or not (outer.data is Dictionary):
		return NxResult.failure("bad_format", "O arquivo não é um JSON válido.")
	var checksum: Variant = outer.data.get("checksum")
	var payload_json: Variant = outer.data.get("payload_json")
	if not (checksum is String and payload_json is String):
		return NxResult.failure("bad_format", "Faltam campos obrigatórios.")
	if payload_json.sha256_text() != checksum:
		return NxResult.failure("checksum", "O conteúdo não confere com o checksum (arquivo alterado ou truncado).")
	var inner := JSON.new()
	if inner.parse(payload_json) != OK or not (inner.data is Dictionary):
		return NxResult.failure("bad_format", "O conteúdo não é um JSON válido.")
	var version: Variant = inner.data.get("schema_version")
	if not (version is float or version is int) or float(version) != floorf(float(version)) or version < 1:
		return NxResult.failure("bad_format", "Versão de esquema inválida.")
	if not (inner.data.get("saved_at") is float or inner.data.get("saved_at") is int):
		return NxResult.failure("bad_format", "Falta a data do save.")
	return NxResult.success({"payload": inner.data})


# --- escrita -----------------------------------------------------------------

static func _encode(payload: Dictionary) -> String:
	var payload_json := JSON.stringify(payload, "", true)
	return JSON.stringify({"checksum": payload_json.sha256_text(), "payload_json": payload_json})


static func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	var ok := file.get_error() == OK
	file.close()
	return ok


## Gira os backups sem nunca sobrescrever um backup válido com lixo.
func _rotate(defs: NxDefinitions) -> bool:
	var main_path := path_of(MAIN)
	if not FileAccess.file_exists(main_path):
		return true
	if _load_file(main_path, defs).ok:
		var bak1 := path_of(BACKUPS[0])
		if FileAccess.file_exists(bak1) and _load_file(bak1, defs).ok:
			if DirAccess.rename_absolute(bak1, path_of(BACKUPS[1])) != OK:
				return false
		return DirAccess.rename_absolute(main_path, bak1) == OK
	# main corrompido: guarda à parte e deixa os backups como estão.
	return DirAccess.rename_absolute(main_path, path_of(CORRUPT)) == OK
