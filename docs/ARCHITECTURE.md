# NEXUS --- Arquitetura técnica

**Versão:** 1.0\
**Stack:** Godot / GDScript

## 1. Princípios

-   Separar lógica do jogo e apresentação.
-   Manter economia determinística.
-   Configurar conteúdo por dados.
-   Evitar dependências circulares entre módulos.
-   Persistir estado com versão de esquema.
-   Testar regras sem precisar executar a interface.
-   Não adicionar backend no MVP.

## 2. Módulos

  Módulo              Responsabilidade
  ------------------- --------------------------------------
  GameManager         Coordena estado e ciclo da partida
  EconomyEngine       Resolve produção, consumo e alocação
  ResourceManager     Mantém saldos e transações
  NetworkManager      Componentes, nós e conectividade
  DiscoveryManager    Avalia e registra condições
  UpgradeManager      Compra e aplicação de melhorias
  AutomationManager   Regras automáticas desbloqueadas
  OfflineCalculator   Calcula progresso de ausência
  SaveManager         Serialização, validação e backup

## 3. Estrutura de diretórios sugerida

``` text
NEXUS/
├── CLAUDE.md
├── project.godot
├── docs/
├── scenes/
│   ├── main/
│   ├── dashboard/
│   ├── network/
│   ├── discoveries/
│   └── components/
├── scripts/
│   ├── core/
│   ├── economy/
│   ├── network/
│   ├── progression/
│   ├── automation/
│   ├── offline/
│   └── save/
├── data/
│   ├── resources/
│   ├── components/
│   ├── discoveries/
│   └── upgrades/
├── assets/
├── localization/
├── tests/
│   ├── runner.gd        runner headless (D-024)
│   ├── framework/       base das suítes e asserts
│   ├── unit/            suítes test_*.gd
│   └── output/          logs (ignorado no Git)
└── tools/
    ├── run_tests.sh     importa o projeto e roda os testes
    └── smoke.sh         executa a cena principal e procura erros
```

Diretórios são criados quando a fase correspondente começa. Arquivos
`.uid` gerados pelo Godot são versionados (D-027).

## 4. Modelo de dados conceitual

### ResourceDefinition

-   id
-   display_name_key
-   icon_key
-   maximum_storage (opcional)

### ComponentDefinition

-   id
-   display_name_key
-   construction_costs `{resource_id: qty}`
-   input_rates `{resource_id: rate}` (inclui Energy; não há campo
    separado de consumo de energia)
-   output_rates `{resource_id: rate}`
-   output_ports
-   child_multiplier (Processor; 1 para os demais)
-   removable / protect_last (Core; Collector)
-   build_limit (opcional)

O desbloqueio de componentes é definido nas recompensas de
DiscoveryDefinition, e não na própria definição, para manter uma única
fonte de verdade.

### ComponentInstance

-   instance_id
-   definition_id
-   level
-   enabled
-   position (layout da tela Network)

### Connection

-   id
-   parent_instance_id
-   child_instance_id

Cada filho tem no máximo uma conexão de entrada, o que torna a rede uma
árvore com raiz no Core. As listas de conexões de cada instância são
derivadas, e não persistidas.

### DiscoveryDefinition

-   id
-   title_key
-   hint_key
-   conditions
-   prerequisites
-   rewards
-   visibility_rule

### SaveData

-   schema_version
-   game_version
-   saved_at (unix)
-   resources
-   component_instances
-   connections
-   next_instance_id
-   unlocked_components
-   discoveries `{id: {order, time}}`
-   condition_progress (contadores de condições temporais)
-   purchased_upgrades `{id: level}`
-   automation_settings
-   statistics (totais acumulados por recurso)
-   stage

## 5. Eventos

Eventos internos possíveis: - resource_changed - component_built -
component_removed - connection_created - connection_removed -
upgrade_purchased - discovery_unlocked - stage_changed - save_completed

Eventos devem ser usados para desacoplar interface e sistemas, sem
transformar o EventBus em dependência global indiscriminada.

## 6. Simulação

Usar passo fixo e lógica independente de FPS. A interface pode atualizar
em frequência diferente da simulação.

Ordem do passo: ativação → resolução de recursos (Energy, Matter,
Data) → aplicação conjunta → estatísticas → contadores de condição →
descobertas → automação. O algoritmo está em `ECONOMY.md` §5. O
progresso offline reutiliza a mesma função de passo, com `dt` maior.

As recompensas de descobertas são aplicadas como mudanças de dados no
estado (desbloqueios, flags), e não como chamadas entre managers, o que
evita dependências circulares entre módulos.

A economia deve possuir uma única autoridade sobre alterações de
recursos. A interface solicita ações e apresenta resultados.

## 7. Salvamento

-   JSON local inicialmente.
-   Campo `schema_version`.
-   Validação de dados na leitura.
-   Escrita atômica sempre que possível.
-   Backup rotativo.
-   Migrações explícitas entre versões.
-   Não salvar referências transitórias de nós da cena.

## 8. Testabilidade

Testar sem interface: - Produção e consumo. - Transações de
construção. - Conectividade. - Condições de descoberta. - Compras e
melhorias. - Automação. - Progresso offline. - Serialização, leitura,
migração e recuperação.

## 9. Riscos técnicos

1.  Ciclos no grafo podem criar recursos indevidos.
2.  Simulação offline longa pode ser cara se avançar segundo a segundo.
3.  Dados de save podem ficar incompatíveis após atualizações.
4.  Excesso de nós visuais pode prejudicar aparelhos modestos.
5.  Relógio local pode ser manipulado.

Mitigações devem ser proporcionais ao MVP. Não construir infraestrutura
de servidor para resolver riscos que ainda não justificam esse custo.
