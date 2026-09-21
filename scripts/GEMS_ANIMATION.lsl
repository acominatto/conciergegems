// GEMS_ANIMATION.lsl - ponte leve.
// A animacao real fica em GEMS_RENDER.lsl para evitar Stack-Heap Collision neste script.

default
{
    state_entry()
    {
        llOwnerSay("GEMS_ANIMATION: ponte leve ativa. O movimento fica no GEMS_RENDER.");
        llMessageLinked(LINK_SET, 250, "", "");
    }

    on_rez(integer p) { llResetScript(); }

    changed(integer c)
    {
        if (c & (CHANGED_LINK | CHANGED_OWNER | CHANGED_REGION_START)) llResetScript();
    }
}
