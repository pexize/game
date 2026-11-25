# NEXUS --- Especificação funcional

**Versão:** 1.0\
**Status:** Base para revisão técnica e prototipagem

## 1. Objetivo

Definir o comportamento observável da primeira versão jogável de NEXUS.

## 2. Requisitos funcionais

### FR-01 --- Inicialização

O jogo deve iniciar uma nova partida com Core, Energy inicial, Generator
desbloqueado e reserva de Matter maior ou igual ao custo do primeiro
Collector.

### FR-02 --- Recursos

O sistema deve manter saldo, produção, consumo e taxa líquida de cada
recurso. Saldos não podem ficar negativos.

### FR-03 --- Construção

O jogador pode construir componentes quando: - O componente estiver
desbloqueado. - Os custos forem atendidos. - Os limites de construção,
se houver, forem respeitados.

A operação deve ser atômica: ou todos os custos são debitados e a
construção ocorre, ou nada muda.

### FR-04 --- Conexões

O jogador pode criar e remover conexões válidas. Conexões incompatíveis
devem ser rejeitadas com feedback compreensível.

Uma conexão é válida quando:

-   o destino não é o Core e ainda não tem pai;
-   a origem tem porta de saída livre;
-   o destino não é ancestral da origem (sem ciclos).

Apenas componentes alcançáveis a partir do Core e habilitados ficam
ativos. Desconectar um componente desativa toda a sua sub-árvore.

### FR-05 --- Simulação

O motor calcula produção e consumo em intervalos controlados. A
simulação deve ser determinística para o mesmo estado e sequência de
ações, e o resultado não pode depender da ordem dos componentes. A
alocação segue `ECONOMY.md` §5.

### FR-06 --- Descobertas

O sistema verifica condições de descoberta e concede cada descoberta uma
única vez. A verificação deve ocorrer após eventos relevantes e/ou em
ciclos definidos, sem depender da tela Discoveries estar aberta.

### FR-07 --- Melhorias

O jogador pode adquirir melhorias disponíveis. O sistema deve validar
recursos, pré-requisitos e limite de nível.

### FR-08 --- Automação

Após desbloqueada, a automação executa a compra da melhoria selecionada
quando os requisitos forem satisfeitos. O jogador pode ativá-la ou
desativá-la.

### FR-09 --- Progresso offline

Ao retornar, o jogo calcula o período elegível de ausência, aplica o
limite e a eficiência offline configurados e atualiza o estado sem criar
recursos negativos.

### FR-10 --- Salvamento

O jogo salva automaticamente e preserva recursos, componentes, conexões,
descobertas, melhorias, estatísticas necessárias e timestamp.

### FR-11 --- Recuperação

O jogo deve validar o save e tentar recuperar backup válido se o arquivo
principal estiver corrompido. Detalhes: `ARCHITECTURE.md` §7. Um save de
versão mais nova que o jogo nunca é substituído por um backup antigo nem
sobrescrito.

### FR-12 --- Interface

A interface deve apresentar estado atual, taxas de produção, ações
disponíveis, custos, descobertas e feedback de operações.

## 3. Regras de negócio

1.  O Core não pode ser removido. O último Collector também não.
2.  Nenhum recurso pode assumir saldo negativo.
3.  Uma descoberta não pode ser concedida duas vezes.
4.  Uma compra não pode ocorrer parcialmente.
5.  Componentes desconectados ou desabilitados ficam inativos: não
    produzem, não consomem e não contam como ativos em condições.
5a. Remover um componente reembolsa a porcentagem configurada do custo;
    os filhos ficam desconectados.
5b. Falta de insumo reduz a eficiência proporcionalmente; o componente
    não desliga.
6.  A interface não altera diretamente o estado econômico.
7.  A simulação não pode criar recursos por ciclos de dependência.
8.  A passagem de estágio não apaga o progresso.
9.  O jogo não depende de conexão com servidor.
10. Os parâmetros de economia devem ser configuráveis.

## 4. Progresso offline

Parâmetros iniciais de teste: - Limite: 8 horas. - Eficiência: 70%.

Fórmulas de referência:

`simulated_time = min(max(elapsed_time, 0), offline_cap) × offline_efficiency`

(O limite de compras automáticas por ausência e a marcação de ausência
suspeita estão em `ECONOMY.md` §7.)

O estado é avançado por `simulated_time` usando a mesma função de passo
da partida ativa, com passo maior (`ECONOMY.md` §7). A eficiência se
aplica ao tempo, de modo que produção e consumo são reduzidos na mesma
proporção. Descobertas, contadores de condições e automação (com limite
de compras) continuam funcionando durante esse cálculo.

Sem servidor, a manipulação do relógio local não pode ser impedida de
forma absoluta. O MVP deve detectar valores claramente inválidos,
limitar o ganho e manter o save consistente, sem prometer antifraude
robusto.

## 5. Requisitos não funcionais

-   Android como alvo inicial.
-   Compatibilidade com aparelhos modestos.
-   Interface em orientação retrato.
-   Código modular e testável.
-   Persistência local.
-   Baixo consumo de memória e CPU.
-   Sem dependência de rede para o loop principal.
-   Estrutura preparada para localização.
-   Tratamento de interrupção, suspensão e retomada do aplicativo.

## 6. Critérios de aceitação

-   [ ] Uma nova partida inicia em estado válido.
-   [ ] Construções respeitam custos e desbloqueios.
-   [ ] Produção e consumo são calculados corretamente.
-   [ ] Conexões inválidas são rejeitadas.
-   [ ] Componentes desconectados seguem as regras definidas.
-   [ ] Descobertas são verificadas automaticamente.
-   [ ] Descobertas não são repetidas.
-   [ ] Melhorias alteram efetivamente o sistema.
-   [ ] Automação respeita recursos e configuração.
-   [ ] Progresso offline respeita limite e eficiência.
-   [ ] O save preserva a configuração da rede.
-   [ ] Save corrompido não elimina automaticamente o backup.
-   [ ] O jogo retoma sem perda de progresso após fechamento normal.
-   [ ] Interface funciona em resoluções Android suportadas.
