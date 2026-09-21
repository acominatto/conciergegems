// GEMS_RENDER_D.lsl - renderiza somente as gemas 48..63.
integer SHARD_START = 48;
integer SHARD_COUNT = 16;
string SHARD_NAME = "D";

float TICK = 0.025;
float TICK_MID = 0.035;
float TEX_ROT = 0.0;
string TEX_GEMS = "CG_gems_atlas_1024x512";
integer GEM_FACE = 1;

list GEM_LINK;
vector CELL0;
vector COL_STEP;
vector ROW_STEP;
integer READY = FALSE;

list A_GEM;
list A_FROM;
list A_TO;
list A_DUR;
integer A_EASE;
integer A_MOVE_ID = 0;
float A_T0;

integer gemLink(integer g) { return llList2Integer(GEM_LINK, g - SHARD_START); }
vector cellPos(integer c) { return CELL0 + COL_STEP * (float)(c % 8) + ROW_STEP * (float)(c / 8); }
vector posOf(integer c) { return cellPos(c); }
vector posVirtual(integer r, integer c)
{
    if (r >= 0) return posOf(r * 8 + c);
    return posOf(c) + ROW_STEP * (float)r;
}
vector posCode(integer code)
{
    if (code >= 0) return posOf(code);
    if (code <= -1000)
    {
        integer cell = -1000 - code;
        integer c = cell % 8;
        return posOf(c) - ROW_STEP * 0.85;
    }
    integer x = -1 - code;
    return posVirtual(-(x / 8), x % 8);
}

float ease(float t)
{
    if (A_EASE == 0) return t * t * (3.0 - 2.0 * t);
    if (t < 0.85)
    {
        float k = t / 0.85;
        return k * k;
    }
    float k2 = (t - 0.85) / 0.15;
    return 1.0 - llSin(k2 * PI) * 0.04;
}

list gemFace(integer v)
{
    if (v < 0) return [PRIM_COLOR, ALL_SIDES, <1.0, 1.0, 1.0>, 0.0, PRIM_GLOW, ALL_SIDES, 0.0];
    integer sp = v / 8;
    integer idx = v % 8;
    if (sp == 3) idx = 7;
    integer col = idx % 4;
    integer row = idx / 4;
    vector c = <1.0, 1.0, 1.0>;
    if (sp == 1) c = <1.0, 0.72, 0.30>;
    if (sp == 2) c = <1.0, 1.0, 0.75>;
    float glow = 0.0;
    if (sp > 0) glow = 0.08;
    return [PRIM_COLOR, ALL_SIDES, <1.0, 1.0, 1.0>, 0.0,
            PRIM_TEXTURE, GEM_FACE, TEX_GEMS, <0.25, 0.5, 0.0>,
            <-0.375 + (float)col * 0.25, 0.25 - (float)row * 0.5, 0.0>, TEX_ROT,
            PRIM_COLOR, GEM_FACE, c, 1.0,
            PRIM_FULLBRIGHT, GEM_FACE, TRUE,
            PRIM_GLOW, GEM_FACE, glow];
}

clearAnim()
{
    A_GEM = [];
    A_FROM = [];
    A_TO = [];
    A_DUR = [];
}

findPrims()
{
    list cells = [];
    GEM_LINK = [];
    integer i;
    for (i = 0; i < 64; ++i) cells += [0];
    for (i = 0; i < SHARD_COUNT; ++i) GEM_LINK += [0];

    integer foundCells = 0;
    integer foundGems = 0;
    integer n = llGetNumberOfPrims();
    integer k;
    for (k = 1; k <= n; ++k)
    {
        string nm = llGetLinkName(k);
        if (llGetSubString(nm, 0, 7) == "CG_CELL_")
        {
            list p = llParseString2List(llGetSubString(nm, 8, -1), ["_"], []);
            integer r = (integer)llList2String(p, 0);
            integer c = (integer)llList2String(p, 1);
            if (r >= 0 && r < 8 && c >= 0 && c < 8)
            {
                integer idx = r * 8 + c;
                if (llList2Integer(cells, idx) == 0)
                {
                    cells = llListReplaceList(cells, [k], idx, idx);
                    ++foundCells;
                }
            }
        }
        else if (llGetSubString(nm, 0, 6) == "CG_GEM_")
        {
            integer g = (integer)llGetSubString(nm, 7, -1);
            if (g >= SHARD_START && g < SHARD_START + SHARD_COUNT)
            {
                GEM_LINK = llListReplaceList(GEM_LINK, [k], g - SHARD_START, g - SHARD_START);
                ++foundGems;
            }
        }
    }
    READY = FALSE;
    integer l0 = llList2Integer(cells, 0);
    integer l1 = llList2Integer(cells, 1);
    integer l8 = llList2Integer(cells, 8);
    if (foundCells == 64 && foundGems == SHARD_COUNT && l0 > 0 && l1 > 0 && l8 > 0)
    {
        CELL0 = llList2Vector(llGetLinkPrimitiveParams(l0, [PRIM_POS_LOCAL]), 0);
        COL_STEP = llList2Vector(llGetLinkPrimitiveParams(l1, [PRIM_POS_LOCAL]), 0) - CELL0;
        ROW_STEP = llList2Vector(llGetLinkPrimitiveParams(l8, [PRIM_POS_LOCAL]), 0) - CELL0;
        READY = TRUE;
    }
    llOwnerSay("GEMS_RENDER_" + SHARD_NAME + ": " + (string)foundGems + "/16 gemas, memoria livre " + (string)llGetFreeMemory() + ".");
    if (READY) llMessageLinked(LINK_SET, 731, SHARD_NAME + "|READY", "");
    else llMessageLinked(LINK_SET, 731, SHARD_NAME + "|ERROR", "");
}

applySet(string body)
{
    if (!READY) return;
    list rows = llParseString2List(body, ["|"], []);
    list q = [];
    integer n = llGetListLength(rows);
    integer i;
    for (i = 0; i < n; ++i)
    {
        list p = llCSV2List(llList2String(rows, i));
        integer g = (integer)llList2String(p, 0);
        if (g >= SHARD_START && g < SHARD_START + SHARD_COUNT)
        {
            integer cell = (integer)llList2String(p, 1);
            integer val = (integer)llList2String(p, 2);
            q += [PRIM_LINK_TARGET, gemLink(g), PRIM_POS_LOCAL, posCode(cell)] + gemFace(val);
            if (llGetListLength(q) >= 64) { llSetLinkPrimitiveParamsFast(LINK_THIS, q); q = []; }
        }
    }
    if (llGetListLength(q) > 0) llSetLinkPrimitiveParamsFast(LINK_THIS, q);
}

applyHide(string body)
{
    list rows = llCSV2List(body);
    list q = [];
    integer i;
    integer n = llGetListLength(rows);
    for (i = 0; i < n; ++i)
    {
        integer g = (integer)llList2String(rows, i);
        if (g >= SHARD_START && g < SHARD_START + SHARD_COUNT)
            q += [PRIM_LINK_TARGET, gemLink(g), PRIM_COLOR, ALL_SIDES, <1.0, 1.0, 1.0>, 0.0, PRIM_GLOW, ALL_SIDES, 0.0];
    }
    if (llGetListLength(q) > 0) llSetLinkPrimitiveParamsFast(LINK_THIS, q);
}

startMove(integer moveId, integer easeKind, string body)
{
    clearAnim();
    A_MOVE_ID = moveId;
    A_EASE = easeKind;
    list rows = llParseString2List(body, ["|"], []);
    integer n = llGetListLength(rows);
    integer i;
    for (i = 0; i < n; ++i)
    {
        list p = llCSV2List(llList2String(rows, i));
        integer g = (integer)llList2String(p, 0);
        if (g >= SHARD_START && g < SHARD_START + SHARD_COUNT)
        {
            A_GEM += [g];
            A_FROM += [(integer)llList2String(p, 1)];
            A_TO += [(integer)llList2String(p, 2)];
            A_DUR += [(float)llList2String(p, 3)];
        }
    }
    integer m = llGetListLength(A_GEM);
    if (m == 0) { llMessageLinked(LINK_SET, 731, SHARD_NAME + "|DONE|" + (string)A_MOVE_ID, ""); return; }
    A_T0 = llGetTime();
    float tk = TICK;
    if (m > 8) tk = TICK_MID;
    llSetTimerEvent(tk);
}

default
{
    state_entry()
    {
        llSetTimerEvent(0.0);
        clearAnim();
        findPrims();
    }
    changed(integer c)
    {
        if (c & (CHANGED_LINK | CHANGED_OWNER | CHANGED_REGION_START)) llResetScript();
    }
    link_message(integer sender, integer num, string str, key id)
    {
        if (num == 720)
        {
            list p = llParseString2List(str, ["|"], []);
            string tg = llList2String(p, 0);
            if (tg != "" && llSubStringIndex(llToLower(tg), "digit") < 0) TEX_GEMS = tg;
            return;
        }
        if (num == 721) { applySet(str); return; }
        if (num == 722)
        {
            integer sep = llSubStringIndex(str, "|");
            if (sep < 0) return;
            string first = llGetSubString(str, 0, sep - 1);
            string rest = llGetSubString(str, sep + 1, -1);
            integer sep2 = llSubStringIndex(rest, "|");
            if (sep2 >= 0)
                startMove((integer)first, (integer)llGetSubString(rest, 0, sep2 - 1), llGetSubString(rest, sep2 + 1, -1));
            else
                startMove(0, (integer)first, rest);
            return;
        }
        if (num == 723) { applyHide(str); return; }
        if (num == 724)
        {
            list p2 = llCSV2List(str);
            integer g2 = (integer)llList2String(p2, 0);
            if (g2 >= SHARD_START && g2 < SHARD_START + SHARD_COUNT)
                llSetLinkPrimitiveParamsFast(LINK_THIS, [PRIM_LINK_TARGET, gemLink(g2), PRIM_GLOW, ALL_SIDES, (float)llList2String(p2, 1)]);
        }
    }
    timer()
    {
        float now = llGetTime() - A_T0;
        integer done = TRUE;
        list q = [];
        integer i;
        integer n = llGetListLength(A_GEM);
        for (i = 0; i < n; ++i)
        {
            float dur = llList2Float(A_DUR, i);
            float t = 1.0;
            if (dur > 0.0) t = now / dur;
            if (t > 1.0) t = 1.0;
            else done = FALSE;
            vector from = posCode(llList2Integer(A_FROM, i));
            vector to = posCode(llList2Integer(A_TO, i));
            q += [PRIM_LINK_TARGET, gemLink(llList2Integer(A_GEM, i)), PRIM_POS_LOCAL, from + (to - from) * ease(t)];
            if (llGetListLength(q) >= 64) { llSetLinkPrimitiveParamsFast(LINK_THIS, q); q = []; }
        }
        if (llGetListLength(q) > 0) llSetLinkPrimitiveParamsFast(LINK_THIS, q);
        if (done)
        {
            llSetTimerEvent(0.0);
            clearAnim();
            llMessageLinked(LINK_SET, 731, SHARD_NAME + "|DONE|" + (string)A_MOVE_ID, "");
        }
    }
}
