# NEXUS --- Documentação do projeto

**Versão:** 1.0\
**Status:** Fases 0 a 5 (lógica completa: economia, rede, descobertas, melhorias, automação, save e offline) concluídas; Fase 6 (interface mobile) a seguir\
**Plataforma-alvo:** Android\
**Engine:** Godot 4.7.2 / GDScript\
**Modelo:** Idle incremental com descoberta por condições emergentes

## Documentos

| Arquivo                   | Finalidade                                   |
| ------------------------- | -------------------------------------------- |
| `docs/VISION.md`          | Visão, proposta de valor e princípios        |
| `docs/GDD.md`             | Documento de design do jogo                  |
| `docs/FUNCTIONAL_SPEC.md` | Requisitos funcionais e critérios de aceitação |
| `docs/ECONOMY.md`         | Recursos, produção, custos e balanceamento   |
| `docs/ARCHITECTURE.md`    | Arquitetura técnica e modelo de dados        |
| `docs/ROADMAP.md`         | Fases de desenvolvimento e entregas          |
| `docs/DECISIONS.md`       | Registro de decisões e pendências            |
| `CLAUDE.md`               | Instruções de trabalho para Claude           |

## Requisitos

- Godot **4.7.2** (versão fixada em D-023). Nesta máquina:
  `~/bin/godot` → `~/bin/godot-4.7.2/Godot_v4.7.2-stable_linux.arm64`.
- Outro binário pode ser usado com a variável `GODOT=/caminho/para/godot`.

## Comandos

```sh
# Rodar todos os testes (importa o projeto e executa o runner headless)
tools/run_tests.sh

# Smoke test: executa a cena principal por 300 frames e procura erros no log
tools/smoke.sh

# Simular a economia sem interface (CSV em stdout)
tools/simulate.sh --steps=300 --every=20
tools/simulate.sh --steps=900 --every=300 --auto=generator_output   # com automação

# Abrir o editor
~/bin/godot --path . -e
```

`tools/run_tests.sh` termina com código 0 somente se todos os testes
passarem.

## Estrutura

```text
NEXUS/
├── project.godot
├── docs/            documentação de produto e engenharia
├── scenes/main/     cena principal (placeholder na Fase 0)
├── scripts/         lógica do jogo (sem dependência de interface)
├── data/            definições de conteúdo em JSON
├── tests/           runner headless e testes
└── tools/           scripts de linha de comando
```

Diretórios de módulos são criados quando a fase correspondente começa,
para não manter pastas vazias.

## Processo

1. Cada fase é aprovada pelo responsável pelo produto antes de começar.
2. Mudanças de economia, progressão ou arquitetura são registradas em
   `docs/DECISIONS.md`.
3. Valores econômicos permanecem configuráveis até a calibração.
