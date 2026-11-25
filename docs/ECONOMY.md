# NEXUS --- Economia e balanceamento

**Versão:** 1.0\
**Status:** Modelo conceitual; parâmetros ainda não calibrados

## 1. Objetivo

Definir uma economia compreensível, configurável e livre de ciclos que
gerem recursos sem custo.

## 2. Recursos

  Recurso   Função               Fontes
  --------- -------------------- -----------------
  Energy    Operação             Core, Generator
  Matter    Construção           Collector
  Data      Descoberta/análise   Analyzer

## 3. Componentes e economia

  Componente   Custo de construção   Consumo contínuo   Saídas / efeito                          Portas de saída
  ------------ --------------------- ------------------ ---------------------------------------- ---------------
  Core         ---                   Nenhum             Energy                                   3
  Generator    Energy                Nenhum             Energy                                   1
  Collector    Matter                Energy             Matter                                   1
  Analyzer     Matter                Energy, Matter     Data                                     1
  Relay        Matter                Energy             Portas extras                            4
  Processor    Matter + Data         Energy             × produção dos filhos diretos (não       2
                                                        transitivo)

Portas e custos são valores iniciais de teste. Os valores concretos de
custo, produção e consumo residem em arquivos de dados, não em scripts
de interface.

Restrições que tornam o início livre de bloqueio (D-014):

-   O Generator nunca custa Matter.
-   Nenhum componente que custa Matter, exceto o Collector, é
    desbloqueado antes de existir um Collector.
-   A reserva inicial de Matter é maior ou igual ao custo do Collector.
-   O último Collector não pode ser removido.

### Fluxo de recursos

Os recursos formam uma cadeia acíclica, e cada recurso só depende dos
anteriores:

``` text
Energy ─► Matter ─► Data
   └───────────────►┘
```

Nenhum componente consome um recurso que ele próprio, direta ou
indiretamente, produz. O carregador de dados deve rejeitar definições
que quebrem essa ordem. Isso elimina, por construção, ciclos que criem
recursos gratuitamente. O Processor não transforma recursos, só
multiplica produção, e por isso não altera a cadeia (D-019).

## 4. Produção

Modelo conceitual:

`effective_output = base_output × upgrade_multiplier × processor_multiplier × operational_efficiency`

-   `operational_efficiency` vem da alocação de insumos (§5). É 0 para
    componentes inativos (desconectados ou desabilitados).
-   `processor_multiplier` vem apenas do pai direto, se ele for um
    Processor ativo; caso contrário vale 1.
-   O consumo também é escalado por `operational_efficiency`: um
    componente a 60% consome 60% e produz 60%.

## 5. Estratégia de simulação

Passo fixo `dt` (valor inicial de teste: 1 s). Cada passo:

1.  **Ativação:** calcular o conjunto de componentes ativos (alcançáveis
    a partir do Core e habilitados).
2.  **Resolver os recursos na ordem da cadeia** (Energy, Matter, Data).
    Para cada recurso R:
    -   `disponível(R) = saldo_inicial(R) + produção(R)` neste passo;
        a produção de R já é conhecida, porque depende só de recursos
        anteriores na cadeia.
    -   `demanda(R) = Σ consumo nominal de R` dos consumidores ativos.
    -   `ratio(R) = min(1, disponível(R) / demanda(R))`; vale 1 se a
        demanda for 0.
    -   **Todos os consumidores de R recebem a mesma fração**
        `ratio(R)`.
3.  **Eficiência:** cada componente opera com
    `min(ratio(R))` sobre todos os seus insumos. Ela escala o seu
    consumo e a sua produção.
4.  **Aplicar** todos os débitos e créditos de uma só vez e limitar
    cada saldo a `[0, max_storage]`.
5.  **Pós-passo:** atualizar estatísticas acumuladas, contadores de
    condições, descobertas e automação, nesta ordem.

O relatório do passo guarda produção e consumo **antes** do limite de
armazenamento, e também a perda por limite. Condições de descoberta e a
taxa líquida exibida usam produção − consumo (D-028); a perda por
limite é exibida à parte.

Propriedades garantidas e testadas:

-   **Independência de ordem:** como todos os consumidores de um recurso
    recebem a mesma fração, embaralhar a ordem dos nós produz estado
    idêntico.
-   **Sem saldo negativo:** o consumo nunca excede `disponível(R)`.
-   **Conservação:** variação do saldo = produção − consumo − perda
    por limite de armazenamento.

Simplificação aceita: se um componente fica limitado por um insumo, a
parte não usada dos outros insumos permanece no saldo e não é
redistribuída no mesmo passo.

## 6. Custos crescentes

Para melhorias repetíveis:

`cost(level) = base_cost × growth_factor ^ level`

Arredondamento, limites numéricos e comportamento para níveis altos
devem ser definidos no código econômico e testados.

## 7. Progresso offline

Parâmetros iniciais de teste: - Capacidade: 8 horas. - Eficiência: 70%.

Estes são valores provisórios de design, não valores comprovadamente
ideais.

O cálculo deve respeitar dependências, disponibilidade de recursos,
desbloqueios e automações. Não presumir que a taxa exibida no momento de
fechar o jogo permanecerá constante durante toda a ausência.

### Algoritmo (D-021)

1.  `elapsed = agora − saved_at`. Se `elapsed < 0`, usar 0 e atualizar
    a referência de tempo.
2.  `tempo_simulado = min(elapsed, cap) × eficiência_offline`. A
    eficiência se aplica ao **tempo**, e não só à produção. Assim,
    produção e consumo são reduzidos igualmente e a taxa líquida nunca
    fica negativa por causa do offline.
3.  Executar a **mesma função de passo** da partida ativa com
    `dt_offline` maior (valor inicial de teste: 60 s; 8 h × 70% ≈ 336
    passos).
4.  Descobertas, contadores e automação rodam a cada passo, como na
    partida ativa. A automação offline tem limite de compras por
    ausência (valor configurável).
5.  Gerar o resumo offline a partir da diferença entre os estados
    inicial e final.

Teste de convergência: o resultado com `dt_offline = 60 s` deve ficar a
menos de 1% do resultado com `dt = 1 s` em cenários de referência.

## 8. Princípios de balanceamento

-   O jogador deve sempre ter uma ação útil ou uma pista compreensível.
-   Nenhuma escolha inicial deve causar bloqueio irrecuperável.
-   Cada componente deve ter utilidade identificável.
-   Novas descobertas devem mudar possibilidades.
-   O custo de uma melhoria deve ser comparável ao benefício percebido.
-   O progresso não deve depender de sessões longas.
-   A progressão offline não deve tornar a interação ativa irrelevante.

## 9. Dados ainda necessários

Antes de fechar a economia:

-   Produção inicial do Core.
-   Custo (em Energy) e produção do Generator.
-   Reserva inicial de Matter (≥ custo do Collector).
-   Custo e produção do Collector.
-   Consumo do Processor e do Analyzer; multiplicador do Processor.
-   Custo, consumo e portas do Relay; portas do Core.
-   Capacidade máxima de Energy.
-   Percentual de reembolso na remoção.
-   Curvas de custo das melhorias (Matter e Data).
-   Valores N e X s das oito descobertas.
-   Limite de compras automáticas por ausência.

Criar uma planilha ou tabela de simulação e testar gargalos antes de
congelar esses parâmetros.
