// GEMS_CELL.lsl - vai DENTRO dos objetos CG_CELL e CG_GEM (o GEMS_BUILDER os rezza).
// O parametro de rez traz tudo, entao o tamanho do modelo NAO importa:
//   bits de baixo (param % 2048): 0..63 -> CG_CELL_<linha>_<coluna> (celula fixa: alvo de clique)
//                                 1000..1063 -> CG_GEM_<n> (gema movel, so visual)
//   param / 2048 = lado_mm * 3 + eixo_fino (0=X, 1=Y, 2=Z): o objeto se redimensiona para um quadrado dessa medida,
//   com espessura 0,01 m (minimo do Second Life) no eixo fino.
// Depois de configurado, este script se apaga: nao pesa no linkset.

configure(string name, string desc, integer high)
{
    llSetObjectName(name);
    llSetObjectDesc(desc);
    llSetStatus(STATUS_PHANTOM, TRUE);
    list p = [
        PRIM_PHYSICS_SHAPE_TYPE, PRIM_PHYSICS_SHAPE_NONE,
        PRIM_COLOR, ALL_SIDES, <1.0, 1.0, 1.0>, 0.0,
        PRIM_FULLBRIGHT, ALL_SIDES, TRUE
    ];
    if (high > 0)
    {
        float side = (float)(high / 3) / 1000.0;
        integer axis = high % 3;
        vector s = <side, side, 0.01>;
        if (axis == 0) s = <0.01, side, side>;
        if (axis == 1) s = <side, 0.01, side>;
        p = [PRIM_SIZE, s] + p;
    }
    llSetPrimitiveParams(p);
    llRemoveInventory(llGetScriptName());
}

default
{
    on_rez(integer param)
    {
        integer idx = param % 2048;
        integer high = param / 2048;
        if (idx >= 1000 && idx <= 1063)
        {
            integer g = idx - 1000;
            configure("CG_GEM_" + (string)g, "gema movel " + (string)g + " do Concierge Gems 2.0", high);
            return;
        }
        if (idx >= 0 && idx <= 63)
        {
            configure("CG_CELL_" + (string)(idx / 8) + "_" + (string)(idx % 8),
                      "celula " + (string)(idx / 8) + "," + (string)(idx % 8) + " do Concierge Gems", high);
        }
    }
}
