# Concierge Gems 2.0 — animação fluida (manual de atualização e arquitetura)

Serve para quem **já montou** o painel da versão 1 (64 células `CG_CELL_r_c` linkadas). Você **não precisa refazer o painel**:
só acrescenta as 64 gemas móveis e troca os scripts.

## 1. O que mudou

| 1.0 | 2.0 |
|---|---|
| a gema era uma textura pintada na célula; a queda andava em degraus de uma linha | 64 prims `CG_GEM_0..63` **se movem de verdade**, com posição interpolada pelo tempo decorrido (smoothstep na troca, aceleração na queda) |
| `GEMS_FX` movia e dormia (`llSleep`) | **um só controlador de movimento** (`GEMS_ANIMATION`), sem `llSleep`, só mexe nos prims que se movem, em lotes de até 16 prims por chamada de `llSetLinkPrimitiveParamsFast` |
| efeito e grade podiam divergir (`ondas=1; grade=0`) | `BOARD` só entrega a jogada ao `ANIMATION` (msg 211); a grade nova de nível/embaralhar espera o fim das ondas (110 → 111/112); após reinício o `ANIMATION` pede a grade (250) e se reconstrói (100) |
| as 64 células mostravam a gema | as células ficam **invisíveis (alpha 0) e continuam recebendo o toque**; quem aparece é a gema |

Máquina de estados: `IDLE → SWAPPING (0,30 s) → MATCHING → EXPLODING (0,18 s) → FALLING → SPAWNING → CASCADE_CHECK → IDLE`.
Troca inválida: as duas gemas vão e voltam (0,30 s + 0,30 s). Nível novo: o tabuleiro inteiro explode e a grade nova cai por cima
(0,48 s). Sem jogadas: as gemas deslizam para o novo lugar (0,52 s). Explosão: atlas `CG_fx_atlas` (animação de textura, roda no
viewer) + partículas nativas (no máximo 4 emissores por onda) + fade. As gemas que entram reaproveitam o pool das que explodiram
e nascem acima do tabuleiro; o alinhamento final é exato (a última posição escrita é a da célula).

## 2. Atualizar o painel que já existe

1. **Backup:** faça uma cópia (Take Copy) do painel montado.
2. Prepare o modelo da gema: cubo **fino no X** (não no Z — era isso que deixava as células "de lado"; a frente do painel é +X).
   Sugestão para painel de 0,75 m: `CG_GEM = <0,006 ; 0,088 ; 0,088>`. Nomeie **`CG_GEM`**, coloque `GEMS_CELL.lsl` dentro e pegue (Take).
3. Coloque `CG_GEM` e `GEMS_BUILDER.lsl` dentro da **raiz** do painel montado, toque nela (só o dono) e escolha **Gemas**.
   O BUILDER usa tamanho e rotação da raiz. Aparecem 64 gemas `CG_GEM_0` … `CG_GEM_63` à frente das células.
4. Selecione as 64 gemas **e por último o painel** e linke (Ctrl+L). O limite é 256 prims por linkset: 64 células + 64 gemas + raiz + interface
   cabem, mas confira o total.
5. Apague `GEMS_BUILDER` e o objeto `CG_GEM` de dentro da raiz.
6. **Troque os scripts** da raiz: `GEMS_LOGIC`, `GEMS_BOARD`, `GEMS_FX` (versões novas) e **acrescente `GEMS_ANIMATION`**.
   Mantenha `GEMS_AUDIO`, `GEMS_SYNC` e o notecard `CG_CONFIG`. Apague a versão antiga de cada um antes de soltar a nova.
7. Ao iniciar, o dono verá o `ANIMATION` dizer quantas células e gemas achou (`READY` só com 64 + 64). Se faltar, ele avisa.
8. Teste nesta ordem: reset → jogada válida → jogada inválida → combinação de 4/5 (especiais) → cascata → nível novo → sem jogadas.

**Gema deitada ou espelhada na frente:** mude `TEX_ROT` no topo do `GEMS_ANIMATION` (0.0 → 1.5708).
**Gema cortada ou muito grande/pequena:** ajuste o tamanho do `CG_GEM` ou `OUT_GEM` no BUILDER.

## 3. Desempenho e LI (Land Impact)

- **LI:** cada prim linkado conta ~1. O painel novo é ≈ 64 células + 64 gemas + raiz + interface. Sem mesh, sem custo extra de peso.
- **Carga no simulador:** cada gema movida é uma atualização de objeto. Medido **no simulador de testes**: pior caso de uma jogada =
  **527 escritas de posição por segundo** a 22 atualizações/s, até 16 prims por chamada. Por isso o passo do timer é adaptativo:
  0,045 s (até 12 gemas móveis), 0,06 s (até 32), 0,085 s (mais que isso, ex.: nível novo). **Não prometo 60 FPS:** prim filho não é
  interpolado pelo viewer, então a fluidez é a taxa de atualização que o simulador entregar (esperado algo entre 10 e 20 quadros/s — a confirmar no SL).
- **Se ficar pesado**, nesta ordem: aumentar `TICK*`; encurtar a queda; diminuir `MAX_BURSTS`; usar tabuleiro menor.
- **Lag do simulador:** o `ANIMATION` usa tempo decorrido, não contagem de passos. Se o simulador atrasar, a gema pula para onde deveria
  estar e termina no mesmo instante, sem câmera lenta.

## 4. O que foi e o que NÃO foi testado

**Testado fora do Second Life** (`tests/test_animation.py`: 166 checagens, 0 falhas; `tests/test_logic.py 40`: 1.109 checagens, 0 falhas):
troca válida (trajetória e tempo), troca inválida com retorno, explosão de cada onda, queda contínua com centralização exata, entrada de
gemas por cima, cascatas multi-onda, nível novo, embaralhar, reinício com recuperação da grade, offline e fila do SYNC; nenhuma gema
duplicada ou perdida e grade visual == grade lógica ao fim de 40 jogadas completas; lote máximo de 16 prims.

**NÃO testado:** compilação no LSL real (só o verificador de sintaxe próprio), memória de script (limite 64 KB Mono; o
`GEMS_ANIMATION` tem ~26 KB de texto), taxa de quadros real, orientação e tamanho das gemas no seu painel, partículas e brilho no viewer,
latência do simulador, dois jogadores ao vivo. Isso só se valida dentro do Second Life.
