// GEMS_BOARD.lsl - estado da partida, toque e HUD do Concierge Gems 2.0 (sem MOAP). PRIM RAIZ.
//
// MUDOU NA 2.0: este script NAO desenha mais gema nenhuma. A camada visual (64 prims moveis CG_GEM_*)
// pertence ao GEMS_ANIMATION. Aqui ficam: quem esta jogando, o clique nas celulas, o placar, as barras,
// o relogio da partida e a ordem das mensagens.
//
// Ordem de uma jogada:
//   toque -> LOGIC (msg 20) decide -> devolve 200 + 210
//   -> BOARD monta "a,b,valido|ondas" e manda para o ANIMATION (msg 211)
//   -> ANIMATION anima tudo e responde 230 -> BOARD libera o toque
//
// Le os UUIDs do notecard "CG_CONFIG" (ver docs/). Sem UUID, usa a textura de mesmo nome no inventario do objeto.

// ---------- constantes de layout (px do jogo original -> fracao da face) ----------
float CELL_F = 0.125;        // 1/8 da largura do tabuleiro
integer NCELL = 64;

// ---------- config (notecard) ----------
string  TEX_GEMS = "";       // atlas 1024x512 com as 8 gemas (4 colunas x 2 linhas)
string  TEX_FX = "";         // atlas de explosao (4x4 quadros)
string  TEX_DIGITS = "";     // atlas de digitos 0-9 + sinais (4x4)
string  TEX_BLANK = "";      // transparente
integer SOUND_ON = TRUE;
string  API_URL = "";        // opcional: sincronizacao com o Concierge OS
string  MACHINE_ID = "";
string  MACHINE_SECRET = "";
string  LAND_ID = "";

// ---------- links achados ----------
list CELL_LINK;              // 64 links na ordem indice 0..63
integer LINK_SEL = 0;
integer LINK_BTN_PLAY = 0;
integer LINK_BTN_PAUSE = 0;
integer LINK_BAR_TIME = 0;
integer LINK_BAR_PROG = 0;
integer LINK_TOAST = 0;
list DIG_SCORE; list DIG_BEST; list DIG_LEVEL; list DIG_TIME; list DIG_COMBO;

// ---------- estado ----------
integer MODE = 0;            // 0 parado, 1 jogando, 2 pausado, 3 fim
key PLAYER = NULL_KEY;
string PLAYER_NAME = "";
integer DIFF = 1;
integer SEL = -1;            // celula selecionada (-1 nenhuma)
list GRID;                   // copia local para desenhar
integer SCORE = 0; integer BEST = 0; integer LEVEL = 1; integer COMBO = 1;
integer TIMEI = 0; integer PROGRESS = 0; integer TARGET = 900;
integer BUSY = FALSE;        // animacao em curso: ignora toques (eles entram na fila)
integer BUSY_SINCE = 0;
integer QUEUED_A = -1; integer QUEUED_B = -1;
integer MOVE_A = -1; integer MOVE_B = -1;   // jogada que o ANIMATION vai animar
integer MOVE_ID = 0;
string  PEND_GRID = "";                     // grade nova (nivel/embaralhar) aguardando o fim da animacao
integer PEND_KIND = 0;                      // 2 = subiu de nivel, 4 = embaralhou
float   TICK = 0.5;          // relogio do jogo (o tempo cai em passos de 0,5 s)
integer LAST_ACTION = 0;
integer HINT_A = -1; integer HINT_B = -1;
integer DIFF_CHAN = 0;
integer DIFF_LISTEN = 0;
key DIFF_AV = NULL_KEY;

// ---------- util ----------
integer cellLink(integer i) { return llList2Integer(CELL_LINK, i); }

// moldura de selecao sobre a celula i (-1 esconde)
showSel(integer i)
{
    if (LINK_SEL <= 1) return;
    if (i < 0)
    {
        llSetLinkAlpha(LINK_SEL, 0.0, ALL_SIDES);
        return;
    }
    vector pos = llList2Vector(llGetLinkPrimitiveParams(cellLink(i), [PRIM_POS_LOCAL]), 0);
    llSetLinkPrimitiveParamsFast(LINK_SEL, [PRIM_POS_LOCAL, pos + <0.0, 0.0, 0.002>, PRIM_COLOR, ALL_SIDES, <1,1,1>, 0.85]);
}

// ---------- HUD: digitos por atlas (4x4: 0..9) ----------
paintNumber(list links, integer value)
{
    integer n = llGetListLength(links);
    if (n == 0) return;
    list p = [];
    integer k;
    integer v = value;
    for (k = n - 1; k >= 0; --k)
    {
        integer d = v % 10;
        v = v / 10;
        integer hide = FALSE;
        if (k < n - 1) { if (value < 1) hide = TRUE; }
        if (v == 0) { if (d == 0) { if (k < n - 1) { if (value / (integer)llPow(10.0, (float)(n - 1 - k)) == 0) hide = TRUE; } } }
        float a = 1.0;
        if (hide) a = 0.0;
        integer col = d % 4;
        integer row = d / 4;
        p += [PRIM_LINK_TARGET, llList2Integer(links, k),
              PRIM_TEXTURE, ALL_SIDES, TEX_DIGITS, <0.25, 0.25, 0.0>,
              <-0.375 + (float)col * 0.25, 0.375 - (float)row * 0.25, 0.0>, 0.0,
              PRIM_COLOR, ALL_SIDES, <1,1,1>, a,
              PRIM_FULLBRIGHT, ALL_SIDES, TRUE];
    }
    llSetLinkPrimitiveParamsFast(LINK_THIS, p);
}

// barra: escala em X mantendo a borda esquerda no lugar
setBar(integer link, float frac, vector color)
{
    if (link <= 1) return;
    if (frac < 0.0) frac = 0.0;
    if (frac > 1.0) frac = 1.0;
    list pr = llGetLinkPrimitiveParams(link, [PRIM_SIZE, PRIM_POS_LOCAL]);
    vector sz = llList2Vector(pr, 0);
    vector po = llList2Vector(pr, 1);
    float full = (float)llLinksetDataRead("bar_full_" + (string)link);
    if (full <= 0.0) { full = sz.x; llLinksetDataWrite("bar_full_" + (string)link, (string)full); }
    float x0 = (float)llLinksetDataRead("bar_x0_" + (string)link);
    if (x0 == 0.0) { x0 = po.x - full * 0.5; llLinksetDataWrite("bar_x0_" + (string)link, (string)x0); }
    float w = full * frac;
    if (w < 0.001) w = 0.001;
    llSetLinkPrimitiveParamsFast(link, [PRIM_SIZE, <w, sz.y, sz.z>,
        PRIM_POS_LOCAL, <x0 + w * 0.5, po.y, po.z>,
        PRIM_COLOR, ALL_SIDES, color, 1.0, PRIM_FULLBRIGHT, ALL_SIDES, TRUE]);
}

updateHud()
{
    paintNumber(DIG_SCORE, SCORE);
    paintNumber(DIG_BEST, BEST);
    paintNumber(DIG_LEVEL, LEVEL);
    paintNumber(DIG_COMBO, COMBO);
    paintNumber(DIG_TIME, TIMEI);
    integer cap = 156;
    if (DIFF == 1) cap = 117;
    if (DIFF == 2) cap = 91;
    vector tc = <0.0, 0.9, 0.78>;
    if (TIMEI <= 15) tc = <1.0, 0.37, 0.48>;
    setBar(LINK_BAR_TIME, (float)TIMEI / (float)cap, tc);
    float pf = 0.0;
    if (TARGET > 0) pf = (float)PROGRESS / (float)TARGET;
    setBar(LINK_BAR_PROG, pf, <1.0, 0.76, 0.29>);
}

releaseInput()
{
    BUSY = FALSE;
    BUSY_SINCE = 0;
    if (QUEUED_A >= 0)
    {
        integer a = QUEUED_A;
        integer b = QUEUED_B;
        QUEUED_A = -1;
        BUSY = TRUE;
        BUSY_SINCE = llGetUnixTime();
        MOVE_A = a;
        MOVE_B = b;
        ++MOVE_ID;
        llMessageLinked(LINK_SET, 20, (string)a + "," + (string)b, "");
    }
}

toast(string msg)
{
    if (LINK_TOAST == 0) return;
    llSetLinkPrimitiveParamsFast(LINK_TOAST, [PRIM_TEXT, msg, <1.0, 0.89, 0.60>, 1.0]);
    llSetTimerEvent(TICK);
}

// ---------- descoberta dos prims ----------
findLinks()
{
    CELL_LINK = [];
    integer i;
    for (i = 0; i < NCELL; ++i) CELL_LINK += [0];
    DIG_SCORE = []; DIG_BEST = []; DIG_LEVEL = []; DIG_TIME = []; DIG_COMBO = [];
    list ds = []; list db = []; list dl = []; list dt = []; list dc = [];
    integer n = llGetNumberOfPrims();
    integer k;
    integer missing = 0;
    for (k = 1; k <= n; ++k)
    {
        string nm = llGetLinkName(k);
        if (llGetSubString(nm, 0, 7) == "CG_CELL_")
        {
            list p = llParseString2List(llGetSubString(nm, 8, -1), ["_"], []);
            integer r = (integer)llList2String(p, 0);
            integer c = (integer)llList2String(p, 1);
            if (r >= 0 && r < 8) { if (c >= 0 && c < 8) CELL_LINK = llListReplaceList(CELL_LINK, [k], r * 8 + c, r * 8 + c); }
        }
        else if (nm == "CG_SEL") LINK_SEL = k;
        else if (nm == "CG_BTN_PLAY") LINK_BTN_PLAY = k;
        else if (nm == "CG_BTN_PAUSE") LINK_BTN_PAUSE = k;
        else if (nm == "CG_BAR_TIME") LINK_BAR_TIME = k;
        else if (nm == "CG_BAR_PROG") LINK_BAR_PROG = k;
        else if (nm == "CG_TOAST") LINK_TOAST = k;
        else if (llGetSubString(nm, 0, 10) == "CG_D_SCORE_") ds += [k];
        else if (llGetSubString(nm, 0, 9) == "CG_D_BEST_") db += [k];
        else if (llGetSubString(nm, 0, 10) == "CG_D_LEVEL_") dl += [k];
        else if (llGetSubString(nm, 0, 9) == "CG_D_TIME_") dt += [k];
        else if (llGetSubString(nm, 0, 10) == "CG_D_COMBO_") dc += [k];
    }
    DIG_SCORE = ds; DIG_BEST = db; DIG_LEVEL = dl; DIG_TIME = dt; DIG_COMBO = dc;
    for (i = 0; i < NCELL; ++i) { if (cellLink(i) == 0) ++missing; }
    llOwnerSay("Concierge Gems (nativo): " + (string)(NCELL - missing) + "/64 celulas, selecao=" + (string)LINK_SEL
        + ", play=" + (string)LINK_BTN_PLAY + ", barras=" + (string)LINK_BAR_TIME + "/" + (string)LINK_BAR_PROG
        + ", digitos score/best/level/time/combo=" + (string)llGetListLength(ds) + "/" + (string)llGetListLength(db)
        + "/" + (string)llGetListLength(dl) + "/" + (string)llGetListLength(dt) + "/" + (string)llGetListLength(dc));
    if (missing > 0) llOwnerSay("ATENCAO: faltam " + (string)missing + " celulas CG_CELL_<linha>_<coluna> (0..7). Rode o GEMS_BUILDER.");
}

// ---------- config ----------
key CFG_Q; integer CFG_LINE;
readConfig()
{
    if (llGetInventoryType("CG_CONFIG") != INVENTORY_NOTECARD)
    {
        llOwnerSay("Sem notecard CG_CONFIG: usando texturas do inventario pelo nome.");
        TEX_GEMS = "CG_gems_atlas_1024x512"; TEX_FX = "CG_fx_atlas_1024x1024"; TEX_DIGITS = "CG_digits_atlas_512x512";
        llMessageLinked(LINK_SET, 502, TEX_GEMS + "|" + TEX_FX, "");
        return;
    }
    CFG_LINE = 0;
    CFG_Q = llGetNotecardLine("CG_CONFIG", 0);
}

applyConfig(string line)
{
    line = llStringTrim(line, STRING_TRIM);
    if (line == "") return;
    if (llGetSubString(line, 0, 0) == "#") return;
    integer p = llSubStringIndex(line, "=");
    if (p < 1) return;
    string k = llStringTrim(llGetSubString(line, 0, p - 1), STRING_TRIM);
    string v = "";
    if (p < llStringLength(line) - 1) v = llStringTrim(llGetSubString(line, p + 1, -1), STRING_TRIM);
    if (k == "TEX_GEMS") TEX_GEMS = v;
    else if (k == "TEX_FX") TEX_FX = v;
    else if (k == "TEX_DIGITS") TEX_DIGITS = v;
    else if (k == "SOUND") SOUND_ON = (integer)v;
    else if (k == "API_URL") API_URL = v;
    else if (k == "LAND_ID") LAND_ID = v;
    else if (k == "MACHINE_ID") MACHINE_ID = v;
    else if (k == "MACHINE_SECRET") MACHINE_SECRET = v;
}

// ---------- jogo ----------
sfx(string name) { if (SOUND_ON) llMessageLinked(LINK_SET, 500, name, ""); }

chooseDifficulty(key av)
{
    if (MODE == 1) { llRegionSayTo(av, 0, "Partida em andamento."); return; }
    if (DIFF_LISTEN != 0) llListenRemove(DIFF_LISTEN);
    DIFF_AV = av;
    DIFF_CHAN = -100000 - (integer)llFrand(900000.0);
    DIFF_LISTEN = llListen(DIFF_CHAN, "", av, "");
    llDialog(av,
        "Escolha a dificuldade do Concierge Gems:",
        ["FACIL", "NORMAL", "DIFICIL"],
        DIFF_CHAN);
}

startGame(key av)
{
    if (DIFF_LISTEN != 0) { llListenRemove(DIFF_LISTEN); DIFF_LISTEN = 0; }
    DIFF_AV = NULL_KEY;
    PLAYER = av;
    PLAYER_NAME = llGetDisplayName(av);
    MODE = 1;
    SEL = -1;
    BUSY = TRUE;
    BUSY_SINCE = llGetUnixTime();
    QUEUED_A = -1;
    COMBO = 1;
    BEST = (integer)llLinksetDataRead("best_" + (string)DIFF);
    llMessageLinked(LINK_SET, 10, (string)DIFF, "");     // LOGIC: novo jogo
    sfx("start");
    LAST_ACTION = llGetUnixTime();
    llSetTimerEvent(TICK);
    toast("BOA SORTE, " + PLAYER_NAME);
}

endGame()
{
    MODE = 3;
    BUSY = FALSE;
    BUSY_SINCE = 0;
    showSel(-1);
    sfx("gameover");
    if (SCORE > BEST) { BEST = SCORE; llLinksetDataWrite("best_" + (string)DIFF, (string)BEST); }
    toast("FIM DE JOGO - " + (string)SCORE + " PONTOS");
    llMessageLinked(LINK_SET, 600, llDumpList2String([(string)PLAYER, PLAYER_NAME, SCORE, LEVEL, COMBO, DIFF], "|"), "");
    PLAYER = NULL_KEY;
    updateHud();
}

// toque numa celula: primeira selecao, ou jogada se for vizinha
onCellTouch(integer idx, key av)
{
    if (MODE != 1) return;
    if (av != PLAYER) { llRegionSayTo(av, 0, "Partida de " + PLAYER_NAME + " em andamento."); return; }
    LAST_ACTION = llGetUnixTime();
    if (HINT_A >= 0) llMessageLinked(LINK_SET, 521, (string)HINT_A + "," + (string)HINT_B, "");
    HINT_A = -1; HINT_B = -1;
    if (BUSY)
    {
        if (SEL >= 0) { QUEUED_A = SEL; QUEUED_B = idx; }     // guarda a jogada para quando liberar
        else SEL = idx;
        return;
    }
    if (SEL < 0) { SEL = idx; showSel(idx); sfx("select"); return; }
    if (SEL == idx) { SEL = -1; showSel(-1); return; }
    integer d = llAbs(SEL / 8 - idx / 8) + llAbs(SEL % 8 - idx % 8);
    if (d != 1) { SEL = idx; showSel(idx); sfx("select"); return; }
    integer a = SEL;
    SEL = -1;
    showSel(-1);
    BUSY = TRUE;
    BUSY_SINCE = llGetUnixTime();
    MOVE_A = a;
    MOVE_B = idx;
    ++MOVE_ID;
    llMessageLinked(LINK_SET, 20, (string)a + "," + (string)idx, "");   // LOGIC: jogada
}

// avisa se o script foi compilado como LSL comum (16 KB) em vez de Mono (64 KB): e a causa de "Stack-Heap Collision"
checkMem()
{
    if (llGetMemoryLimit() <= 16384)
        llOwnerSay("ERRO: GEMS_BOARD esta compilado como LSL comum (16 KB de memoria). Abra o script, marque MONO, salve e marque Running.");
    else llOwnerSay("GEMS_BOARD: memoria livre " + (string)llGetFreeMemory() + " de " + (string)llGetMemoryLimit() + " bytes.");
}

default
{
    state_entry()
    {
        checkMem();
        findLinks();
        readConfig();
        llLinksetDataWrite("ver", "1.0.0");
        BEST = (integer)llLinksetDataRead("best_1");
        llSetTimerEvent(2.0);
    }

    on_rez(integer p) { llResetScript(); }

    changed(integer c)
    {
        if (c & (CHANGED_LINK | CHANGED_OWNER | CHANGED_REGION_START)) llResetScript();
        if (c & CHANGED_INVENTORY) readConfig();
    }

    dataserver(key q, string data)
    {
        if (q != CFG_Q) return;
        if (data == EOF)
        {
            if (TEX_GEMS == "" || llSubStringIndex(llToLower(TEX_GEMS), "digit") >= 0) TEX_GEMS = "CG_gems_atlas_1024x512";
            if (TEX_FX == "") TEX_FX = "CG_fx_atlas_1024x1024";
            if (TEX_DIGITS == "") TEX_DIGITS = "CG_digits_atlas_512x512";
            llOwnerSay("CG_CONFIG lido (" + (string)CFG_LINE + " linhas).");
            // ANIMATION e FX desenham as gemas e a explosao: recebem os nomes/UUIDs das texturas daqui (msg 502)
            llMessageLinked(LINK_SET, 502, TEX_GEMS + "|" + TEX_FX, "");
            return;
        }
        applyConfig(data);
        ++CFG_LINE;
        CFG_Q = llGetNotecardLine("CG_CONFIG", CFG_LINE);
    }

    touch_start(integer n)
    {
        integer link = llDetectedLinkNumber(0);
        key av = llDetectedKey(0);
        string nm = llGetLinkName(link);
        if (nm == "CG_BTN_PLAY")
        {
            chooseDifficulty(av);
            return;
        }
        if (nm == "CG_BTN_PAUSE")
        {
            if (av != PLAYER) return;
            if (MODE == 1) { MODE = 2; toast("PAUSADO"); }
            else if (MODE == 2) { MODE = 1; toast(""); LAST_ACTION = llGetUnixTime(); }
            return;
        }
        integer i = llListFindList(CELL_LINK, [link]);
        if (i >= 0)
        {
            if (MODE == 0 || MODE == 3) { chooseDifficulty(av); return; }     // tocar na tela parada abre dificuldade
            onCellTouch(i, av);
            return;
        }
        if (llSubStringIndex(nm, "CG_GEM_") == 0)
        {
            // a gema fica NA FRENTE da celula e recebe o toque: o ANIMATION diz em que celula ela esta agora (240 -> 241)
            if (MODE == 0 || MODE == 3) { chooseDifficulty(av); return; }
            llMessageLinked(LINK_SET, 240, llGetSubString(nm, 7, -1), av);
        }
    }

    listen(integer channel, string name, key id, string msg)
    {
        if (channel != DIFF_CHAN) return;
        if (id != DIFF_AV) return;
        if (msg == "FACIL") DIFF = 0;
        else if (msg == "NORMAL") DIFF = 1;
        else if (msg == "DIFICIL") DIFF = 2;
        else return;
        if (DIFF_LISTEN != 0) { llListenRemove(DIFF_LISTEN); DIFF_LISTEN = 0; }
        startGame(id);
    }

    link_message(integer sender, integer num, string str, key id)
    {
        if (num == 241)                      // celula onde esta a gema tocada
        {
            integer tc = (integer)str;
            if (tc >= 0) onCellTouch(tc, id);
            return;
        }
        if (num == 250)                      // o ANIMATION reiniciou: a jogada que ele animava se perdeu; libera o toque
        {                                    // (a grade certa vem da LOGIC, que responde ao mesmo 250 com a msg 100)
            BUSY = FALSE;
            BUSY_SINCE = 0;
            QUEUED_A = -1;
        }
        else if (num == 101)                 // hud inicial
        {
            list p = llCSV2List(str);
            SCORE = (integer)llList2String(p, 0);
            LEVEL = (integer)llList2String(p, 1);
            PROGRESS = (integer)llList2String(p, 2);
            TARGET = (integer)llList2String(p, 3);
            TIMEI = (integer)llList2String(p, 5);
            updateHud();
            BUSY = FALSE;
            BUSY_SINCE = 0;
        }
        else if (num == 200)                 // resultado da jogada
        {
            list p = llCSV2List(str);
            integer code = (integer)llList2String(p, 0);
            if (code == 0)
            {
                toast("MOVIMENTO INVALIDO");
                // o ANIMATION empurra as duas gemas e traz de volta; o som sai la, junto do movimento
                llMessageLinked(LINK_SET, 211, (string)MOVE_ID + "," + (string)MOVE_A + "," + (string)MOVE_B + ",0", "");
                return;
            }
            PEND_KIND = code & 6;
            SCORE = (integer)llList2String(p, 1);
            LEVEL = (integer)llList2String(p, 2);
            PROGRESS = (integer)llList2String(p, 3);
            TARGET = (integer)llList2String(p, 4);
            COMBO = (integer)llList2String(p, 5);
            TIMEI = (integer)llList2String(p, 6);
            if (SCORE > BEST) BEST = SCORE;
            updateHud();
            if (code & 2) { sfx("levelup"); toast("LEVEL " + (string)LEVEL); }
            if (code & 4) { sfx("shuffle"); toast("SEM JOGADAS - EMBARALHANDO"); }
        }
        else if (num == 210)                 // ondas: manda para o ANIMATION com a jogada no cabecalho
        {
            llMessageLinked(LINK_SET, 211,
                (string)MOVE_ID + "," + (string)MOVE_A + "," + (string)MOVE_B + ",1|" + str, "");
        }
        else if (num == 110)                 // grade nova (nivel/embaralhar): guarda ate a animacao das ondas acabar
        {
            PEND_GRID = str;
        }
        else if (num == 230)                 // ANIMATION terminou de animar
        {
            integer doneId = (integer)str;
            if (doneId != MOVE_ID) return;
            if (PEND_GRID != "")               // ainda falta a transicao do tabuleiro novo
            {
                string g = PEND_GRID;
                PEND_GRID = "";
                if (PEND_KIND & 2) llMessageLinked(LINK_SET, 111, g, "");      // explode o tabuleiro e entram gemas novas
                else if (PEND_KIND & 4) llMessageLinked(LINK_SET, 112, g, ""); // embaralha (gemas deslizam)
                PEND_KIND = 0;
                return;
            }
            releaseInput();
        }
        else if (num == 300)                 // acabou o tempo
        {
            endGame();
        }
        else if (num == 400)                 // dica
        {
            if (str != "-1")
            {
                list p = llCSV2List(str);
                HINT_A = (integer)llList2String(p, 0);
                HINT_B = (integer)llList2String(p, 1);
                llMessageLinked(LINK_SET, 520, (string)HINT_A + "," + (string)HINT_B, "");
            }
        }
    }

    timer()
    {
        if (MODE == 1)
        {
            if (BUSY)
            {
                if (BUSY_SINCE > 0)
                {
                    if (llGetUnixTime() - BUSY_SINCE > 5)
                    {
                        llMessageLinked(LINK_SET, 250, "", "");
                        releaseInput();
                    }
                }
            }
            if (!BUSY)
            {
                llMessageLinked(LINK_SET, 30, (string)TICK, "");
                TIMEI = TIMEI - 1;
                if (TIMEI < 0) TIMEI = 0;
                updateHud();
                integer idle = llGetUnixTime() - LAST_ACTION;
                integer wait = 7;
                if (DIFF == 0) wait = 5;
                if (DIFF == 2) wait = 12;
                if (idle > wait) { if (HINT_A < 0) llMessageLinked(LINK_SET, 40, "", ""); }
                if (TIMEI > 0) { if (TIMEI <= 10) sfx("tick"); }
                // abandono: 90 s sem tocar encerra e libera o painel
                if (idle > 90) endGame();
            }
        }
    }
}
