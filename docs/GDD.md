# NEXUS --- Game Design Document

**Versão:** 1.0

## 1. Conceito

Idle incremental de construção de redes e descoberta emergente. O
jogador começa com um Core e desenvolve um sistema de componentes
interdependentes.

## 2. Decisões de design consolidadas

  Dimensão                   Decisão
  -------------------------- ---------------------------
  Descoberta                 Por condições emergentes
  Profundidade estratégica   Média
  Progresso offline          Equilibrado e limitado
  Sessões                    Curtas
  Visual                     Minimalista e abstrato
  Plataforma inicial         Android
  Engine                     Godot
  Monetização                Fora do protótipo inicial

## 3. Loop principal

1.  Receber a produção do sistema.
2.  Avaliar recursos e gargalos.
3.  Construir ou melhorar componentes.
4.  Estabelecer conexões.
5.  Atingir condições.
6.  Descobrir capacidades.
7.  Reorganizar ou expandir o sistema.

## 4. Recursos

### Energy

Recurso operacional usado para manter componentes e processos ativos.

### Matter

Recurso estrutural usado para construir e aprimorar componentes.

### Data

Recurso de análise e descoberta, produzido por estruturas
especializadas.

Os recursos não podem ficar negativos. A interface exibe quantidade
atual e taxa líquida por segundo.

Energy tem armazenamento máximo (valor configurável). Matter e Data não
têm limite no MVP. Quando falta um insumo, os consumidores operam com
eficiência proporcional em vez de desligar (ver `ECONOMY.md` §5).

## 5. Componentes do MVP

  Componente   Função
  ------------ ------------------------------------------------
  Core         Núcleo inicial; fonte inicial de Energy; raiz da rede
  Generator    Produção adicional de Energy (custa apenas Energy)
  Collector    Produção de Matter a partir de Energy
  Processor    Amplifica a produção dos componentes ligados a ele
  Relay        Hub: fornece portas de saída extras para expandir a rede
  Analyzer     Produz Data a partir de Energy e Matter

O Core é obrigatório e não pode ser removido.

Decisões D-014 a D-022 (ver `DECISIONS.md`).

### Estado inicial sem dependência circular

A partida começa com:

-   Um Core, com produção básica de Energy.
-   Generator desbloqueado. Ele custa **apenas Energy**, portanto nunca
    consome a reserva de Matter.
-   Uma reserva inicial de Matter **igual ou maior que o custo do
    primeiro Collector**.

Enquanto não existir Collector, nenhum componente desbloqueado custa
Matter, logo a reserva só pode ser gasta no próprio Collector. Isso
torna o início livre de bloqueio por construção, sem depender da
escolha do jogador.

O último Collector da rede não pode ser removido (mesma proteção do
Core), para que sempre exista uma fonte de Matter depois da primeira.

Regra geral: nenhum componente é exigido para desbloquear a si mesmo, e
nenhuma descoberta exige um componente que só ela, ou uma descoberta
posterior, desbloqueia.

## 6. Rede e conexões

A rede é uma **árvore direcionada com raiz no Core**.

### O que uma conexão significa

-   Os recursos ficam em um **reservatório global**. Nada é
    transportado pelas conexões.
-   Uma conexão significa **ativação**: um componente só opera (produz
    e consome) se houver um caminho do Core até ele e ele estiver
    habilitado.
-   Componentes desconectados ficam **inativos**: não produzem, não
    consomem e não contam para condições que pedem componentes ativos.

### Regras de conexão

-   Cada componente que não é o Core tem **exatamente uma entrada**
    (seu pai) e um número de **portas de saída** definido em dados.
-   O Core tem poucas portas (valor inicial de teste: 3). O Relay tem
    muitas (valor inicial de teste: 4), e é assim que a rede cresce.
-   Como cada nó tem um único pai e a raiz é o Core, **ciclos são
    impossíveis por construção**. Conectar um nó a um de seus
    descendentes é rejeitado.
-   Desconectar um nó desativa toda a sua sub-árvore. Ela continua
    construída e pode ser reconectada.
-   Remover um componente reembolsa parte do custo (valor inicial de
    teste: 50%), e seus filhos ficam desconectados.

### Efeito do Processor

O Processor multiplica a produção dos seus **filhos diretos**. O efeito
não é transitivo: um Processor sob outro Processor não acumula bônus.
Isso transforma o posicionamento na árvore em decisão estratégica, sem
permitir cadeias de multiplicação.

Na primeira versão não há roteamento físico, congestionamento nem
partículas transportadas.

## 7. Descobertas

Descobertas são verificadas automaticamente. Podem exigir condições
quantitativas, estruturais, funcionais ou históricas.

Tipos de condição: - Quantitativa: possuir determinada quantidade ou
número de componentes. - Estrutural: possuir uma configuração de
conexões. - Funcional: manter produção ou operação por um período. -
Histórica: ter produzido/acumulado determinado total ao longo da
partida.

Uma descoberta: - Tem ID estável. - Tem condições explícitas. - É
concedida uma única vez. - Registra data/ordem de obtenção. - Concede
recompensa definida em dados. - Pode desbloquear componentes, melhorias
ou regras.

### Descobertas planejadas

Os valores abaixo são os de teste que estão em `data/discoveries/`; todos
são dados, não código, e serão calibrados. Cada descoberta só é
avaliada depois que os seus pré-requisitos foram obtidos (coluna
"Exige"). Os pré-requisitos formais são: D2 ← D1; D4 ← D2; D5 ← D2;
D6 ← D2, D3; D7 ← D3, D5; D8 ← D1 a D7; D1 e D3 não têm.

Valores de teste: D2 e D4 sustentadas por 10 s; D5 com 5 de Data
produzido; D6 com 5 componentes ativos por 30 s; D8 com 100 de Matter
produzido.

  \#   Descoberta           Condição                                               Exige (já disponível)          Recompensa
  ---- -------------------- ------------------------------------------------------ ------------------------------ ----------------------------------------------
  1    First Connection     1 componente não-Core ativo                            Generator (inicial)            Collector
  2    Production Cycle     Taxa líquida de Energy > 0 e de Matter > 0 por X s     Generator, Collector           Analyzer + melhorias Production básicas
  3    Distributed System   ≥ 3 componentes não-Core ativos                        Portas do Core                 Relay
  4    Data Acquisition     Analyzer ativo produzindo Data por X s                 Analyzer (D2)                  Melhorias pagas em Data
  5    System Analysis      Data produzido acumulado ≥ N                           Analyzer (D2)                  Processor + melhorias Efficiency
  6    Self Regulation      ≥ N componentes ativos, incluindo ≥ 1 Collector e      Collector (D1), Analyzer       Automação inicial
                            ≥ 1 Analyzer, todos com eficiência 100%, por X s       (D2), Relay (D3)
  7    Adaptive Network     Processor ativo com ≥ 2 filhos de tipos diferentes,    Processor (D5), Relay (D3)     Melhorias avançadas
                            Relay ativo e ≥ 4 tipos distintos ativos
  8    Emergent Structure   D1--D7 obtidas e Matter produzido acumulado ≥ N        ---                            Stage II

### Verificação de alcançabilidade

Grafo de desbloqueio (A → B: A libera algo que B exige):

``` text
Camada 0  Início
Camada 1  D1 ← Início (Generator)       D3 ← Início (Generators + 3 portas do Core)
Camada 2  D2 ← D1 (Collector)
Camada 3  D4 ← D2 (Analyzer)    D5 ← D2 (Analyzer)    D6 ← D2 (Analyzer), D3 (Relay)
Camada 4  D7 ← D3 (Relay), D5 (Processor)
Camada 5  D8 ← D1..D7
```

Cada descoberta só depende de camadas anteriores, logo o grafo é
acíclico.

-   O grafo não tem ciclos: cada descoberta só exige componentes do
    estado inicial ou de descobertas anteriores.
-   D3 é alcançável sem Relay porque o Core tem 3 portas.
-   D4 tem o Analyzer como **condição**, não como recompensa. O Analyzer
    produz Data desde a construção, e D4 libera os **usos** de Data.
-   Funcionalidade de teste: a Fase 3 deve incluir um teste estático
    (grafo acíclico, referências válidas) e um jogador automático que
    conclui D1--D8 a partir de uma partida nova.

### Como as condições medem taxas

Se uma descoberta sustentada tem como pré-requisito outra concedida no
mesmo passo, o contador já conta esse passo (a avaliação segue a ordem
topológica dentro do passo).

"Taxa líquida" em condições de descoberta significa **produção −
consumo do passo, antes do limite de armazenamento**. Assim, um recurso
parado no máximo (Energy cheia) continua contando como em produção, e
D2 não fica bloqueada por uma rede saudável (D-028).

### Condições temporais e offline

Os contadores de condições funcionais ("por X s") avançam também
durante o cálculo offline, porque o offline usa as mesmas regras da
partida ativa. O progresso parcial desses contadores é salvo, e o
contador zera quando a condição deixa de ser satisfeita.

### Visibilidade

-   Descobertas obtidas: descrição e recompensa completas.
-   Descobertas próximas: pistas sobre categorias de requisitos.
-   Descobertas distantes: nome ou pista temática, quando adequado.
-   Descobertas secretas: ocultas até serem reveladas.

## 8. Melhorias

Categorias: - Production: aumenta produção. - Efficiency: reduz
consumo/custo ou melhora conversão. - Automation: executa operações sem
intervenção frequente.

Moedas de compra: melhorias Production custam Matter. Melhorias
Efficiency, Automation e avançadas custam Data (com ou sem Matter), o
que dá a Data uma função econômica própria a partir de D4.

Melhorias podem ser específicas de componente ou globais. A interface
apresenta custo e efeito antes da compra. Melhorias repetíveis usam
curvas configuráveis.

Evitar melhorias que sejam apenas bônus percentuais sem mudança
perceptível na tomada de decisão.

## 9. Estágios

### Stage I --- Emergence

Primeiros componentes, produção de recursos, conexões e descobertas
iniciais.

### Stage II --- Organization

Redes mais complexas, componentes especializados, melhorias globais e
automação inicial.

No MVP, alcançar o Stage II registra o estágio e exibe uma tela de
conclusão de conteúdo. Os componentes especializados do Stage II ficam
para depois do MVP e exigirão nova especificação.

A passagem de estágio não apaga o progresso. Prestígio/reset não faz
parte do MVP.

## 10. Automação

Primeira automação prevista: comprar automaticamente uma melhoria
selecionada quando houver recursos suficientes.

A automação deve ser desbloqueada por descoberta e ser
configurável/desativável pelo jogador.

## 11. Interface

Três áreas principais: - Dashboard: recursos, taxas, componentes ativos
e próxima descoberta. - Network: construção, conexões e inspeção. -
Discoveries: descobertas, pistas, requisitos e recompensas.

Janela adicional: - Offline Summary: resumo ao retornar ao jogo.

Navegação inferior com três abas. Orientação retrato. Animações
discretas e feedback claro.

## 12. Direção visual e áudio

Direção visual: minimalista, abstrata, científica, com nós e conexões
legíveis. Evitar excesso de efeitos, ruído visual e dependência de arte
complexa.

Áudio e identidade sonora não são bloqueadores do protótipo funcional e
devem ser tratados após validar o loop.
