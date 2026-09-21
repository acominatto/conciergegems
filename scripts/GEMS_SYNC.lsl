// GEMS_SYNC.lsl - fila local + envio dos resultados ao Concierge OS. Vai no PRIM RAIZ. OPCIONAL.
//
// O jogo NAO depende deste script: sem ele (ou com o servidor fora do ar) a partida roda igual e a
// pontuacao local continua valendo. Aqui so cuidamos de guardar os resultados e manda-los quando der.
//
// Fila: Linkset Data (128 KB por linkset). Guardamos ate FILA_MAX partidas em chaves "q<n>".
//   Cada partida: game_id|avatar_uuid|nome|score|level|combo|dificuldade|unixtime
//   game_id = <chave do objeto>-<contador>-<unixtime>: o servidor descarta repetido, entao reenviar
//   nunca duplica pontos.
// Cheia: descarta a MAIS ANTIGA e conta as perdas (o dono e avisado). O jogo nunca trava por isso.
//
// Recebe do GEMS_BOARD: msg 600 = "avatar|nome|score|level|combo|dificuldade"

integer FILA_MAX = 50;
float   RETRY_MIN = 30.0;        // recuo: 30 s, 60, 120... ate RETRY_MAX
float   RETRY_MAX = 300.0;
float   IDLE = 120.0;            // com a fila vazia, olha de dois em dois minutos

string API_URL = "";             // vazio = sincronizacao desligada
string LAND_ID = "";
string MACHINE_ID = "";
string MACHINE_SECRET = "";

float   wait = 0.0;
key     req = NULL_KEY;
string  sending = "";            // chave da partida em voo
integer lost = 0;

// ---------- fila (Linkset Data) ----------
integer qHead() { return (integer)llLinksetDataRead("q_head"); }
integer qTail() { return (integer)llLinksetDataRead("q_tail"); }
integer qLen() { return qTail() - qHead(); }

qPush(string rec)
{
    integer tail = qTail();
    integer head = qHead();
    while (tail - head >= FILA_MAX)          // cheia: sai a mais antiga
    {
        llLinksetDataDelete("q" + (string)head);
        ++head;
        ++lost;
        llLinksetDataWrite("q_head", (string)head);
        llOwnerSay("Concierge Gems: fila cheia, descartei o resultado mais antigo (" + (string)lost + " no total).");
    }
    if (llLinksetDataWrite("q" + (string)tail, rec) != LINKSETDATA_OK)
    {
        llOwnerSay("Concierge Gems: sem espaco no armazenamento do objeto; resultado nao guardado.");
        return;
    }
    llLinksetDataWrite("q_tail", (string)(tail + 1));
}

string qPeek()
{
    if (qLen() <= 0) return "";
    return llLinksetDataRead("q" + (string)qHead());
}

qPop()
{
    integer head = qHead();
    llLinksetDataDelete("q" + (string)head);
    llLinksetDataWrite("q_head", (string)(head + 1));
}

integer nextId()
{
    integer n = (integer)llLinksetDataRead("gid") + 1;
    llLinksetDataWrite("gid", (string)n);
    return n;
}

// ---------- envio ----------
trySend()
{
    if (API_URL == "") return;
    if (req != NULL_KEY) return;             // ja tem uma em voo
    string rec = qPeek();
    if (rec == "") { llSetTimerEvent(IDLE); return; }
    list p = llParseStringKeepNulls(rec, ["|"], []);
    sending = rec;
    string body = llList2Json(JSON_OBJECT, [
        "land_id", LAND_ID,
        "machine_id", MACHINE_ID,
        "secret", MACHINE_SECRET,
        "game_id", llList2String(p, 0),
        "avatar_uuid", llList2String(p, 1),
        "avatar_name", llList2String(p, 2),
        "score", llList2String(p, 3),
        "level", llList2String(p, 4),
        "max_combo", llList2String(p, 5),
        "difficulty", llList2String(p, 6),
        "played_at", llList2String(p, 7),
        "source", "sl-native"
    ]);
    req = llHTTPRequest(API_URL + "/games/concierge-gems/native-result",
        [HTTP_METHOD, "POST", HTTP_MIMETYPE, "application/json", HTTP_VERIFY_CERT, TRUE], body);
}

backoff()
{
    if (wait <= 0.0) wait = RETRY_MIN;
    else wait = wait * 2.0;
    if (wait > RETRY_MAX) wait = RETRY_MAX;
    llSetTimerEvent(wait);
}

// ---------- config (mesmo notecard CG_CONFIG do BOARD) ----------
key CFG_Q; integer CFG_LINE;

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
    if (k == "API_URL")
    {
        while (llGetSubString(v, -1, -1) == "/") v = llGetSubString(v, 0, -2);      // sem barra no fim
        if (v != "")
        {
            if (llGetSubString(v, 0, 7) != "https://" && llGetSubString(v, 0, 6) != "http://")
            {
                llOwnerSay("ERRO no CG_CONFIG: API_URL '" + v + "' nao comeca com https:// - sincronizacao desligada.");
                v = "";
            }
        }
        API_URL = v;
    }
    else if (k == "LAND_ID") LAND_ID = v;
    else if (k == "MACHINE_ID") MACHINE_ID = v;
    else if (k == "MACHINE_SECRET") MACHINE_SECRET = v;
}

default
{
    state_entry()
    {
        if (llGetInventoryType("CG_CONFIG") == INVENTORY_NOTECARD)
        {
            CFG_LINE = 0;
            CFG_Q = llGetNotecardLine("CG_CONFIG", 0);
        }
        else llOwnerSay("Concierge Gems: sem CG_CONFIG - sincronizacao desligada (o jogo funciona normalmente).");
        llSetTimerEvent(IDLE);
    }

    on_rez(integer p) { llResetScript(); }

    changed(integer c) { if (c & CHANGED_INVENTORY) llResetScript(); }

    dataserver(key q, string data)
    {
        if (q != CFG_Q) return;
        if (data == EOF)
        {
            if (API_URL == "") llOwnerSay("Concierge Gems: API_URL vazio - resultados ficam so no objeto.");
            else llOwnerSay("Concierge Gems: sincronizacao ligada (" + (string)qLen() + " resultado(s) na fila).");
            trySend();
            return;
        }
        applyConfig(data);
        ++CFG_LINE;
        CFG_Q = llGetNotecardLine("CG_CONFIG", CFG_LINE);
    }

    link_message(integer sender, integer num, string str, key id)
    {
        if (num != 600) return;
        list p = llParseStringKeepNulls(str, ["|"], []);
        string gid = (string)llGetKey() + "-" + (string)nextId() + "-" + (string)llGetUnixTime();
        qPush(gid + "|" + llDumpList2String(p, "|") + "|" + (string)llGetUnixTime());
        wait = 0.0;
        trySend();
    }

    http_response(key id, integer status, list meta, string body)
    {
        if (id != req) return;
        req = NULL_KEY;
        if (status == 200 || status == 201 || status == 409)
        {
            // 409 = o servidor ja tinha este game_id: tratado como entregue (nunca duplica pontos)
            qPop();
            wait = 0.0;
            if (qLen() > 0) { llSetTimerEvent(2.0); return; }
            llSetTimerEvent(IDLE);
            return;
        }
        if (status == 401 || status == 403)
        {
            llOwnerSay("Concierge Gems: credenciais recusadas pelo servidor. Confira MACHINE_SECRET no CG_CONFIG.");
            llSetTimerEvent(RETRY_MAX);
            return;
        }
        backoff();                            // rede fora, 5xx, etc: tenta de novo mais tarde
    }

    timer()
    {
        trySend();
    }
}
