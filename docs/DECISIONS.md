# NEXUS --- Registro de decisões

Este documento registra decisões de produto e questões ainda abertas.

## Decisões aprovadas

  ID      Decisão                                    Estado
  ------- ------------------------------------------ -------------------
  D-001   Gênero idle incremental                    Aprovada
  D-002   Descobertas por condições emergentes       Aprovada
  D-003   Profundidade estratégica média             Aprovada
  D-004   Progresso offline equilibrado e limitado   Aprovada
  D-005   Sessões curtas                             Aprovada
  D-006   Visual minimalista e abstrato              Aprovada
  D-007   Android como plataforma inicial            Aprovada
  D-008   Godot e GDScript                           Aprovada (versão em D-023)
  D-009   Três recursos: Energy, Matter e Data       Aprovada para MVP
  D-010   Seis componentes conceituais               Aprovada para MVP
  D-011   Sem monetização no protótipo               Aprovada
  D-012   Sem backend no MVP                         Aprovada
  D-013   Sem prestígio/reset no MVP                 Aprovada

## Revisão de fluxos (2026-11-23) --- aprovada pelo responsável pelo produto

Origem: revisão técnica da documentação. Problemas corrigidos: o
Collector exigia a produção de Matter para ser desbloqueado, e só ele
produz Matter; a reserva inicial permitia bloqueio irrecuperável;
Analyzer e Processor não tinham desbloqueio; Data não tinha uso; o
offline aplicava eficiência só à produção; o Stage II não tinha
conteúdo.

  ID      Decisão                                                         Resolve pend.   Docs afetados
  ------- --------------------------------------------------------------- --------------- -------------------------------
  D-014   Início livre de bloqueio: Generator custa só Energy; reserva     1, 2            GDD §5, ECONOMY §3, FS FR-01
          de Matter ≥ custo do Collector; último Collector não removível
  D-015   Sequência de descobertas D1--D8 acíclica (GDD §7)               2, 8            GDD §7
  D-016   Recursos em reservatório global; conexão = ativação             3, 9            GDD §6, FS FR-04, ARCH §4
  D-017   Rede em árvore com raiz no Core; portas de saída por            5, 9            GDD §6, ECONOMY §3, FS FR-04
          componente; Relay é hub de portas
  D-018   Alocação por fração uniforme por recurso, na ordem              3, 6            ECONOMY §5, ARCH §6
          Energy → Matter → Data; déficit reduz eficiência
          proporcionalmente
  D-019   Processor multiplica a produção dos filhos diretos (não         7               GDD §6, ECONOMY §3--4
          transitivo); não transforma recursos
  D-020   Energy com armazenamento máximo; Matter e Data sem limite no    4               GDD §4, ECONOMY §9
          MVP
  D-021   Offline: eficiência aplicada ao tempo; mesma função de passo    10              ECONOMY §7, FS §4
          com dt maior; elapsed negativo → 0; automação com limite
  D-022   Data como moeda de melhorias Efficiency/Automation/avançadas;   ---             GDD §7--8
          Stage II no MVP = registro + tela de conclusão

## Decisões técnicas da Fase 0 (2026-11-23)

  ID      Decisão                                                        Estado
  ------- -------------------------------------------------------------- ----------
  D-023   Godot fixado em 4.7.2 estável (binário oficial linux.arm64)    Aprovada
  D-024   Runner de testes próprio (`tests/runner.gd`, SceneTree          Aprovada
          headless) em vez de GUT/gdUnit4: sem dependência externa;
          código de saída 1 em falha, erro de execução, erro de
          sintaxe ou nenhum teste executado
  D-025   Definições de conteúdo em JSON em `data/`, validadas na         Aprovada
          carga (comparáveis no Git, testáveis sem editor, sem
          execução de script embutido como em `.tres`)
  D-026   Renderer GL Compatibility (desktop e mobile), pensando em       Aprovada
          aparelhos Android modestos
  D-027   Arquivos `.uid` gerados pelo Godot são versionados; `.godot/`   Aprovada
          não é

## Correções de fluxo (2026-11-24) --- aprovadas

  ID      Decisão                                                        Docs afetados
  ------- -------------------------------------------------------------- -------------------
  D-028   Taxas usadas em condições e na interface = produção − consumo  GDD §7, ECONOMY §5
          antes do limite de armazenamento. Evita que D2 fique
          bloqueada com Energy no máximo.
  D-029   D6 exige ≥ 1 Collector e ≥ 1 Analyzer ativos com eficiência    GDD §7
          100%. Antes, uma rede só de Generators cumpria a condição.

## Decisões de implementação da Fase 1 (2026-11-24)

  ID      Decisão                                                        Estado
  ------- -------------------------------------------------------------- ----------
  D-030   Quantidades em inteiros (milésimos de unidade) e taxas em       Aprovada
          milésimos por segundo; produção e consumo arredondados para
          baixo, então o motor nunca cria recursos por arredondamento.
          O JSON de `data/` usa unidades "humanas".
  D-031   Cada recurso tem um `tier`; toda saída de um componente deve    Aprovada
          ter tier maior que todas as suas entradas. O validador rejeita
          dados que quebrem a cadeia, impedindo ciclos de geração.
  D-032   Provisório: `start_unlocked` inclui Collector e Analyzer até    Provisória
          a Fase 3, quando D1 e D2 passam a liberá-los
  D-033   Classes de lógica têm prefixo `Nx` (`NxEconomyEngine`...) e     Aprovada
          usam `class_name`; nenhuma depende de nós ou autoloads
  D-034   Valores de `data/` são provisórios. O Collector consome 0.5     Provisória
          de Energy (com 1.0 o saldo líquido de Energy zerava e o
          jogador que o construísse primeiro não pagaria o Generator)

## Decisões de implementação da Fase 2 (2026-11-24)

  ID      Decisão                                                        Estado
  ------- -------------------------------------------------------------- -----------
  D-035   Conexões persistidas como o campo `parent` de cada instância    Aprovada
          (0 = sem pai). Equivale à lista Connection do modelo, e um
          único pai por nó garante a árvore.
  D-036   Ativação: o componente precisa de um caminho de nós            Aprovada
          habilitados até o Core; desabilitar um nó desativa a sua
          sub-árvore. O multiplicador do Processor vale por inteiro
          enquanto ele estiver ativo, sem depender da eficiência dele
          (evita depender de razões de tiers ainda não resolvidos).
  D-037   O Core não pode ser desabilitado. Remover reembolsa            Aprovada
          `removal_refund` do custo, arredondado para baixo e limitado
          pelo armazenamento, e deixa os filhos desconectados.
  D-038   Construir não liga: o componente nasce solto e só opera        Aprovada
          depois de ligado (a interface fará os dois passos juntos)

## Decisões de implementação da Fase 3 (2026-11-24)

  ID      Decisão                                                        Estado
  ------- -------------------------------------------------------------- -----------
  D-039   Descobertas em `data/discoveries/*.json`: condições quantita-   Aprovada
          tivas, estruturais, funcionais (`sustained`) e históricas;
          recompensas `unlock_component`, `unlock_feature`, `set_stage`.
          Todas as condições de uma descoberta valem juntas.
  D-040   O validador exige alcançabilidade: tudo o que uma descoberta    Aprovada
          exige (componentes e recursos produzidos) precisa estar
          disponível no início ou liberado por um pré-requisito dela,
          e os pré-requisitos não podem formar ciclo.
  D-041   `start_unlocked` passa a ser só o Generator (substitui o        Aprovada
          provisório D-032). Collector, Analyzer, Relay e Processor são
          liberados por D1, D2, D3 e D5. D-014 vale também para o que as
          descobertas liberam.
  D-042   Tick completo = economia, depois descobertas (`NxSimulation`).  Aprovada
          Contadores sustentados zeram quando a condição falha e são
          salvos no estado. A automação entra na Fase 4.

## Decisões de implementação da Fase 4 (2026-11-24)

  ID      Decisão                                                        Estado
  ------- -------------------------------------------------------------- -----------
  D-043   Efeitos das melhorias: `output_multiplier` (1 + k × nível) e    Aprovada
          `input_multiplier` (1 − k × nível, consumo mínimo de 10%),
          por componente ou `"all"`, multiplicativos entre si.
  D-044   Curva de custo ceil(base × growth^nível), determinista, com     Aprovada
          tolerância de ruído e teto (implementa ECONOMY §6).
  D-045   Automação = recurso liberado por D6, não uma melhoria; compra   Aprovada
          a melhoria escolhida, no máximo uma por tick, depois das
          descobertas, pelas mesmas regras da compra manual. A categoria
          "Automation" do GDD §8 fica como esse recurso.
  D-046   D2 passa a conceder também `production_upgrades` (alteração     Aprovada
          de dados em `data/discoveries/production_cycle.json`).

## Decisões de implementação da Fase 5 (2026-11-25)

  ID      Decisão                                                        Estado
  ------- -------------------------------------------------------------- -----------
  D-047   Save em JSON `{checksum, payload_json}`; checksum SHA-256 do     Aprovada
          texto do payload; `schema_version` e `game_version` no payload.
  D-048   Escrita atômica (tmp → conferir → girar → publicar) com dois     Aprovada
          backups; main corrompido vai para `save.corrupt.json`; backup
          inválido nunca sobrescreve um válido.
  D-049   Validação estrita ao carregar, sem reparo silencioso (save       Proposta
          inválido cai no backup). Mudança de conteúdo = migração
          explícita. Save de versão mais nova bloqueia o carregamento e
          não é sobrescrito. (Difere da ideia inicial de remover ids
          desconhecidos com log.)
  D-050   Offline: min(ausência, 8 h) × 70% como TEMPO, mesmo tick da      Aprovada
          partida ativa, passos de 60 s; ausência negativa vale 0; >30
          dias é marcada suspeita (o teto já limita o ganho); limite de
          20 compras automáticas por ausência (provisório). Implementa
          D-021.
  D-051   Ao abrir, a sessão salva logo depois do offline; save inválido   Proposta
          ou de versão futura nunca é substituído sem decisão do jogador.
  D-052   Limitação conhecida: o arredondamento para baixo em milésimos    Registro
          no passo ativo de 1 s perde até ~2% sob déficit em taxas
          pequenas (Data a 0,1/s). O offline é mais exato. Saída futura:
          unidade interna menor (micro). Não afeta rede sem déficit.

Risco aberto: o Android SDK oficial não tem build-tools para Linux
arm64, então gerar o APK neste Raspberry Pi pode não ser viável. Avaliar
antes da Fase 6 (opções: outra máquina x86_64 ou CI).

## Parâmetros provisórios

  Parâmetro                  Valor de teste
  ------------------------ ----------------
  Limite offline                    8 horas
  Eficiência offline                    70%
  Sessão pretendida            2--5 minutos
  Estágios no MVP                         2
  Descobertas planejadas                  8

  Portas do Core                          3
  Portas do Relay                         4
  Compras automáticas por ausência      20
  Reembolso na remoção                  50%
  Passo de simulação ativo              1 s
  Passo de simulação offline           60 s

Estes valores podem mudar após testes.

## Pendências

Itens riscados foram resolvidos pelas decisões D-014 a D-022,
aprovadas em 2026-11-23.

1.  Fechar produção e custo inicial de cada componente. *(estrutura
    em D-014; números em aberto)*
2.  ~~Sequência de desbloqueios sem dependências circulares.~~ →
    D-015
3.  ~~Regras de alocação com múltiplos produtores/consumidores.~~ →
    D-018
4.  ~~Armazenamento máximo por recurso.~~ → D-020 (valor em
    aberto)
5.  Limites de componentes e conexões. *(portas em D-017;
    limite total de componentes em aberto)*
6.  ~~Comportamento de componentes sem energia.~~ → D-018
7.  ~~Processor transforma ou altera eficiência.~~ → D-019
8.  Condições e recompensas numéricas das oito descobertas.
    *(estrutura em D-015; valores N e X s em aberto)*
9.  ~~Desconexão e remoção de componentes.~~ → D-016/D-017
10. ~~Horário local alterado durante ausência.~~ → D-021

## Processo de alteração

Qualquer alteração que afete loop, economia, progressão ou arquitetura
deve: 1. Ser descrita. 2. Ter justificativa. 3. Identificar documentos
afetados. 4. Ser aprovada pelo responsável pelo produto. 5. Ser
registrada aqui.
