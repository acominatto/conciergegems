// GEMS_BUILDER.lsl - monta as 64 CELULAS e as 64 GEMAS MOVEIS do Concierge Gems 2.0, ja nomeadas e orientadas.
// Voce NAO cria 64+64 prims na mao e NAO digita numero de link.
//
// (Ajuste FRONT_AXIS abaixo conforme a face do prim onde o script esta; celulas e gemas devem ser FINAS nesse mesmo eixo.)
// ATENCAO A ORIENTACAO (era o erro das celulas "de lado"): a face frontal do painel e +X LOCAL. Por isso o cubo
// modelo tem de ser FINO NO X, nao no Z. Tamanhos sugeridos para um painel de 0,75 m:
//     CG_CELL  <0,010 ; 0,092 ; 0,092>      (X fino; Y e Z sao a largura e a altura da celula)
//     CG_GEM   <0,006 ; 0,088 ; 0,088>
// Celulas e gemas nascem com a MESMA rotacao da base, entao herdam a frente +X.
//
// PREPARO (uma vez)
//   1. Crie um cubo com o tamanho de CG_CELL acima e chame-o de "CG_CELL". Ponha nele o script GEMS_CELL.
//   2. Crie outro com o tamanho de CG_GEM, chame de "CG_GEM" e ponha o mesmo GEMS_CELL. Pegue os dois (Take).
//   3. Na BASE do tabuleiro (a que ja existe) coloque os dois objetos e este script.
//
// USO: toque na base (so o dono) e escolha no menu:
//   Celulas -> 64 celulas   (pule se o painel ja tem as celulas CG_CELL_r_c)
//   Gemas   -> 64 gemas moveis CG_GEM_0..63, um pouco a frente das celulas
//   Ambos   -> os dois
// Depois: selecione tudo (celulas + gemas + a BASE POR ULTIMO) e linke com Ctrl+L. Apague este script e os dois
// objetos modelo de dentro da base. Linha 0 no TOPO, coluna 0 na esquerda de quem olha o painel.

string CELL_OBJ = "CG_CELL";
string GEM_OBJ  = "CG_GEM";
float  OUT_CELL = 0.012;         // celula: distancia da face da base (m)
float  OUT_GEM  = 0.024;         // gema: mais a frente que a celula
float  BOARD_UP_CELLS = -0.35;   // ajuste vertical em celulas: positivo sobe, negativo desce
float  BOARD_SCALE = 0.86;       // usa so a area visivel da tela do gabinete, sem invadir letreiro/botoes
// Eixos LOCAIS do prim onde este script esta (aba Objeto do editor, modo Local).
//   FRONT_AXIS = para onde a face frontal aponta (o eixo FINO do prim).
//   UP_AXIS    = para onde e o "para cima" do desenho (linha 0 fica deste lado).
// TELA DO GABINETE (0,83 x 0,092 x 1,006, rotacao 0; fina em Y): frente <0,-1,0>, cima <0,0,1>  <- valor abaixo.
// Se as pecas nascerem ATRAS do vidro, troque a frente para <0,1,0>. Se o tabuleiro sair de lado ou de cabeca para
// baixo, ajuste UP_AXIS. (Painel avulso 0,75 x 0,75 x 0,05, fino em Z: frente <0,0,1>, cima <0,1,0>.)
vector FRONT_AXIS = <0.0, -1.0, 0.0>;
vector UP_AXIS = <0.0, 0.0, 1.0>;
// TELA INCLINADA (nao curva): o vidro e um plano reto que se inclina. Os 0,092 m de espessura do prim sao quase todos
// inclinacao: 0,092 m de profundidade em 1,006 m de altura = atan(0,092 / 1,006) = 5,2 graus.
// TILT_DEG = quantos graus o TOPO da tela se inclina em relacao a vertical:
//   NEGATIVO = o topo fica mais LONGE de quem joga (tela "deitada para tras", comum em arcade). Padrao: -5.2 (medido no modelo do Blender: plano reto de 4 vertices, sem espessura)
//   POSITIVO = o topo fica mais PERTO de quem joga.
// Celulas e gemas nascem inclinadas o mesmo tanto e paralelas ao vidro. Se saírem cruzando o vidro ou afastadas
// so em cima/embaixo, inverta o sinal. SCREEN_THICK = espessura real do vidro (sem a inclinacao).
float TILT_DEG = -5.2;
float SCREEN_THICK = 0.0;
integer CH = 0;
integer LISTEN_H = 0;

float dimAlong(vector a, vector size)
{
    return llFabs(a.x) * size.x + llFabs(a.y) * size.y + llFabs(a.z) * size.z;
}

integer rezAll(string obj, float out, integer offset, float fill)
{
    if (llGetInventoryType(obj) != INVENTORY_OBJECT)
    {
        llOwnerSay("Falta o objeto '" + obj + "' no inventario deste prim. Veja o cabecalho do script.");
        return 0;
    }
    vector size = llGetScale();
    vector up = UP_AXIS;
    vector wid = (-FRONT_AXIS) % up;             // direcao da coluna 0 -> 7 para quem olha o painel
    float w = dimAlong(wid, size);               // largura do painel
    float h = dimAlong(up, size);                // altura do painel
    float cw = (w * BOARD_SCALE) / 8.0;
    float ch = (h * BOARD_SCALE) / 8.0;
    if (cw > ch) cw = ch;            // celula SEMPRE quadrada: numa tela mais alta que larga, o tabuleiro fica centrado
    if (ch > cw) ch = cw;
    rotation rot = llGetRot();
    vector pos = llGetPos();
    float ang = TILT_DEG * DEG_TO_RAD;
    // +ang gira a tela em torno da largura: o "cima" se inclina para a frente (tup) e a normal do vidro vira nrm
    vector tup = up * llCos(ang) + FRONT_AXIS * llSin(ang);
    vector nrm = FRONT_AXIS * llCos(ang) - up * llSin(ang);
    rotation tiltRot = llAxisAngle2Rot(wid, ang);
    // o TAMANHO tambem viaja no parametro de rez: o GEMS_CELL redimensiona o objeto sozinho, entao nao importa o tamanho
    // do modelo. Lado (mm) e eixo fino (0=X,1=Y,2=Z) ficam acima de 2048, o indice fica nos 11 bits de baixo.
    integer axis = 1;
    if (llFabs(FRONT_AXIS.x) > 0.5) axis = 0;
    if (llFabs(FRONT_AXIS.z) > 0.5) axis = 2;
    integer sideMM = llRound(cw * fill * 1000.0);
    integer packed = (sideMM * 3 + axis) * 2048;
    integer r; integer c;
    integer n = 0;
    for (r = 0; r < 8; ++r)
    {
        for (c = 0; c < 8; ++c)
        {
            float lx = -cw * 4.0 + cw * ((float)c + 0.5);
            float lz =  ch * 4.0 - ch * ((float)r + 0.5) + ch * BOARD_UP_CELLS;
            vector local = wid * lx + tup * lz + nrm * (SCREEN_THICK * 0.5 + out);
            // o parametro de rez leva o indice: o GEMS_CELL do objeto se renomeia sozinho
            llRezObject(obj, pos + local * rot, ZERO_VECTOR, tiltRot * rot, packed + offset + r * 8 + c);
            ++n;
        }
    }
    return n;
}

report(integer cells, integer gems)
{
    vector size = llGetScale();
    float cw = (dimAlong((-FRONT_AXIS) % UP_AXIS, size) * BOARD_SCALE) / 8.0;
    float ch = (dimAlong(UP_AXIS, size) * BOARD_SCALE) / 8.0;
    if (cw > ch) cw = ch;
    if (ch > cw) ch = cw;
    if (cells > 0) llOwnerSay("Criei " + (string)cells + " celulas CG_CELL_<linha>_<coluna> (lado " + (string)(cw * 0.98) + " m, redimensionadas sozinhas).");
    if (gems > 0) llOwnerSay("Criei " + (string)gems + " gemas moveis CG_GEM_0..63 (lado " + (string)(cw * 0.88) + " m, redimensionadas sozinhas).");
    llOwnerSay("AGORA: selecione celulas + gemas + a base (a BASE POR ULTIMO) e linke com Ctrl+L. Depois apague este script e os objetos modelo.");
}

default
{
    state_entry()
    {
        CH = -1 - (integer)llFrand(2000000000.0);
        llOwnerSay("GEMS_BUILDER pronto. Toque na base para escolher o que criar.");
    }

    touch_start(integer n)
    {
        if (llDetectedKey(0) != llGetOwner()) return;
        if (LISTEN_H != 0) llListenRemove(LISTEN_H);
        LISTEN_H = llListen(CH, "", llGetOwner(), "");
        llDialog(llGetOwner(), "O que criar? Frente do painel (eixo local): " + (string)FRONT_AXIS + " cima: " + (string)UP_AXIS, ["Celulas", "Gemas", "Ambos"], CH);
        llSetTimerEvent(60.0);
    }

    listen(integer ch, string name, key id, string msg)
    {
        integer c = 0;
        integer g = 0;
        if (msg == "Celulas" || msg == "Ambos") c = rezAll(CELL_OBJ, OUT_CELL, 0, 0.98);
        if (msg == "Gemas" || msg == "Ambos") g = rezAll(GEM_OBJ, OUT_GEM, 1000, 0.88);
        if (c + g > 0) report(c, g);
        llListenRemove(LISTEN_H);
        LISTEN_H = 0;
        llSetTimerEvent(0.0);
    }

    timer()
    {
        if (LISTEN_H != 0) llListenRemove(LISTEN_H);
        LISTEN_H = 0;
        llSetTimerEvent(0.0);
    }
}
