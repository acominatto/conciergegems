// GEMS_AUDIO.lsl - som nativo do Concierge Gems (sem navegador). Vai no PRIM RAIZ.
// Toca os WAV que estao no INVENTARIO do objeto, pelo nome (ou pelos UUIDs do notecard CG_CONFIG).
// Um unico script cuida de tudo: o BOARD/FX so manda "sfx <nome>" (msg 500).

integer ENABLED = TRUE;
float   VOL = 0.55;
list    WARMUP_SOUNDS = [];
integer WARMUP_I = 0;

// nomes dos sons no inventario (arquivos em /audio do pacote)
// match0..match7 = estouro com o tom subindo a cada onda da cascata, como no audio.js
string pick(string name)
{
    if (llGetInventoryType(name) == INVENTORY_SOUND) return name;
    // cascata alta cai no ultimo som disponivel
    if (llGetSubString(name, 0, 4) == "match")
    {
        integer n = (integer)llGetSubString(name, 5, -1);
        while (n > 0)
        {
            --n;
            if (llGetInventoryType("match" + (string)n) == INVENTORY_SOUND) return "match" + (string)n;
        }
    }
    return "";
}

default
{
    state_entry()
    {
        // pre-carrega nos viewers por perto: o primeiro estouro nao sai mudo
        integer n = llGetInventoryNumber(INVENTORY_SOUND);
        integer i;
        WARMUP_SOUNDS = [];
        WARMUP_I = 0;
        for (i = 0; i < n; ++i)
        {
            string snd = llGetInventoryName(INVENTORY_SOUND, i);
            llPreloadSound(snd);
            WARMUP_SOUNDS += [snd];
        }
        llOwnerSay("Concierge Gems audio: " + (string)n + " sons no inventario.");
        // diz QUAIS dos 21 sons esperados faltam (nome exato, sem .wav)
        list want = ["swap", "select", "invalid", "land", "created", "levelup", "shuffle", "gameover", "start", "tick",
            "blast_bomb", "blast_star", "blast_rainbow", "match0", "match1", "match2", "match3", "match4", "match5", "match6", "match7"];
        string missing = "";
        for (i = 0; i < 21; ++i)
            if (llGetInventoryType(llList2String(want, i)) != INVENTORY_SOUND) missing += " " + llList2String(want, i);
        if (missing != "") llOwnerSay("Concierge Gems audio: FALTAM ou estao com nome errado:" + missing);
        if (n > 0) llSetTimerEvent(0.12);
    }

    on_rez(integer p) { llResetScript(); }

    changed(integer c) { if (c & CHANGED_INVENTORY) llResetScript(); }

    timer()
    {
        integer n = llGetListLength(WARMUP_SOUNDS);
        if (WARMUP_I >= n)
        {
            llSetTimerEvent(0.0);
            WARMUP_SOUNDS = [];
            return;
        }
        llTriggerSound(llList2String(WARMUP_SOUNDS, WARMUP_I), 0.01);
        ++WARMUP_I;
    }

    link_message(integer sender, integer num, string str, key id)
    {
        if (num == 500)
        {
            if (!ENABLED) return;
            string s = pick(str);
            if (s == "") return;
            float v = VOL;
            if (str == "tick") v = VOL * 0.5;
            if (llGetSubString(str, 0, 4) == "blast") v = VOL * 1.0;
            llTriggerSound(s, v);          // nao bloqueia: varios sons podem se sobrepor
        }
        else if (num == 501)               // liga/desliga
        {
            ENABLED = (integer)str;
            llOwnerSay("Som: " + llList2String(["desligado", "ligado"], ENABLED));
        }
    }
}
