# NEXUS --- Roadmap do MVP

**Estimativa inicial:** 10--14 semanas, sujeita à disponibilidade,
experiência e retrabalho. Não é compromisso de prazo.

## Fase 0 --- Fundação

Entregas: - Projeto Godot criado. - Repositório Git. - Estrutura de
diretórios. - Documentação revisada. - Build mínimo executável.

Critério de saída: projeto abre e executa sem erros.

**Status: concluída em 2026-11-23.** `tools/run_tests.sh` executa 9
testes, que passam; o runner foi verificado com falhas propositais
(asserção, erro de execução, erro de sintaxe), e todas resultaram em
código de saída 1. `tools/smoke.sh` executa a cena principal por 300
frames sem erros.

## Fase 1 --- Economia

Entregas: - Definições de recursos. - Saldos. - Produção e consumo. -
Construção básica. - Simulação determinística. - Testes econômicos.

Critério de saída: simulação reproduzível sem interface elaborada.

**Status: concluída em 2026-11-24.** Implementados: validador de
definições, estado, ledger atômico, construção, motor de passo
determinístico, simulador CSV (`tools/simulate.sh`) e 56 testes
(inclui testes de mutação manuais do motor). Adiados de propósito: o
`GameManager` com acumulador de passo fixo e a tela de debug, que só
fazem sentido junto da interface (Fase 6); a rede e o multiplicador do
Processor (Fase 2).

## Fase 2 --- Componentes e rede

Entregas: - Instâncias de componentes. - Conexões direcionadas. -
Validação de compatibilidade. - Regras de conectividade. - Testes de
rede.

Critério de saída: rede funcional sem ciclos exploráveis de geração
gratuita.

**Status: concluída em 2026-11-24.** `NxNetwork` (ligar, desligar,
portas, ciclos, ativação, remoção com reembolso, validação da árvore) e
motor com ativação por conectividade e multiplicador do Processor; 84
testes, com mutações manuais da rede e do motor todas detectadas.
Pendentes de aprovação: D-036 e D-038.

## Fase 3 --- Descobertas

Entregas: - Condições quantitativas, estruturais, funcionais e
históricas. - Registro de descobertas. - Recompensas. - Pistas e
visibilidade. - Testes de alcançabilidade e dependências.

Critério de saída: sequência inicial de descobertas pode ser completada
sem bloqueio.

## Fase 4 --- Melhorias e automação

Entregas: - Melhorias por componente. - Melhorias globais. - Curvas de
custo. - Primeira automação.

Critério de saída: melhorias e automação produzem mudanças observáveis e
testadas.

## Fase 5 --- Save e offline

Entregas: - Salvamento automático. - Versionamento. - Backup e
recuperação. - Cálculo offline. - Tela de resumo.

Critério de saída: fechar e reabrir preserva o estado e aplica progresso
offline corretamente.

## Fase 6 --- Interface mobile

Entregas: - Dashboard. - Network. - Discoveries. - Navegação. - Feedback
e acessibilidade básica.

Critério de saída: loop principal jogável em aparelho Android.

## Fase 7 --- Validação

Entregas: - Testes funcionais. - Testes em aparelhos modestos. -
Balanceamento. - Correção de crashes. - Revisão de UX.

Critério de saída: protótipo estável para testes externos limitados.

## Fora do MVP

-   Monetização.
-   Ads.
-   Backend.
-   Multiplayer.
-   Ranking.
-   Prestígio.
-   Eventos temporários.

## Métricas a observar em testes

Registrar: - Conclusão do tutorial/primeira descoberta. - Tempo até
primeira expansão. - Tempo até segunda descoberta. - Retorno após
primeira sessão. - Pontos de abandono. - Uso das telas de rede e
descobertas. - Frequência de gargalos e períodos sem ação útil.

Metas quantitativas de retenção só devem ser definidas como hipóteses de
validação, considerando origem e tamanho da amostra.
