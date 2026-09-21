// GEMS_RENDER_CONTROLLER.lsl - coordena GEMS_RENDER_A/B/C/D.
// Mantem somente o mapa logico das 64 gemas; nao move prims diretamente.

float SWAP_DUR = 0.20;
float POP_DUR = 0.14;
float FALL_BASE = 0.08;
float FALL_ROW = 0.035;
float FALL_MAX = 0.28;
float SPAWN_EXTRA = 0.02;

integer ST_IDLE = 0;
integer ST_SWAP = 1;
integer ST_SWAPBACK = 2;
integer ST_POP = 3;
integer ST_FALL = 4;
integer STATE = 0;

list GEM_CELL;
list GEM_VAL;
list AT_CELL;
list GEM_LINK;
string WAVES_STR = "";
list W_CLEARED;
list W_CREATED;
list W_FALLS;
list W_SPAWNS;
integer W_CHAIN;
integer DONE_MASK = 0;
integer READY_MASK = 0;
integer EXPECT_MASK = 15;
integer SWAP_A = -1;
integer SWAP_B = -1;
integer SWAP_OK = FALSE;
string BACK_MOVES = "";
float WAIT_PAD = 0.22;
integer ACTIVE_MOVE_ID = 0;

integer gemLink(integer g) { return llList2Integer(GEM_LINK, g); }

findGemLinks()
{
    GEM_LINK = [];
    integer i;
    for (i = 0; i < 64; ++i) GEM_LINK += [0];
    integer n = llGetNumberOfPrims();
    integer k;
    integer found = 0;
    for (k = 1; k <= n; ++k)
    {
        string nm = llGetLinkName(k);
        if (llGetSubString(nm, 0, 6) == "CG_GEM_")
        {
            integer g = (integer)llGetSubString(nm, 7, -1);
            if (g >= 0 && g < 64)
            {
                if (llList2Integer(GEM_LINK, g) == 0) ++found;
                GEM_LINK = llListReplaceList(GEM_LINK, [k], g, g);
            }
        }
    }
    llOwnerSay("GEMS_RENDER_CONTROLLER: links de gemas " + (string)found + "/64.");
}

integer shardBit(string s)
{
    if (s == "A") return 1;
    if (s == "B") return 2;
    if (s == "C") return 4;
    if (s == "D") return 8;
    return 0;
}

integer takeFree()
{
    integer i;
    for (i = 0; i < 64; ++i)
    {
        if (llList2Integer(GEM_CELL, i) == -1) return i;
    }
    return -1;
}

integer codeVirtual(integer r, integer c)
{
    return -1 - ((-r) * 8 + c);
}

integer codeSpawn(integer cell)
{
    return -1000 - cell;
}

sendSet(string body)
{
    if (body != "") llMessageLinked(LINK_SET, 721, body, "");
}

sendMove(integer easeKind, string body)
{
    DONE_MASK = 0;
    if (body == "")
    {
        DONE_MASK = EXPECT_MASK;
        return;
    }
    llMessageLinked(LINK_SET, 722, (string)ACTIVE_MOVE_ID + "|" + (string)easeKind + "|" + body, "");
    llSetTimerEvent(maxDur(body) + WAIT_PAD);
}

sendHide(string body)
{
    if (body != "") llMessageLinked(LINK_SET, 723, body, "");
}

integer findGemAtCell(integer cell)
{
    integer g;
    for (g = 0; g < 64; ++g)
    {
        if (llList2Integer(GEM_CELL, g) == cell) return g;
    }
    return -1;
}

integer findGemInColumn(integer col, integer val, list used)
{
    integer g;
    for (g = 0; g < 64; ++g)
    {
        integer cell = llList2Integer(GEM_CELL, g);
        if (cell >= 0)
        {
            if (cell % 8 == col)
            {
                if (llList2Integer(GEM_VAL, g) == val)
                {
                    if (llListFindList(used, [g]) < 0) return g;
                }
            }
        }
    }
    return -1;
}

syncVisual()
{
    string body = "";
    integer g;
    for (g = 0; g < 64; ++g)
    {
        integer cell = llList2Integer(GEM_CELL, g);
        integer val = llList2Integer(GEM_VAL, g);
        if (cell >= 0 && val >= 0)
        {
            if (body != "") body += "|";
            body += (string)g + "," + (string)cell + "," + (string)val;
        }
    }
    sendSet(body);
}

finish()
{
    llSetTimerEvent(0.0);
    syncVisual();
    STATE = ST_IDLE;
    WAVES_STR = "";
    W_CLEARED = [];
    W_CREATED = [];
    W_FALLS = [];
    W_SPAWNS = [];
    llMessageLinked(LINK_SET, 230, (string)ACTIVE_MOVE_ID, "");
}

float maxDur(string body)
{
    float mx = 0.0;
    list rows = llParseString2List(body, ["|"], []);
    integer n = llGetListLength(rows);
    integer i;
    for (i = 0; i < n; ++i)
    {
        list p = llCSV2List(llList2String(rows, i));
        float d = (float)llList2String(p, 3);
        if (d > mx) mx = d;
    }
    if (mx < 0.05) mx = 0.05;
    return mx;
}

afterDone()
{
    llSetTimerEvent(0.0);
    if (STATE == ST_SWAP)
    {
        if (WAVES_STR != "") nextWave();
        else finish();
    }
    else if (STATE == ST_SWAPBACK)
    {
        if (BACK_MOVES != "")
        {
            string back = BACK_MOVES;
            BACK_MOVES = "";
            sendMove(0, back);
        }
        else finish();
    }
    else if (STATE == ST_FALL)
    {
        nextWave();
    }
}

resetFromGrid(list grid)
{
    GEM_CELL = [];
    GEM_VAL = [];
    AT_CELL = [];
    string body = "";
    integer i;
    for (i = 0; i < 64; ++i)
    {
        integer v = llList2Integer(grid, i);
        GEM_CELL += [i];
        GEM_VAL += [v];
        AT_CELL += [i];
        if (body != "") body += "|";
        body += (string)i + "," + (string)i + "," + (string)v;
    }
    sendSet(body);
}

parseWave(string w)
{
    list v = llCSV2List(w);
    W_CHAIN = (integer)llList2String(v, 0);
    integer nc = (integer)llList2String(v, 3);
    W_CLEARED = [];
    integer k;
    for (k = 0; k < nc; ++k) W_CLEARED += [(integer)llList2String(v, 4 + k)];
    integer i = 4 + nc;
    integer ncr = (integer)llList2String(v, i); ++i;
    W_CREATED = [];
    for (k = 0; k < ncr * 2; ++k) W_CREATED += [(integer)llList2String(v, i + k)];
    i += ncr * 2;
    integer nf = (integer)llList2String(v, i); ++i;
    W_FALLS = [];
    for (k = 0; k < nf * 4; ++k) W_FALLS += [(integer)llList2String(v, i + k)];
    i += nf * 4;
    integer ns = (integer)llList2String(v, i); ++i;
    W_SPAWNS = [];
    for (k = 0; k < ns * 4; ++k) W_SPAWNS += [(integer)llList2String(v, i + k)];
}

nextWave()
{
    if (WAVES_STR == "") { finish(); return; }
    integer sep = llSubStringIndex(WAVES_STR, "|");
    string w = WAVES_STR;
    if (sep >= 0)
    {
        w = llGetSubString(WAVES_STR, 0, sep - 1);
        WAVES_STR = llGetSubString(WAVES_STR, sep + 1, -1);
    }
    else WAVES_STR = "";
    parseWave(w);
    string fx = "";
    integer especial = FALSE;
    integer n = llGetListLength(W_CLEARED);
    integer k;
    for (k = 0; k < n; ++k)
    {
        integer cell = llList2Integer(W_CLEARED, k);
        integer g = llList2Integer(AT_CELL, cell);
        if (g >= 0)
        {
            integer link = gemLink(g);
            integer val = llList2Integer(GEM_VAL, g);
            if (link > 1)
            {
                if (fx != "") fx += "|";
                fx += (string)link + "," + (string)val;
            }
            if (val / 8 > 0) especial = TRUE;
        }
    }
    llMessageLinked(LINK_SET, 500, "match" + (string)W_CHAIN, "");
    if (especial) llMessageLinked(LINK_SET, 500, "blast_bomb", "");
    if (fx != "") llMessageLinked(LINK_SET, 530, fx, "");
    STATE = ST_POP;
    llSetTimerEvent(POP_DUR);
}

beginFall()
{
    integer k;
    string hide = "";
    string stopS = "";
    integer n = llGetListLength(W_CLEARED);
    for (k = 0; k < n; ++k)
    {
        integer cell = llList2Integer(W_CLEARED, k);
        integer g = llList2Integer(AT_CELL, cell);
        if (g >= 0)
        {
            if (hide != "") hide += ",";
            hide += (string)g;
            integer link = gemLink(g);
            if (link > 1)
            {
                if (stopS != "") stopS += "|";
                stopS += (string)link;
            }
            GEM_CELL = llListReplaceList(GEM_CELL, [-1], g, g);
            GEM_VAL = llListReplaceList(GEM_VAL, [-1], g, g);
            AT_CELL = llListReplaceList(AT_CELL, [-1], cell, cell);
        }
    }
    sendHide(hide);
    if (stopS != "") llMessageLinked(LINK_SET, 531, stopS, "");

    string setBody = "";
    integer ncr = llGetListLength(W_CREATED) / 2;
    for (k = 0; k < ncr; ++k)
    {
        integer cell2 = llList2Integer(W_CREATED, k * 2);
        integer val2 = llList2Integer(W_CREATED, k * 2 + 1);
        integer g2 = takeFree();
        if (g2 >= 0)
        {
            GEM_CELL = llListReplaceList(GEM_CELL, [cell2], g2, g2);
            GEM_VAL = llListReplaceList(GEM_VAL, [val2], g2, g2);
            AT_CELL = llListReplaceList(AT_CELL, [g2], cell2, cell2);
            if (setBody != "") setBody += "|";
            setBody += (string)g2 + "," + (string)cell2 + "," + (string)val2;
        }
    }
    sendSet(setBody);
    if (ncr > 0) llMessageLinked(LINK_SET, 500, "created", "");

    string moveBody = "";
    integer nf = llGetListLength(W_FALLS) / 4;
    list movingGem = [];
    list usedGem = [];
    for (k = 0; k < nf; ++k)
    {
        integer c = llList2Integer(W_FALLS, k * 4);
        integer from = llList2Integer(W_FALLS, k * 4 + 1);
        integer to = llList2Integer(W_FALLS, k * 4 + 2);
        integer val3 = llList2Integer(W_FALLS, k * 4 + 3);
        integer g3 = llList2Integer(AT_CELL, from * 8 + c);
        if (g3 < 0) g3 = findGemAtCell(from * 8 + c);
        if (g3 < 0) g3 = findGemInColumn(c, val3, usedGem);
        movingGem += [g3];
        if (g3 >= 0)
        {
            usedGem += [g3];
            float d = FALL_BASE + (float)(to - from) * FALL_ROW;
            if (d > FALL_MAX) d = FALL_MAX;
            if (moveBody != "") moveBody += "|";
            moveBody += (string)g3 + "," + (string)(from * 8 + c) + "," + (string)(to * 8 + c) + "," + (string)d;
            AT_CELL = llListReplaceList(AT_CELL, [-1], from * 8 + c, from * 8 + c);
        }
    }
    for (k = 0; k < nf; ++k)
    {
        integer g4 = llList2Integer(movingGem, k);
        if (g4 >= 0)
        {
            integer c2 = llList2Integer(W_FALLS, k * 4);
            integer to2 = llList2Integer(W_FALLS, k * 4 + 2);
            integer dest = to2 * 8 + c2;
            AT_CELL = llListReplaceList(AT_CELL, [g4], dest, dest);
            GEM_CELL = llListReplaceList(GEM_CELL, [dest], g4, g4);
        }
    }

    integer ns = llGetListLength(W_SPAWNS) / 4;
    if (nf + ns > 0) llMessageLinked(LINK_SET, 500, "land", "");
    setBody = "";
    for (k = 0; k < ns; ++k)
    {
        integer sc = llList2Integer(W_SPAWNS, k * 4);
        integer sf = llList2Integer(W_SPAWNS, k * 4 + 1);
        integer st = llList2Integer(W_SPAWNS, k * 4 + 2);
        integer sv = llList2Integer(W_SPAWNS, k * 4 + 3);
        integer sg = takeFree();
        if (sg >= 0)
        {
            integer sdest = st * 8 + sc;
            integer startCode = codeSpawn(sdest);
            GEM_CELL = llListReplaceList(GEM_CELL, [sdest], sg, sg);
            GEM_VAL = llListReplaceList(GEM_VAL, [sv], sg, sg);
            AT_CELL = llListReplaceList(AT_CELL, [sg], sdest, sdest);
            if (setBody != "") setBody += "|";
            setBody += (string)sg + "," + (string)startCode + "," + (string)sv;
            float sd = FALL_BASE + SPAWN_EXTRA + (float)(st - sf) * FALL_ROW;
            if (sd > FALL_MAX) sd = FALL_MAX;
            if (moveBody != "") moveBody += "|";
            moveBody += (string)sg + "," + (string)startCode + "," + (string)sdest + "," + (string)sd;
        }
    }
    sendSet(setBody);
    W_CLEARED = [];
    W_CREATED = [];
    W_FALLS = [];
    W_SPAWNS = [];
    STATE = ST_FALL;
    sendMove(1, moveBody);
    if (DONE_MASK == EXPECT_MASK) nextWave();
}

beginSwap(integer moveId, integer a, integer b, integer ok, string waves)
{
    ACTIVE_MOVE_ID = moveId;
    SWAP_A = a;
    SWAP_B = b;
    SWAP_OK = ok;
    WAVES_STR = waves;
    integer ga = llList2Integer(AT_CELL, a);
    integer gb = llList2Integer(AT_CELL, b);
    if (ga < 0 || gb < 0) { finish(); return; }
    string moves = (string)ga + "," + (string)a + "," + (string)b + "," + (string)SWAP_DUR
        + "|" + (string)gb + "," + (string)b + "," + (string)a + "," + (string)SWAP_DUR;
    llMessageLinked(LINK_SET, 500, "swap", "");
    if (ok)
    {
        AT_CELL = llListReplaceList(AT_CELL, [gb], a, a);
        AT_CELL = llListReplaceList(AT_CELL, [ga], b, b);
        GEM_CELL = llListReplaceList(GEM_CELL, [b], ga, ga);
        GEM_CELL = llListReplaceList(GEM_CELL, [a], gb, gb);
        STATE = ST_SWAP;
    }
    else
    {
        llMessageLinked(LINK_SET, 500, "invalid", "");
        BACK_MOVES = (string)ga + "," + (string)b + "," + (string)a + "," + (string)SWAP_DUR
            + "|" + (string)gb + "," + (string)a + "," + (string)b + "," + (string)SWAP_DUR;
        STATE = ST_SWAPBACK;
    }
    sendMove(0, moves);
}

default
{
    state_entry()
    {
        findGemLinks();
        llOwnerSay("GEMS_RENDER_CONTROLLER: pronto, memoria livre " + (string)llGetFreeMemory() + ".");
        llMessageLinked(LINK_SET, 250, "", "");
    }
    on_rez(integer p) { llResetScript(); }
    changed(integer c)
    {
        if (c & (CHANGED_LINK | CHANGED_OWNER | CHANGED_REGION_START)) llResetScript();
    }
    link_message(integer sender, integer num, string str, key id)
    {
        if (num == 502)
        {
            list tp = llParseString2List(str, ["|"], []);
            string tg = llList2String(tp, 0);
            if (tg == "" || llSubStringIndex(llToLower(tg), "digit") >= 0) tg = "CG_gems_atlas_1024x512";
            llMessageLinked(LINK_SET, 720, tg, "");
            return;
        }
        if (num == 100 || num == 111 || num == 112)
        {
            list grid = llCSV2List(str);
            if (llGetListLength(grid) == 64) resetFromGrid(grid);
            if (num == 111 || num == 112) finish();
            return;
        }
        if (num == 211)
        {
            integer sep = llSubStringIndex(str, "|");
            string head = str;
            string waves = "";
            if (sep >= 0)
            {
                head = llGetSubString(str, 0, sep - 1);
                waves = llGetSubString(str, sep + 1, -1);
            }
            list h = llCSV2List(head);
            if (llGetListLength(h) >= 4)
                beginSwap((integer)llList2String(h, 0), (integer)llList2String(h, 1), (integer)llList2String(h, 2), (integer)llList2String(h, 3), waves);
            else
                beginSwap(0, (integer)llList2String(h, 0), (integer)llList2String(h, 1), (integer)llList2String(h, 2), waves);
            return;
        }
        if (num == 240)
        {
            integer g = (integer)str;
            integer cell = -1;
            if (g >= 0 && g < 64) cell = llList2Integer(GEM_CELL, g);
            llMessageLinked(LINK_SET, 241, (string)cell, id);
            return;
        }
        if (num == 520 || num == 521)
        {
            list p = llCSV2List(str);
            integer c1 = (integer)llList2String(p, 0);
            integer c2 = (integer)llList2String(p, 1);
            float glow = 0.0;
            if (num == 520) glow = 0.2;
            integer g1 = -1;
            integer g2 = -1;
            if (c1 >= 0 && c1 < 64) g1 = llList2Integer(AT_CELL, c1);
            if (c2 >= 0 && c2 < 64) g2 = llList2Integer(AT_CELL, c2);
            if (g1 >= 0) llMessageLinked(LINK_SET, 724, (string)g1 + "," + (string)glow, "");
            if (g2 >= 0) llMessageLinked(LINK_SET, 724, (string)g2 + "," + (string)glow, "");
            return;
        }
        if (num == 731)
        {
            list p2 = llParseString2List(str, ["|"], []);
            integer bit = shardBit(llList2String(p2, 0));
            string st = llList2String(p2, 1);
            if (st == "READY") READY_MASK = READY_MASK | bit;
            if (st == "DONE")
            {
                if (llGetListLength(p2) >= 3)
                {
                    integer doneMove = (integer)llList2String(p2, 2);
                    if (doneMove != ACTIVE_MOVE_ID) return;
                }
                DONE_MASK = DONE_MASK | bit;
                if (DONE_MASK == EXPECT_MASK)
                {
                    afterDone();
                }
            }
        }
    }
    timer()
    {
        llSetTimerEvent(0.0);
        if (STATE == ST_POP) beginFall();
        else if (STATE == ST_SWAP || STATE == ST_SWAPBACK || STATE == ST_FALL)
        {
            DONE_MASK = EXPECT_MASK;
            afterDone();
        }
    }
}
