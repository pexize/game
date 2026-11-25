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

### Unidades e dados (D-030, D-031)

-   Internamente, quantidades são inteiros em milésimos e taxas em
    milésimos por segundo. Os arquivos em `data/` usam unidades
    "humanas" (`10` = dez unidades, `0.5` = meia unidade por segundo).
-   Cada recurso tem um `tier` (Energy 0, Matter 1, Data 2). O motor
    resolve os recursos nessa ordem, e o validador exige que a saída de
    um componente tenha tier maior que todas as suas entradas.
-   O validador também verifica o início sem bloqueio (D-014): todo
    componente liberado no início precisa ser construível por reserva
    inicial ou por produção de algo construível.

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

`cost(level) = ceil(base_cost × growth_factor ^ level)`

`level` é o nível atual (0 = custo do primeiro nível), e cada recurso do
custo segue a sua própria curva. Regras implementadas (D-044):

-   A potência é feita por multiplicações repetidas em ponto flutuante,
    que são deterministas em qualquer arquitetura (`pow` não é).
-   Arredonda para cima, com tolerância de 1e-6 em milésimos: ruído de
    ponto flutuante (3000 × 1,1 = 3300.0000000000005) não custa uma
    unidade a mais.
-   Satura em 9e15 milésimos (abaixo de 2^53, exato em ponto
    flutuante); nada estoura nem fica negativo.
-   Validação na carga: `1 ≤ growth ≤ 10` e `1 ≤ max_level ≤ 100`.

### Efeito das melhorias (D-043)

-   `output_multiplier` (categoria Production): produção do alvo ×
    `(1 + per_level × nível)`. Alvo: um componente ou `"all"` (inclui o
    Core). Melhorias diferentes se multiplicam entre si e com o bônus do
    Processor.
-   `input_multiplier` (categoria Efficiency): consumo do alvo ×
    `(1 − per_level × nível)`, nunca abaixo de 10% (validado). Reduz a
    demanda sem reduzir a produção.
-   Production custa Matter; Efficiency e as avançadas custam Data
    (D-022). Cada melhoria exige os recursos de jogo (`unlock_feature`)
    concedidos por descobertas.

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

Limite de compras automáticas por ausência: `offline_auto_purchase_limit`
(valor de teste: 20). Ao atingi-lo, a automação não compra mais até o fim
do cálculo, mas o resto da economia continua.

Relógio: ausência negativa vale 0 (sem ganho); o teto de 8 h limita
qualquer avanço de relógio; ausência acima de 30 dias é marcada como
suspeita para a interface decidir o que mostrar. Não há antifraude.

Precisão (medida em `tests/unit/test_offline.gd`): em rede sem déficit o
passo de 60 s dá o mesmo resultado que o de 1 s (diferença 0%). Com
déficit, o offline fica a ~0,02% do valor analítico. O passo ATIVO de 1 s
é que perde precisão: arredondar para baixo em milésimos (D-030) tira até
1 milésimo por componente por passo, o que chega a ~2% em taxas pequenas
com eficiência fracionária (Data a 0,1/s). Sempre para baixo, nunca cria
recursos; registrado como limitação conhecida (D-052).

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
