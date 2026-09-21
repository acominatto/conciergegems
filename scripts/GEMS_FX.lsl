// GEMS_FX.lsl - explosao e particulas do Concierge Gems 2.0. PRIM RAIZ.
//
// MUDOU NA 2.0: este script nao move mais gema nenhuma e nao usa llSleep. Quem manda e o GEMS_ANIMATION,
// que conhece as posicoes; aqui so trocamos a textura da gema pelo atlas de explosao, ligamos a animacao
// de quadros (que roda no VIEWER, nao no script) e soltamos as particulas na cor da gema.
//
// entra 530 "link,valor|link,valor|..."   explode estas gemas agora
// entra 501 "0|1"                          liga/desliga o som (repassado ao GEMS_AUDIO)
//
// O GEMS_ANIMATION apaga as gemas (alpha 0) quando a explosao termina, entao aqui nao ha limpeza a fazer.

string TEX_FX = "CG_fx_atlas_1024x1024";
float  POP = 0.18;               // tem de bater com POP_DUR do GEMS_ANIMATION
integer MAX_BURSTS = 4;          // limite de emissores por onda (particula demais derruba o FPS)

// cores das 7 gemas, iguais ao COLOR_DEFS do main.js
list GEM_RGB = [
    <0.29, 0.36, 1.00>,  // blue    #4A5CFF
    <0.24, 0.82, 0.24>,  // green   #3ED13E
    <0.89, 0.23, 0.23>,  // red     #E23A3A
    <1.00, 0.77, 0.23>,  // gold    #FFC43B
    <0.25, 0.88, 0.91>,  // turq    #3FE0E8
    <0.83, 0.24, 0.88>,  // magenta #D43CE0
    <1.00, 0.24, 0.65>   // pink    #FF3EA5
];

vector gemColor(integer v)
{
    if (v < 0) return <1.0, 1.0, 1.0>;
    if (v / 8 == 3) return <1.0, 1.0, 1.0>;      // rainbow: branco
    return llList2Vector(GEM_RGB, v % 8);
}

// rajada curta de particulas na cor da gema; o viewer desenha, o script nao paga por quadro
burst(integer link, vector color)
{
    llLinkParticleSystem(link, [
        PSYS_PART_FLAGS, PSYS_PART_EMISSIVE_MASK | PSYS_PART_INTERP_COLOR_MASK
                       | PSYS_PART_INTERP_SCALE_MASK | PSYS_PART_FOLLOW_VELOCITY_MASK,
        PSYS_SRC_PATTERN, PSYS_SRC_PATTERN_EXPLODE,
        PSYS_PART_START_COLOR, color,
        PSYS_PART_END_COLOR, color,
        PSYS_PART_START_ALPHA, 1.0,
        PSYS_PART_END_ALPHA, 0.0,
        PSYS_PART_START_SCALE, <0.035, 0.035, 0.0>,
        PSYS_PART_END_SCALE, <0.005, 0.005, 0.0>,
        PSYS_PART_MAX_AGE, 0.45,
        PSYS_SRC_BURST_PART_COUNT, 7,          // os mesmos 7 pedacos do efeito original
        PSYS_SRC_BURST_RATE, 0.0,
        PSYS_SRC_BURST_RADIUS, 0.02,
        PSYS_SRC_BURST_SPEED_MIN, 0.15,
        PSYS_SRC_BURST_SPEED_MAX, 0.45,
        PSYS_SRC_ACCEL, <0.0, 0.0, -0.6>,      // gravidade, como no Canvas
        PSYS_SRC_MAX_AGE, 0.2,                 // emite uma vez e para sozinho
        PSYS_PART_START_GLOW, 0.3
    ]);
}

default
{
    state_entry()
    {
        llOwnerSay("Concierge Gems FX 2.0 pronto (explosao e particulas).");
    }

    on_rez(integer p) { llResetScript(); }

    link_message(integer sender, integer num, string str, key id)
    {
        if (num == 502)
        {
            string tf = llList2String(llParseString2List(str, ["|"], []), 1);
            if (tf != "") TEX_FX = tf;
            return;
        }
        if (num == 530)
        {
            list items = llParseString2List(str, ["|"], []);
            integer n = llGetListLength(items);
            integer k;
            list rec;
            integer inBatch = 0;
            for (k = 0; k < n; ++k)
            {
                list p = llCSV2List(llList2String(items, k));
                integer link = (integer)llList2String(p, 0);
                integer val = (integer)llList2String(p, 1);
                vector col = gemColor(val);
                // a gema vira o primeiro quadro do atlas de explosao, na cor dela
                rec += [PRIM_LINK_TARGET, link,
                        PRIM_TEXTURE, ALL_SIDES, TEX_FX, <0.25, 0.25, 0.0>, <-0.375, 0.375, 0.0>, 0.0,
                        PRIM_COLOR, ALL_SIDES, col, 1.0,
                        PRIM_FULLBRIGHT, ALL_SIDES, TRUE,
                        PRIM_GLOW, ALL_SIDES, 0.3];
                ++inBatch;
                if (inBatch >= 16)                      // fecha o lote sempre entre registros
                {
                    llSetLinkPrimitiveParamsFast(LINK_THIS, rec);
                    rec = [];
                    inBatch = 0;
                }
            }
            if (inBatch > 0) llSetLinkPrimitiveParamsFast(LINK_THIS, rec);
            // 16 quadros (4x4) em POP segundos, uma passada so; quem anima e o viewer
            for (k = 0; k < n; ++k)
            {
                list p = llCSV2List(llList2String(items, k));
                integer link = (integer)llList2String(p, 0);
                llSetLinkTextureAnim(link, ANIM_ON, ALL_SIDES, 4, 4, 0.0, 16.0, 16.0 / POP);
            }
            // particulas so em algumas gemas da onda: o efeito e o mesmo e o custo cai muito
            integer nb = n;
            if (nb > MAX_BURSTS) nb = MAX_BURSTS;
            for (k = 0; k < nb; ++k)
            {
                list p = llCSV2List(llList2String(items, k));
                burst((integer)llList2String(p, 0), gemColor((integer)llList2String(p, 1)));
            }
            return;
        }
        if (num == 531)                      // desliga a animacao de quadros de gemas reaproveitadas: "link|link|..."
        {
            list ls = llParseString2List(str, ["|"], []);
            integer m = llGetListLength(ls);
            integer q;
            for (q = 0; q < m; ++q)
            {
                integer link = (integer)llList2String(ls, q);
                llSetLinkTextureAnim(link, 0, ALL_SIDES, 0, 0, 0.0, 0.0, 1.0);
                llLinkParticleSystem(link, []);
            }
        }
    }
}
