# Testes da lógica — resultados

**Comando:** `python tests/test_logic.py 400` (precisa de Node e Python; leva ~3,5 min).
**Resultado (2026-09-19):** **8.727 checagens, 0 falhas.**

## O que foi comparado com o jogo original

O mesmo tabuleiro, a mesma jogada e a **mesma sequência de números aleatórios** entram no `logic.js` original (Node) e em
`scripts/GEMS_LOGIC.lsl` (interpretador `tools/lslsim.py`). Tudo tem de ser idêntico.

| Grupo | Amostra | O que é igual ao original |
|---|---|---|
| Fórmulas de nível | 3 dificuldades × 40 níveis | meta de pontos, nº de cores, dreno do tempo, bônus de tempo, teto de tempo, tempo inicial, atraso da dica (extraídas do texto do `main.js`) |
| Troca válida e dica | 26 tabuleiros × 112 pares | `validSwap` de todos os pares adjacentes, primeira dica e "há jogada?" |
| Tabuleiro inicial e embaralhar | 26 + 13 cenários (5, 6 e 7 cores) | grade gerada e nº de sorteios consumidos |
| Resolver jogada | **400 jogadas**, 661 ondas | por onda: pontos, bônus de tempo, gemas limpas, especiais criados, quedas, entradas; grade final; sorteios consumidos |
| Partidas completas | 26 partidas, 1.266 jogadas | pelo protocolo de mensagens (novo jogo, dica, jogada, tempo, fim); grade cheia e sem sequência em repouso; pontuação nunca cai; ondas reproduzem a grade final; nível sobe; resultado final coerente; nada é aceito depois do fim |

Cobertura das jogadas: 163 cascatas de 2+ ondas (máx. 8), 62 bombas e 33 estrelas criadas, 57 trocas com rainbow.

## Limites (leia antes de concluir que "está pronto")

- O interpretador **não é o LSL real**: não mede memória (64 KB por script Mono) nem tempo de execução, usa ponto flutuante de 64 bits (o
  Second Life usa 32; nenhum valor do jogo passa de 2^24, mas arredondamentos de meio ponto podem diferir) e não replica todas as
  verificações do compilador da Linden.
- **Nada foi compilado ou executado no Second Life.** O script pode ter erro de compilação que só o viewer mostra.
- Esta bateria valida **regras**. Fluidez, animações, sons, partículas, toque, interface e o comportamento de vários jogadores
  só podem ser validados dentro do viewer (Etapas 3 a 7).


---

# Concierge Gems 2.0 — animação (2026-09-20)

**Comandos:** `python tests/test_animation.py` (**166 checagens, 0 falhas**) e `python tests/test_logic.py 40` (**1.109 checagens, 0 falhas**).
`tools/lslworld.py` simula um linkset com prims nomeados, relógio virtual, timers e `link_message` entre os scripts reais
(`LOGIC`, `BOARD`, `ANIMATION`, `FX`, `SYNC`).

Cobre: troca válida/inválida, explosão, queda, entrada, cascata, nível novo, embaralhar, reinício com recuperação de grade, offline;
grade visual == grade lógica ao fim de cada jogada; pior caso medido de 527 escritas de posição/s; lote máximo de 16 prims.

**Não cobre:** compilador LSL real, memória Mono, latência/limite de atualização do simulador, fluidez visual, orientação das peças,
partículas e brilho no viewer, multijogador. Veja `docs/03-atualizacao-2.0-animacao-fluida.md`, seção 4.
