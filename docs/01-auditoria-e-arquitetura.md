# Concierge Gems nativo (LSL) — Etapa 1: auditoria e arquitetura

Estado: **auditoria concluída; nada foi testado no viewer**. O jogo HTML (`public/games/bubble-match/`) não foi alterado.
Este módulo é independente: `concierge-gems-secondlife/`.

## 1. O que o jogo original faz (lido em `logic.js`, `main.js`, `audio.js`, `index.html`, `style.css`)

**Tabuleiro:** 8 × 8. Célula 62 px, gema 58 px (0,935 da célula). Tabuleiro 496 × 496 px dentro de um palco de 548 × 666 px
(proporção 0,823, a da tela do gabinete, 0,83 × 1,01 m).

**Posição no palco (px):** padding 10/26/12; cabeçalho y 10–50; barra de status y 58–108 (4 caixas: SCORE, BEST, COMBO, LEVEL,
118 px cada, vão de 8); barra de tempo y 116–130; barra de progresso y 135–149; **tabuleiro em x 26–522, y 157–653**.
Em metros (0,001515 m/px): célula 0,0939 m, gema 0,0878 m, tabuleiro 0,751 m, canto do tabuleiro a 0,039 m da borda esquerda e 0,238 m do topo da tela.

**Gemas:** 7 cores (`gem_0_blue`, `_1_green`, `_2_red`, `_3_gold`, `_4_turquoise`, `_5_magenta`, `_6_pink`) + `gem_rainbow`,
todas PNG **256 × 256 RGBA**, 8 bits (total 383 KB). Cores de efeito: `#4A5CFF #3ED13E #E23A3A #FFC43B #3FE0E8 #D43CE0 #FF3EA5`.
Cores em jogo por nível: 5, 6 ou 7 (`sixFrom`/`sevenFrom` por dificuldade).

**Regras (`logic.js`):**
- Combinação = 3+ da mesma cor em linha ou coluna. Troca só vale se gerar combinação; **rainbow troca com qualquer gema**.
- 4 em linha cria **bomba** (limpa 3 × 3, +30); 5 em linha cria **rainbow**; encontro em L/T (linha e coluna) cria **estrela**
  (limpa linha e coluna inteiras, +60). Especiais atingidos disparam em cadeia.
- Rainbow + cor: limpa todas as gemas daquela cor (+150). Rainbow + rainbow: limpa o tabuleiro (+500).
- Bônus de criação: 4 → +40, 5 → +100, estrela → +40.
- **Pontos por onda** = `round(gemas × 10 × mult + bônus × mult)`, `mult = 1 + 0,5 × cascata` (cascata 0, 1, 2…).
- Gravidade por coluna; reposição por cima com cor aleatória (dentro das cores do nível). Sem jogadas → embaralha.
- Tempo: início 120/90/70 s (fácil/normal/difícil); escoa `drain × min(1,6; 1 + 0,05 × (nível − 1))` por segundo; teto 1,3 × início;
  bônus de tempo por cascata e por especial; ao completar nível: `max(10; 24 − nível) × bônus`.
- Meta do nível: `900 × (1 + 0,45(n−1) + 0,03(n−1)²) × fator`, arredondada de 50 em 50 (fator 0,8 / 1,0 / 1,25).
- Fim de nível: bônus `250 × nível + 100 × especiais restantes`; tabuleiro estoura inteiro e entra um novo.
- Dica após 5/7/12 s parado (fácil/normal/difícil).

**Animações (`main.js`, ms):** troca 120 (easeInOut); estouro 150 (escala 1 → 1,18 nos 30 % iniciais, depois → 0 com fade);
anel de luz 420 ms (raio 10 → 44 px, espessura 4 → 1, alpha 1 → 0) + 7 partículas (distância 22–42 px, gravidade `14 t²`);
queda 90 + 45/linha (máx. 380) com curva quadrática e leve quique no fim; gemas novas entram com escala easeOut;
seleção = moldura branca de 3 px; dica = moldura dourada pulsando; textos flutuantes (+pontos, "BOM!", "LEGAL!", "INCRIVEL!", "FANTASTICO!") por 900 ms.

**Sons (`audio.js`):** 100 % sintetizados (WebAudio): seleção, troca, inválido, estouro (estilhaço de vidro + sino que sobe a escala maior por cascata),
pouso, especial nasce, bomba / estrela / rainbow, level up, início, embaralhar, tique do tempo, game over.

**Integração atual:** `arcade.js` só liga com `?st=` / `?m=`; o jogo em si já roda sozinho no navegador.

## 2. Limites reais do LSL que decidem a arquitetura

| Limite | Consequência |
|---|---|
| **Máx. 8 faces por prim/mesh** | Um mesh com 64 faces (uma por célula) **não existe**. O mais próximo é 8 malhas de 8 faces (uma por linha). |
| Linkset até 256 prims | 64 células + interface + efeitos ≈ 110 prims cabe. |
| Mono: 64 KB por script (código + dados) | A lógica cabe; dividir em poucos scripts com mensagens de baixa frequência. |
| `llSetLinkPrimitiveParamsFast` sem atraso, aceita lista com vários links | Atualizar só as células mudadas, em lote. |
| Prims filhos **não são interpolados** pelo viewer (só saltam); `llSetKeyframedMotion` não vale para filhos | Movimento suave só dentro da própria face (animação de textura) ou com objetos avulsos. |
| `llSetTextureAnim` / `llSetLinkTextureAnim` rodam **no viewer** (SMOOTH, LOOP, PING_PONG, translação/escala/rotação, quadros de atlas) | Base das explosões, da dica pulsando e da "queda" dentro da célula, sem custo de script. |
| `llParticleSystem` roda no viewer | Partículas coloridas nativas por célula (rajada curta). |
| Linkset Data: 128 KB por linkset | Fila de resultados pendentes (limitada, ver §8). |
| Upload: L$ 10 por textura e por som | Ver §7. Preferir atlas. |
| Textura clássica ≤ 1024 px por lado | Atlas de gemas 1024 × 512 (4 × 2 gemas de 256). |
| Sons: WAV 16 bit mono 44,1 kHz, ≤ 10 s | Todos os efeitos cabem. |
| Sem `sleep` sem custo | O tique do jogo é um único `llSetTimerEvent` a 0,05–0,1 s **só durante animações**; parado, o timer é de 1 s (relógio). |

## 3. Adaptações (fidelidade ao Canvas × o que o viewer permite)

| Original | Nativo em Second Life | Fidelidade |
|---|---|---|
| Troca 120 ms suave | 2 prims "voadores" deslizam em 3 passos de 40 ms; células mostram a gema final ao fim | boa (sem sub-quadro) |
| Estouro: escala 1 → 1,18 → 0 + fade | atlas de estouro (quadros) por animação de textura + escala em 3 passos | boa |
| Anel + 7 partículas | quadro do anel no atlas + `llParticleSystem` (rajada curta, cor da gema) | boa |
| Queda contínua com quique | **queda em degraus de 1 linha** (cada degrau = 1 animação de textura suave dentro da face, ~45 ms), repetida até assentar | aproximada (sem quique) |
| Gemas novas com escala easeOut | entram deslizando de cima na linha 0 e escalam por textura | boa |
| Texto do HUD (fonte do sistema) | atlas de dígitos (0–9, x, /) em 1 prim por dígito; textos fixos ("SCORE", "LEVEL") como textura pré-desenhada | boa, fonte fixa |
| Barras de tempo/progresso | prim escalado (`PRIM_SIZE` + posição), passo mínimo de 1 % | boa |
| Toast / combo ("BOM!", "FANTASTICO!") | textura curta por frase em prim de aviso | boa |
| Arrastar e soltar | **dois cliques** (selecionar, depois a célula vizinha), preservando a animação de troca | adaptação obrigatória |
| Sons WebAudio | WAV gerados a partir dos mesmos parâmetros, tocados com `llPlaySound` / `llTriggerSound` | boa (síntese offline), não idêntica amostra a amostra |

Não há como igualar o Canvas quadro a quadro: o viewer não interpola movimento de prim filho. O que estas adaptações mantêm é a
**sequência** (clique → troca → estouro → queda → reposição → cascata), os **tempos**, as **cores** e as **regras**.

## 4. Arquitetura escolhida

**Células = 64 prims planos independentes** (`CG_CELL_r_c`, linha `r` e coluna `c` de 0 a 7), cada um com **uma face** que mostra
a gema por **recorte do atlas** (`PRIM_TEXTURE` com `repeats` e `offset`) — trocar a gema é mudar o `offset`, sem trocar de textura.
Cada célula recebe o próprio toque (`llDetectedLinkNumber`), o próprio efeito de partículas e a própria animação de textura.

*Alternativa B (8 malhas de 8 faces, uma por linha)* reduziria o Land Impact de ~64 para 8, mas exige mesh novo e impede animar
tamanho por célula. Fica como otimização **depois** de validar o protótipo no viewer.

**Prims por função (~110):**

| Grupo | Nome | Qtd |
|---|---|---|
| Células | `CG_CELL_0_0` … `CG_CELL_7_7` | 64 |
| Seleção / dica | `CG_SEL`, `CG_HINT_A`, `CG_HINT_B` | 3 |
| Voadores (troca e queda) | `CG_FLY_0` … `CG_FLY_3` | 4 |
| Efeitos (anel/estouro) | `CG_FX_0` … `CG_FX_7` | 8 |
| Dígitos do HUD | `CG_D_SCORE_0..6`, `CG_D_BEST_0..6`, `CG_D_COMBO_0..1`, `CG_D_LEVEL_0..1`, `CG_D_TIME_0..2` | 21 |
| Barras | `CG_BAR_TIME`, `CG_BAR_PROG` | 2 |
| Botões e telas | `CG_BTN_PLAY`, `CG_BTN_PAUSE`, `CG_BTN_RESET`, `CG_OVERLAY`, `CG_TOAST` | 5 |
| Rótulos fixos | `CG_LBL_*` (SCORE, BEST, COMBO, LEVEL) | 4 |

Os prims são **filhos do gabinete existente** (`CG_Screen` continua como fundo); o mesh original **não muda**.
O **instalador** (`GEMS_INSTALL.lsl`) percorre o linkset, acha tudo **pelo nome** e grava os números de link em Linkset Data —
nenhum número é digitado à mão.

## 5. Scripts e como conversam

| Script | Responsabilidade | Mensagens |
|---|---|---|
| `GEMS_CONFIG` | UUIDs de textura/som, cores, tempos, dificuldade | lido pelos outros no início (`llLinksetDataRead`) |
| `GEMS_LOGIC` | grade 8 × 8, combinações, especiais, cascata, gravidade, pontos, níveis, tempo | recebe `move`/`tick`; devolve a **lista de ondas** numa única mensagem |
| `GEMS_BOARD` | mapa link ↔ célula, toque, seleção de duas células, dono da partida | envia `move` à LOGIC; recebe `waves` |
| `GEMS_ANIMATION` | executa as ondas no viewer (texturas, degraus de queda, voadores) | recebe `waves`; avisa `anim_done` |
| `GEMS_PARTICLES` | rajadas por célula/cor, anel | recebe `burst r c color` |
| `GEMS_AUDIO` | toca/pré-carrega sons, liga/desliga | recebe `sfx <nome>` |
| `GEMS_UI` | dígitos, barras, botões, tela de Game Over | recebe `hud score best combo level time progress` |
| `GEMS_STORAGE` | fila local de resultados (Linkset Data) | `enqueue`, `next`, `ack` |
| `GEMS_SYNC` | envia resultados ao Concierge OS quando houver rede | usa `GEMS_STORAGE` |
| `GEMS_CONTROLLER` | máquina de estados (IDLE → PLAYING → PAUSED → OVER), trava de jogador | orquestra os demais |

Regras de comunicação: **poucas mensagens grandes**, nunca uma por célula. A LOGIC calcula a partida inteira de uma jogada
(todas as ondas) e a ANIMATION apenas a reproduz. Os módulos podem ser fundidos quando a memória sobrar (a divisão em 10 é máxima).

## 6. Sem servidor

Toda a regra roda no linkset. O servidor só recebe: `{game_id, avatar_uuid, score, level, difficulty, max_combo, moves, duration}`.
Sem rede, a partida segue normalmente e o resultado entra na fila local (§8).

## 7. Assets e custo de upload (L$)

| Asset | Origem | Arquivos | Custo |
|---|---|---|---|
| Atlas de gemas 1024 × 512 (8 × 256, pixels originais) | gerado dos 8 PNG | 1 | L$ 10 |
| Atlas de estouros (7 cores + rainbow + anel + brilho de seleção + especiais) | novo, desenhado com a mesma lógica do Canvas | 1–2 (1024²) | L$ 10–20 |
| Atlas de dígitos e textos do HUD | novo | 1–2 | L$ 10–20 |
| Sons (12–14 WAV) | sintetizados com os parâmetros de `audio.js` | ~13 | L$ ~130 |
| **Total estimado** | | **~18** | **~L$ 180** |

Alternativa mais barata: **um único atlas por tipo** e 6 sons agrupados (com deslocamento de reprodução não existe em LSL, então os sons
ficam separados). Os UUIDs reais só existem depois do upload — os campos ficam **vazios e configuráveis** em `GEMS_CONFIG`.

## 8. Fila local (Linkset Data)

- Limite: **50 resultados pendentes** (~120 bytes cada → ~6 KB de 128 KB).
- Cada resultado tem `game_id` único (`<uuid do objeto>-<contador>-<segundo>`); o servidor descarta `game_id` repetido.
- Cheio: descarta o **mais antigo** e registra um contador de perdas (mostrado ao dono). Nunca bloqueia o jogo.
- Sincronização com recuo (30 s → 5 min); um resultado só sai da fila depois da confirmação (`ack`).

## 9. Tabuleiro, jogador e concorrência

Um jogador por vez: o **dono da partida** é o avatar que clicou em PLAY (`llDetectedKey`); cliques de outros avatares são ignorados
(mensagem "em uso por …"). Se ele ficar 60 s sem clicar (ou sair da região), a partida é encerrada e o painel é liberado.

## 10. O que precisa de decisão sua antes da Etapa 2 (protótipo)

1. **Células (A) 64 prims** (recomendado para o protótipo) ou **(B) 8 malhas de 8 faces** (menos LI, exige mesh novo)?
2. O gabinete no Second Life tem a tela **frontal plana** em `CG_Screen`? Preciso das dimensões reais dessa face para alinhar as células
   (uso 0,83 × 1,01 m, do mesh exportado). Se você redimensionou o objeto no mundo, informe a escala.
3. Orçamento de upload aceitável (~L$ 180) e se posso gerar os **sons em WAV** agora.

## 11. Próximos passos (ordem do projeto)

Etapa 2 — protótipo: `GEMS_LOGIC` + `GEMS_BOARD` com gemas, seleção, troca, combinações e pontuação, mais testes automáticos da lógica.
Etapa 3 — animações (atlas de estouro, degraus de queda, partículas). Etapa 4 — sons. Etapa 5 — interface. Etapa 6 — sincronização.
Etapa 7 — pacote, manual e ZIP. **Nada disso será dado como validado sem teste no viewer.**
