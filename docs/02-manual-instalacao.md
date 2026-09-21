# Concierge Gems nativo — manual de instalação

Jogo de verdade dentro do Second Life: prims, texturas, partículas, som e scripts LSL. **Sem Media on a Prim.**
A partida inteira roda no linkset, então **funciona com o Concierge OS offline**.

O que você precisa: permissão para construir no terreno e cerca de **L$ 240** de upload (3 texturas + 21 sons).

---

## 1. Subir as texturas (L$ 30)

No visualizador: **Build ▸ Upload ▸ Image**, e escolha os 3 arquivos da pasta `textures/`:

| Arquivo | O que é |
|---|---|
| `CG_gems_atlas_1024x512.png` | as 8 gemas do jogo original |
| `CG_fx_atlas_1024x1024.png` | explosão em 16 quadros |
| `CG_digits_atlas_512x512.png` | números do placar |

Ao subir, deixe **"Lossless compression" marcado** nas gemas, senão elas ficam borradas.

## 2. Subir os sons (L$ 210)

**Build ▸ Upload ▸ Sound**, com os 21 arquivos de `audio/`. Você pode subir todos de uma vez com **Bulk Upload**.
Mantenha os nomes como estão (`select`, `swap`, `match0`… `match7`, `blast_bomb`…). O script procura por nome.

Se quiser gastar menos, suba só estes 8 e o jogo funciona: `select`, `swap`, `invalid`, `match0`, `match1`, `match2`, `land`, `gameover`.

## 3. Montar o tabuleiro (o script faz sozinho)

1. Crie **um cubo**, achate para algo como `0,09 × 0,09 × 0,01` m, marque como **Phantom** e chame-o de **`CG_CELL`** (aba Geral do editor).
2. Coloque dentro dele o script **`GEMS_CELL.lsl`**.
3. Pegue o cubo de volta para o inventário (**Take**).
4. Crie outro cubo, achate para algo como `0,088 × 0,088 × 0,006` m, marque como **Phantom** e chame-o de **`CG_GEM`**.
5. Coloque dentro dele o mesmo script **`GEMS_CELL.lsl`** e pegue-o de volta para o inventário.
6. Crie o prim que será a **base do tabuleiro**: um cubo achatado de cerca de **0,75 × 0,75 × 0,05** m, virado para você.
   A face que fica de frente é a **+X local** (a seta vermelha do editor aponta para o jogador).
7. Arraste para dentro da base: os objetos **`CG_CELL`**, **`CG_GEM`** e o script **`GEMS_BUILDER.lsl`**.
8. **Toque na base** e escolha **Ambos**. Ele cria as 64 células (`CG_CELL_0_0` a `CG_CELL_7_7`) e as 64 gemas (`CG_GEM_0` a `CG_GEM_63`) já posicionadas e nomeadas.
9. Selecione tudo (células, gemas e a base), com a **base por último**, e **linke com Ctrl+L**.
10. Apague o `GEMS_BUILDER` e os objetos `CG_CELL`/`CG_GEM` de dentro da base.

As células criadas pelo script já nascem sem colisão física. Se você estiver reaproveitando células antigas, selecione-as e marque **Phantom** ou recrie o tabuleiro com esta versão.

Se o tabuleiro ficar fora da área da tela do gabinete, ajuste `BOARD_UP_CELLS` no `GEMS_BUILDER.lsl` antes de criar as peças. Valor positivo sobe, valor negativo desce. O `BOARD_SCALE` controla o tamanho do grid para não invadir o letreiro nem os botões.

Esta distribuição divide a renderização em `GEMS_RENDER_CONTROLLER.lsl` e quatro motores (`GEMS_RENDER_A/B/C/D`). Cada motor controla somente 16 gemas. O prim raiz não é movimentado; as animações usam apenas `llSetLinkPrimitiveParamsFast` com `PRIM_POS_LOCAL` nos prims `CG_GEM_*`.

## 4. Peças da interface (opcionais, mas recomendadas)

Crie estes prims, linke junto e dê exatamente estes nomes (aba Geral):

| Nome | O que é | Sugestão |
|---|---|---|
| `CG_BTN_PLAY` | botão de começar | prim pequeno abaixo do tabuleiro |
| `CG_BTN_PAUSE` | pausar | ao lado do PLAY |
| `CG_SEL` | moldura da gema selecionada | prim fino, levemente à frente das células |
| `CG_BAR_TIME` | barra de tempo | prim comprido e fino |
| `CG_BAR_PROG` | barra de progresso do nível | idem |
| `CG_TOAST` | avisos em texto flutuante | prim pequeno e transparente |
| `CG_D_SCORE_0` … `CG_D_SCORE_5` | dígitos da pontuação | 6 prims lado a lado |
| `CG_D_BEST_0` … `CG_D_BEST_5` | recorde | 6 prims |
| `CG_D_TIME_0` … `CG_D_TIME_2` | tempo | 3 prims |
| `CG_D_LEVEL_0`, `CG_D_LEVEL_1` | nível | 2 prims |
| `CG_D_COMBO_0`, `CG_D_COMBO_1` | combo | 2 prims |

O jogo funciona sem eles: o que faltar é simplesmente ignorado, e o script avisa no chat o que encontrou.

## 5. Instalar os scripts

Arraste para dentro do **prim raiz** (a base):

- `GEMS_LOGIC.lsl` — as regras
- `GEMS_BOARD.lsl` — tabuleiro, toque e placar
- `GEMS_RENDER_CONTROLLER.lsl` — coordena a renderização
- `GEMS_RENDER_A.lsl` — movimento das gemas 0 a 15
- `GEMS_RENDER_B.lsl` — movimento das gemas 16 a 31
- `GEMS_RENDER_C.lsl` — movimento das gemas 32 a 47
- `GEMS_RENDER_D.lsl` — movimento das gemas 48 a 63
- `GEMS_FX.lsl` — animações e partículas
- `GEMS_AUDIO.lsl` — som

Arraste também as **3 texturas** e os **sons** para dentro do prim raiz. Opcionalmente, crie o notecard **`CG_CONFIG`**
com o conteúdo de `scripts/CG_CONFIG.txt` (só é preciso se você quiser usar UUIDs em vez dos nomes).

No inventário do prim raiz, mantenha estes nomes exatos de textura, sem `.png`: `CG_gems_atlas_1024x512`, `CG_fx_atlas_1024x1024` e `CG_digits_atlas_512x512`.

Ao terminar, o script diz no chat quantas células e quantos elementos achou. Se disser que faltam células, refaça o passo 3.

## 6. Jogar

1. Toque em **`CG_BTN_PLAY`**. Quem tocar vira o dono da partida.
2. Toque numa gema para selecionar e depois na **vizinha** para trocar. São dois cliques: o Second Life não tem arrastar e soltar.
3. Combinações de 3 ou mais estouram, as gemas caem e a cascata continua sozinha.
4. Se ficar 7 segundos parado, o jogo pisca uma jogada possível.
5. A partida acaba quando o tempo zera. Depois de 90 segundos sem tocar, o painel se libera para outra pessoa.

## 7. Integração opcional com o Concierge OS

Preencha `API_URL`, `LAND_ID`, `MACHINE_ID` e `MACHINE_SECRET` no `CG_CONFIG` para mandar o resultado ao ranking.
Com o servidor fora do ar o jogo continua igual: só a sincronização fica pendente.

**Não distribua cópias do objeto com o segredo preenchido.** Quem tiver o objeto consegue ler o notecard.

---

## Se algo der errado

| Sintoma | Causa provável |
|---|---|
| "faltam N células" no chat | o linke não pegou todas, ou algum nome saiu errado. Refaça o passo 3. |
| Gemas aparecem em branco ou como xadrez | a textura não está no prim raiz e o `CG_CONFIG` está sem o UUID. |
| Sem som | os WAV não estão no prim raiz, ou `SOUND = 0` no notecard. |
| Explosão não aparece | falta o `CG_fx_atlas` no prim raiz. |
| Nada acontece ao tocar | o `GEMS_BOARD` não está no prim **raiz**, ou o `CG_BTN_PLAY` não foi criado. |
| Números do placar não mudam | os prims `CG_D_*` não existem ou têm nome diferente. |

## Limites conhecidos (honestos)

- **Nada disto foi testado dentro do Second Life.** As regras foram validadas fora do jogo (8.727 checagens contra o
  código original), e os scripts passam por um verificador de sintaxe que escrevi, mas **não pelo compilador da Linden**.
  Erro de compilação, estouro de memória ou lentidão só aparecem no visualizador.
- A **queda das gemas é em degraus** de uma linha, não um deslizamento contínuo: o Second Life não interpola movimento de
  prim filho. As demais animações (explosão, brilho, partículas) rodam no visualizador e são suaves.
- O tabuleiro tem **65 prims**, mais a interface. Isso conta no Land Impact do terreno.
