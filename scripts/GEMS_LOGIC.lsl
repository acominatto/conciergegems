// GEMS_LOGIC.lsl - regras do Concierge Gems (conversao do Bubble Match / logic.js + parte de main.js).
// Roda 100% no linkset: nenhuma chamada de rede. Grade 8 x 8 em UMA lista de 64 inteiros (indice = linha*8 + coluna).
//   valor -1 = vazio; valor v >= 0: cor = v % 8 (0..6), especial = v / 8 (0 nenhum, 1 bomba, 2 estrela, 3 rainbow)
//
// Estilo LSL deliberado: sem ?: e sem break/continue; && e || NAO tem curto-circuito em LSL, entao nenhum teste
// depende disso (indices fora da lista so aparecem atras de um "if" separado).
//
// Mensagens (link_message, num = comando):
//   10 novo jogo          str = dificuldade "0|1|2"                -> 100 (grade) e 101 (hud)
//   20 jogada             str = "a,b" (indices 0..63)               -> 200 (resultado) [+ 210 ondas] [+ 110 grade nova, se subiu de nivel/embaralhou]
//   30 tick de tempo      str = segundos decorridos (float)         -> 101 (hud) e 300 se acabou
//   40 pedir dica         -> 400 "a,b" ou "-1"
//   250 ressincronia      (pedida pela camada visual ao reiniciar) -> 100 com a grade atual
// O formato das ondas (210) esta em waveToString().

integer COLS = 8;
integer ROWS = 8;

// ---------- estado da partida ----------
list G;                  // grade
integer DIFF = 1;        // 0 facil, 1 normal, 2 dificil
integer LEVEL = 1;
integer SCORE = 0;
integer PROGRESS = 0;
integer TARGET = 900;
integer NCOLORS = 5;
float   TIMELEFT = 90.0;
integer MAXCHAIN = 1;
integer MOVES = 0;       // jogadas validas (contagem enviada ao servidor)
integer CLEAREDN = 0;    // gemas estouradas
integer WAVESN = 0;      // ondas
integer OVER = FALSE;

// ---------- dificuldade (indice = DIFF) ----------
list D_START  = [120, 90, 70];
list D_DRAIN  = [0.85, 1.0, 1.15];
list D_BONUS  = [1.3, 1.0, 0.8];
list D_TARGET = [0.8, 1.0, 1.25];
list D_SIX    = [6, 3, 1];
list D_SEVEN  = [10, 7, 4];
list D_HINT   = [5000, 7000, 12000];   // ms parado ate a dica

// ---------- saidas do ultimo resolve ----------
list WAVES;              // uma string por onda
integer W_POINTS = 0;
integer W_TIME = 0;      // soma de timeBonus das ondas (segundos "brutos", antes do fator da dificuldade)
list RUNS;               // [dir(0 h,1 v), cor, inicio, tamanho] x N

// ---------- utilidades ----------
integer rnd(integer n) { return (integer)llFrand((float)n); }       // 0..n-1
integer rnd1(integer n) { return llFloor(llFrand((float)n)); }

integer roundHalfUp(float x) { return llFloor(x + 0.5); }           // igual ao Math.round do JS (valores positivos)

integer valAt(integer i)
{
    if (i < 0) return -1;
    if (i > 63) return -1;
    return llList2Integer(G, i);
}

// cor "para combinar": -1 se vazio ou rainbow (rainbow estoura como especial, nao casa por cor)
integer colorAt(integer i)
{
    integer v = valAt(i);
    if (v < 0) return -1;
    if (v / 8 == 3) return -1;
    return v % 8;
}

setG(integer i, integer v) { G = llListReplaceList(G, [v], i, i); }

swapG(integer a, integer b)
{
    integer x = llList2Integer(G, a);
    integer y = llList2Integer(G, b);
    setG(a, y);
    setG(b, x);
}

// ---------- dificuldade e niveis (main.js) ----------
integer levelTarget(integer level, integer diff)
{
    float n = (float)(level - 1);
    float base = 900.0 * (1.0 + 0.45 * n + 0.03 * n * n);
    float t = base * llList2Float(D_TARGET, diff);
    return llFloor(t / 50.0 + 0.5) * 50;
}

integer levelColors(integer level, integer diff)
{
    if (level >= llList2Integer(D_SEVEN, diff)) return 7;
    if (level >= llList2Integer(D_SIX, diff)) return 6;
    return 5;
}

float levelDrain(integer level, integer diff)
{
    float m = 1.0 + 0.05 * (float)(level - 1);
    if (m > 1.6) m = 1.6;
    return llList2Float(D_DRAIN, diff) * m;
}

integer levelTimeBonus(integer level, integer diff)
{
    integer base = 24 - level;
    if (base < 10) base = 10;
    return roundHalfUp((float)base * llList2Float(D_BONUS, diff));
}

integer timeCap(integer diff) { return roundHalfUp((float)llList2Integer(D_START, diff) * 1.3); }

// ---------- busca de combinacoes ----------
findRuns()
{
    RUNS = [];
    integer r; integer c; integer e; integer col; integer go;
    for (r = 0; r < 8; ++r)
    {
        c = 0;
        while (c < 8)
        {
            col = colorAt(r * 8 + c);
            e = c + 1;
            if (col >= 0)
            {
                go = TRUE;
                while (go)
                {
                    if (e >= 8) go = FALSE;
                    else if (colorAt(r * 8 + e) == col) ++e;
                    else go = FALSE;
                }
                if (e - c >= 3) RUNS += [0, col, r * 8 + c, e - c];
            }
            c = e;
        }
    }
    for (c = 0; c < 8; ++c)
    {
        r = 0;
        while (r < 8)
        {
            col = colorAt(r * 8 + c);
            e = r + 1;
            if (col >= 0)
            {
                go = TRUE;
                while (go)
                {
                    if (e >= 8) go = FALSE;
                    else if (colorAt(e * 8 + c) == col) ++e;
                    else go = FALSE;
                }
                if (e - r >= 3) RUNS += [1, col, r * 8 + c, e - r];
            }
            r = e;
        }
    }
}

// a celula i participa de uma sequencia de 3+ (usado so para validar troca; a grade em repouso nunca tem combinacao)
integer runAt(integer i)
{
    integer col = colorAt(i);
    if (col < 0) return FALSE;
    integer r = i / 8;
    integer c = i % 8;
    integer n = 1;
    integer k; integer go;
    k = c - 1; go = TRUE;
    while (go) { if (k < 0) go = FALSE; else if (colorAt(r * 8 + k) == col) { ++n; --k; } else go = FALSE; }
    k = c + 1; go = TRUE;
    while (go) { if (k > 7) go = FALSE; else if (colorAt(r * 8 + k) == col) { ++n; ++k; } else go = FALSE; }
    if (n >= 3) return TRUE;
    n = 1;
    k = r - 1; go = TRUE;
    while (go) { if (k < 0) go = FALSE; else if (colorAt(k * 8 + c) == col) { ++n; --k; } else go = FALSE; }
    k = r + 1; go = TRUE;
    while (go) { if (k > 7) go = FALSE; else if (colorAt(k * 8 + c) == col) { ++n; ++k; } else go = FALSE; }
    if (n >= 3) return TRUE;
    return FALSE;
}

integer validSwap(integer a, integer b)
{
    integer d = llAbs(a / 8 - b / 8) + llAbs(a % 8 - b % 8);
    if (d != 1) return FALSE;
    integer x = llList2Integer(G, a);
    integer y = llList2Integer(G, b);
    if (x < 0) return FALSE;
    if (y < 0) return FALSE;
    if (x / 8 == 3) return TRUE;      // rainbow troca com qualquer gema
    if (y / 8 == 3) return TRUE;
    swapG(a, b);
    integer ok = FALSE;
    if (runAt(a)) ok = TRUE;
    if (runAt(b)) ok = TRUE;
    swapG(a, b);
    return ok;
}

integer HINT_A = -1;
integer HINT_B = -1;

// primeira jogada valida na mesma ordem do JS (direita antes de baixo); guarda em HINT_A/HINT_B
integer findHint()
{
    integer r; integer c; integer a;
    for (r = 0; r < 8; ++r)
    {
        for (c = 0; c < 8; ++c)
        {
            a = r * 8 + c;
            if (c < 7)
            {
                if (validSwap(a, a + 1)) { HINT_A = a; HINT_B = a + 1; return TRUE; }
            }
            if (r < 7)
            {
                if (validSwap(a, a + 8)) { HINT_A = a; HINT_B = a + 8; return TRUE; }
            }
        }
    }
    HINT_A = -1;
    HINT_B = -1;
    return FALSE;
}

// ---------- tabuleiro inicial e embaralhar ----------
integer buildInitialBoard(integer colors)
{
    integer attempt; integer r; integer c; integer color; integer bad;
    for (attempt = 0; attempt < 200; ++attempt)
    {
        G = [];
        for (r = 0; r < 8; ++r)
        {
            for (c = 0; c < 8; ++c)
            {
                bad = TRUE;
                while (bad)
                {
                    color = rnd(colors);
                    bad = FALSE;
                    if (c >= 2)
                    {
                        if (llList2Integer(G, r * 8 + c - 1) == color)
                        {
                            if (llList2Integer(G, r * 8 + c - 2) == color) bad = TRUE;
                        }
                    }
                    if (r >= 2)
                    {
                        if (llList2Integer(G, (r - 1) * 8 + c) == color)
                        {
                            if (llList2Integer(G, (r - 2) * 8 + c) == color) bad = TRUE;
                        }
                    }
                }
                G += [color];
            }
        }
        if (findHint()) return TRUE;
    }
    return FALSE;
}

// embaralha mantendo os especiais ate nao haver combinacao pronta e existir jogada
integer shuffleBoard()
{
    list cells = G;
    integer attempt; integer i; integer j; integer x; integer y; integer k;
    for (attempt = 0; attempt < 300; ++attempt)
    {
        for (i = 63; i > 0; --i)
        {
            j = rnd(i + 1);
            x = llList2Integer(cells, i);
            y = llList2Integer(cells, j);
            cells = llListReplaceList(cells, [y], i, i);
            cells = llListReplaceList(cells, [x], j, j);
        }
        G = cells;
        findRuns();
        if (llGetListLength(RUNS) == 0)
        {
            if (findHint()) return TRUE;
        }
    }
    return FALSE;
}

// ---------- resolucao da jogada (cascata) ----------
// Cada onda vira uma string CSV:
//   chain,points,timeBonus, nCleared,<idx>..., nCreated,<idx,val>..., nFalls,<col,de,para,val>..., nSpawns,<col,de,para,val>...
// "de" das quedas/entradas e a linha de origem (entradas novas tem "de" negativo = acima do tabuleiro).
string waveToString(integer chain, integer points, integer tb, list cleared, list created, list falls, list spawns)
{
    list L = [chain, points, tb, llGetListLength(cleared)] + cleared
        + [llGetListLength(created) / 2] + created
        + [llGetListLength(falls) / 4] + falls
        + [llGetListLength(spawns) / 4] + spawns;
    return llDumpList2String(L, ",");
}

// hasSwap = TRUE: a jogada a<->b ja esta trocada em G
resolveMove(integer a, integer b, integer hasSwap)
{
    WAVES = [];
    W_POINTS = 0;
    W_TIME = 0;
    integer first = TRUE;
    integer chain = 0;
    integer guard = 0;
    integer i; integer j; integer k; integer r; integer c; integer idx; integer v; integer sp;
    list CL; list inH; list inV; list created; list cleared; list falls; list spawns; list taken;
    integer forced; integer bonus; integer x; integer y; integer target; integer both; integer n;
    integer grew; integer nb; integer rr; integer cc; integer isFive; integer pos; integer hit;
    integer dir; integer col; integer st; integer len; integer step; integer empties; integer newv;
    integer keep; integer wr; integer cnt; integer tb; float mult; integer points;

    while (guard < 60)
    {
        CL = []; inH = []; inV = [];
        for (i = 0; i < 64; ++i) { CL += [0]; inH += [0]; inV += [0]; }
        created = []; cleared = []; falls = []; spawns = []; taken = [];
        forced = FALSE;
        bonus = 0;

        // rainbow trocado: limpa a cor do vizinho (ou tudo, se forem dois)
        if (first)
        {
            if (hasSwap)
            {
                x = llList2Integer(G, a);
                y = llList2Integer(G, b);
                if (x / 8 == 3 || y / 8 == 3)
                {
                    forced = TRUE;
                    both = FALSE;
                    if (x / 8 == 3) { if (y / 8 == 3) both = TRUE; }
                    if (x / 8 == 3) target = y % 8; else target = x % 8;
                    if (x / 8 == 3) CL = llListReplaceList(CL, [1], a, a);
                    if (y / 8 == 3) CL = llListReplaceList(CL, [1], b, b);
                    for (i = 0; i < 64; ++i)
                    {
                        v = llList2Integer(G, i);
                        if (v >= 0)
                        {
                            if (both) CL = llListReplaceList(CL, [1], i, i);
                            else if (v % 8 == target && v / 8 != 3) CL = llListReplaceList(CL, [1], i, i);
                        }
                    }
                    if (both) bonus += 500; else bonus += 150;
                }
            }
        }

        findRuns();
        n = llGetListLength(RUNS) / 4;
        if (!forced && n == 0) guard = 1000;      // sai do laco (sem "break" em LSL)
        else
        {
            // marca celulas de cada sequencia
            for (k = 0; k < n; ++k)
            {
                dir = llList2Integer(RUNS, k * 4);
                col = llList2Integer(RUNS, k * 4 + 1);
                st = llList2Integer(RUNS, k * 4 + 2);
                len = llList2Integer(RUNS, k * 4 + 3);
                if (dir == 0) step = 1; else step = 8;
                for (j = 0; j < len; ++j)
                {
                    idx = st + j * step;
                    CL = llListReplaceList(CL, [1], idx, idx);
                    if (dir == 0) inH = llListReplaceList(inH, [col + 1], idx, idx);
                    else inV = llListReplaceList(inV, [col + 1], idx, idx);
                }
            }

            // estrela: celula em sequencia horizontal E vertical (ordem: linhas, da esquerda p/ direita, de cima p/ baixo)
            for (i = 0; i < 64; ++i)
            {
                if (llList2Integer(inH, i) > 0)
                {
                    if (llList2Integer(inV, i) > 0)
                    {
                        created += [i, (llList2Integer(inH, i) - 1) + 8 * 2];
                        taken += [i];
                        bonus += 40;
                    }
                }
            }
            // bomba (4) / rainbow (5+): posicao = celula tocada pela troca (so na 1a onda) ou o meio da sequencia
            for (k = 0; k < n; ++k)
            {
                dir = llList2Integer(RUNS, k * 4);
                col = llList2Integer(RUNS, k * 4 + 1);
                st = llList2Integer(RUNS, k * 4 + 2);
                len = llList2Integer(RUNS, k * 4 + 3);
                if (len >= 4)
                {
                    if (dir == 0) step = 1; else step = 8;
                    pos = st + ((len - 1) / 2) * step;
                    if (first)
                    {
                        if (hasSwap)
                        {
                            hit = -1;
                            for (j = 0; j < len; ++j)
                            {
                                idx = st + j * step;
                                if (hit < 0) { if (idx == b || idx == a) hit = idx; }
                            }
                            if (hit >= 0) pos = hit;
                        }
                    }
                    if (llListFindList(taken, [pos]) == -1)
                    {
                        taken += [pos];
                        if (len >= 5) { created += [pos, 3 * 8]; bonus += 100; }       // rainbow (cor 0)
                        else { created += [pos, col + 8 * 1]; bonus += 40; }           // bomba
                    }
                }
            }

            // especiais atingidos disparam em cadeia (fecho do conjunto; cada especial conta uma vez)
            grew = TRUE;
            while (grew)
            {
                grew = FALSE;
                for (i = 0; i < 64; ++i)
                {
                    if (llList2Integer(CL, i) == 1)
                    {
                        v = llList2Integer(G, i);
                        sp = v / 8;
                        if (v >= 0 && (sp == 1 || sp == 2))
                        {
                            r = i / 8; c = i % 8;
                            if (sp == 1)
                            {
                                for (rr = r - 1; rr <= r + 1; ++rr)
                                    for (cc = c - 1; cc <= c + 1; ++cc)
                                        if (rr >= 0 && rr < 8 && cc >= 0 && cc < 8)
                                        {
                                            idx = rr * 8 + cc;
                                            if (llList2Integer(CL, idx) == 0) { CL = llListReplaceList(CL, [1], idx, idx); grew = TRUE; }
                                        }
                            }
                            else
                            {
                                for (cc = 0; cc < 8; ++cc)
                                {
                                    idx = r * 8 + cc;
                                    if (llList2Integer(CL, idx) == 0) { CL = llListReplaceList(CL, [1], idx, idx); grew = TRUE; }
                                }
                                for (rr = 0; rr < 8; ++rr)
                                {
                                    idx = rr * 8 + c;
                                    if (llList2Integer(CL, idx) == 0) { CL = llListReplaceList(CL, [1], idx, idx); grew = TRUE; }
                                }
                            }
                        }
                    }
                }
            }
            // bonus dos especiais disparados: 30 por bomba, 60 por estrela (uma vez cada)
            for (i = 0; i < 64; ++i)
            {
                if (llList2Integer(CL, i) == 1)
                {
                    v = llList2Integer(G, i);
                    if (v >= 0)
                    {
                        if (v / 8 == 1) bonus += 30;
                        if (v / 8 == 2) bonus += 60;
                    }
                }
            }

            // limpa
            for (i = 0; i < 64; ++i)
            {
                if (llList2Integer(CL, i) == 1)
                {
                    if (llList2Integer(G, i) >= 0) cleared += [i];
                    setG(i, -1);
                }
            }
            // especiais criados ocupam a celula limpa
            for (k = 0; k < llGetListLength(created); k += 2) setG(llList2Integer(created, k), llList2Integer(created, k + 1));

            // gravidade + reposicao por cima (mesma ordem de sorteio do JS: coluna 0..7, linhas de baixo p/ cima)
            for (c = 0; c < 8; ++c)
            {
                cnt = 0;
                list colv = []; list colf = [];
                for (r = 7; r >= 0; --r)
                {
                    v = llList2Integer(G, r * 8 + c);
                    if (v >= 0) { colv += [v]; colf += [r]; ++cnt; }
                }
                empties = 8 - cnt;
                r = 7;
                for (k = 0; k < cnt; ++k)
                {
                    setG(r * 8 + c, llList2Integer(colv, k));
                    if (llList2Integer(colf, k) != r) falls += [c, llList2Integer(colf, k), r, llList2Integer(colv, k)];
                    --r;
                }
                for (rr = r; rr >= 0; --rr)
                {
                    newv = rnd(NCOLORS);
                    setG(rr * 8 + c, newv);
                    spawns += [c, rr - empties, rr, newv];
                }
            }

            mult = 1.0 + 0.5 * (float)chain;
            points = roundHalfUp((float)llGetListLength(cleared) * 10.0 * mult + (float)bonus * mult);
            tb = 0;
            if (chain >= 1) tb = 1;
            tb += (llGetListLength(created) / 2) * 2;
            if (forced) tb += 2;
            WAVES += [waveToString(chain, points, tb, cleared, created, falls, spawns)];
            W_POINTS += points;
            W_TIME += tb;
            CLEAREDN += llGetListLength(cleared);
            ++WAVESN;
            if (chain + 1 > MAXCHAIN) MAXCHAIN = chain + 1;
            ++chain;
            first = FALSE;
            ++guard;
        }
    }
}

// ---------- API da partida ----------
newGame(integer diff)
{
    DIFF = diff;
    LEVEL = 1;
    SCORE = 0;
    PROGRESS = 0;
    MAXCHAIN = 1;
    MOVES = 0;
    CLEAREDN = 0;
    WAVESN = 0;
    OVER = FALSE;
    TIMELEFT = (float)llList2Integer(D_START, diff);
    NCOLORS = levelColors(LEVEL, DIFF);
    TARGET = levelTarget(LEVEL, DIFF);
    buildInitialBoard(NCOLORS);
}

integer countSpecials()
{
    integer i; integer n = 0; integer v;
    for (i = 0; i < 64; ++i) { v = llList2Integer(G, i); if (v >= 0) { if (v / 8 > 0) ++n; } }
    return n;
}

// devolve bits: 1 = jogada valida, 2 = subiu de nivel, 4 = embaralhou. 0 = invalida (nada muda).
integer LEVELUP_BONUS = 0;
integer doMove(integer a, integer b)
{
    integer res = 0;
    if (OVER) return 0;
    if (!validSwap(a, b)) return 0;
    res = 1;
    ++MOVES;
    swapG(a, b);
    resolveMove(a, b, TRUE);
    SCORE += W_POINTS;
    PROGRESS += W_POINTS;
    float t = TIMELEFT + (float)W_TIME * llList2Float(D_BONUS, DIFF);
    float cap = (float)timeCap(DIFF);
    if (t > cap) t = cap;
    TIMELEFT = t;
    LEVELUP_BONUS = 0;
    if (PROGRESS >= TARGET)
    {
        integer done = LEVEL;
        LEVELUP_BONUS = 250 * done + countSpecials() * 100;
        SCORE += LEVELUP_BONUS;
        LEVEL = done + 1;
        PROGRESS = 0;
        NCOLORS = levelColors(LEVEL, DIFF);
        TARGET = levelTarget(LEVEL, DIFF);
        TIMELEFT = TIMELEFT + (float)levelTimeBonus(done, DIFF);
        if (TIMELEFT > cap) TIMELEFT = cap;
        buildInitialBoard(NCOLORS);
        res += 2;
    }
    else
    {
        if (!findHint())
        {
            shuffleBoard();
            res += 4;
        }
    }
    return res;
}

// desconta o tempo; devolve TRUE quando acabou
integer tick(float dt)
{
    if (OVER) return TRUE;
    TIMELEFT -= dt * levelDrain(LEVEL, DIFF);
    if (TIMELEFT <= 0.0) { TIMELEFT = 0.0; OVER = TRUE; return TRUE; }
    return FALSE;
}

// avisa se o script foi compilado como LSL comum (16 KB) em vez de Mono (64 KB): e a causa de "Stack-Heap Collision"
checkMem()
{
    if (llGetMemoryLimit() <= 16384)
        llOwnerSay("ERRO: GEMS_LOGIC esta compilado como LSL comum (16 KB de memoria). Abra o script, marque MONO, salve e marque Running.");
    else llOwnerSay("GEMS_LOGIC: memoria livre " + (string)llGetFreeMemory() + " de " + (string)llGetMemoryLimit() + " bytes.");
}

default
{
    state_entry() { G = []; checkMem(); }

    link_message(integer sender, integer num, string str, key id)
    {
        if (num == 10)
        {
            newGame((integer)str);
            llMessageLinked(LINK_SET, 100, llDumpList2String(G, ","), "");
            llMessageLinked(LINK_SET, 101, llDumpList2String([SCORE, LEVEL, PROGRESS, TARGET, MAXCHAIN, (integer)TIMELEFT], ","), "");
        }
        else if (num == 20)
        {
            list p = llParseString2List(str, [","], []);
            integer res = doMove((integer)llList2String(p, 0), (integer)llList2String(p, 1));
            llMessageLinked(LINK_SET, 200, llDumpList2String([res, SCORE, LEVEL, PROGRESS, TARGET, MAXCHAIN, (integer)TIMELEFT, LEVELUP_BONUS, MOVES], ","), "");
            if (res & 1) llMessageLinked(LINK_SET, 210, llDumpList2String(WAVES, "|"), "");
            // nivel novo / embaralhou: a grade NOVA so pode ser mostrada DEPOIS da animacao das ondas desta jogada.
            if (res & 6) llMessageLinked(LINK_SET, 110, llDumpList2String(G, ","), "");
        }
        else if (num == 30)
        {
            if (tick((float)str)) llMessageLinked(LINK_SET, 300, llDumpList2String([SCORE, LEVEL, MAXCHAIN, MOVES, CLEAREDN, WAVESN, DIFF], ","), "");
        }
        else if (num == 40)
        {
            if (findHint()) llMessageLinked(LINK_SET, 400, (string)HINT_A + "," + (string)HINT_B, "");
            else llMessageLinked(LINK_SET, 400, "-1", "");
        }
        else if (num == 250)                 // a camada visual reiniciou: devolve a grade LOGICA atual (fonte da verdade)
        {
            if (llGetListLength(G) == 64) llMessageLinked(LINK_SET, 100, llDumpList2String(G, ","), "");
        }
    }
}
