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
  D-008   Godot e GDScript                           Proposta técnica
  D-009   Três recursos: Energy, Matter e Data       Aprovada para MVP
  D-010   Seis componentes conceituais               Aprovada para MVP
  D-011   Sem monetização no protótipo               Aprovada
  D-012   Sem backend no MVP                         Aprovada
  D-013   Sem prestígio/reset no MVP                 Aprovada

## Revisão de fluxos (2026-11-23) --- propostas aguardando aprovação

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
  Reembolso na remoção                  50%
  Passo de simulação ativo              1 s
  Passo de simulação offline           60 s

Estes valores podem mudar após testes.

## Pendências

Itens resolvidos por proposta (D-014 a D-022) ficam como "proposto"
até aprovação.

1.  Fechar produção e custo inicial de cada componente. *(estrutura
    proposta em D-014; números em aberto)*
2.  ~~Sequência de desbloqueios sem dependências circulares.~~ →
    proposto D-015
3.  ~~Regras de alocação com múltiplos produtores/consumidores.~~ →
    proposto D-018
4.  ~~Armazenamento máximo por recurso.~~ → proposto D-020 (valor em
    aberto)
5.  Limites de componentes e conexões. *(portas propostas em D-017;
    limite total de componentes em aberto)*
6.  ~~Comportamento de componentes sem energia.~~ → proposto D-018
7.  ~~Processor transforma ou altera eficiência.~~ → proposto D-019
8.  Condições e recompensas numéricas das oito descobertas.
    *(estrutura em D-015; valores N e X s em aberto)*
9.  ~~Desconexão e remoção de componentes.~~ → proposto D-016/D-017
10. ~~Horário local alterado durante ausência.~~ → proposto D-021

## Processo de alteração

Qualquer alteração que afete loop, economia, progressão ou arquitetura
deve: 1. Ser descrita. 2. Ter justificativa. 3. Identificar documentos
afetados. 4. Ser aprovada pelo responsável pelo produto. 5. Ser
registrada aqui.
