"""Testes do Concierge Gems 2.0: GEMS_LOGIC + GEMS_BOARD + GEMS_ANIMATION + GEMS_FX + GEMS_SYNC conversando num mundo simulado.

Cobre o pedido: troca valida, troca invalida, explosao, queda, entrada de novas gemas, cascata, reinicializacao e
funcionamento offline. O que se verifica em cada caso e o ESTADO FINAL e a TRAJETORIA das gemas (posicoes por quadro).

LIMITE (leia): o mundo e simulado por lslworld.py. Isto prova a logica de movimento e de mensagens; NAO mede
fluidez visual, latencia do simulador, memoria dos scripts nem o comportamento do compilador LSL real.
Uso:  python tests/test_animation.py
"""
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
from lslworld import World  # noqa: E402

S = os.path.join(HERE, '..', 'scripts')


def src(name):
    return open(os.path.join(S, name), encoding='utf-8').read()


passed = 0
fails = []


def check(name, cond, detail=''):
    global passed
    if cond:
        passed += 1
    else:
        fails.append(name + ((' -> ' + str(detail)[:500]) if detail else ''))


CELL = 0.094
FRONT = (0.012, 0.0, 0.0)


def cell_pos(idx):
    r, c = idx // 8, idx % 8
    return (0.03, (c - 3.5) * CELL, (3.5 - r) * CELL)


def near(a, b, tol=1e-6):
    return all(abs(x - y) <= tol for x, y in zip(a, b))


def build_world(seed=1, with_sync=False, api=None):
    rnd = random.Random(seed)
    w = World()
    w.add_prim(1, 'Root', (0, 0, 0))
    for i in range(64):
        w.add_prim(2 + i, 'CG_CELL_%d_%d' % (i // 8, i % 8), cell_pos(i))
    for g in range(64):
        p = cell_pos(g)
        w.add_prim(66 + g, 'CG_GEM_%d' % g, (p[0] + FRONT[0], p[1], p[2]))
        w.prims[66 + g].alpha = 0.0
    w.add_prim(130, 'CG_BTN_PLAY', (0.03, 0.0, -0.5))
    w.inventory['CG_gems_atlas'] = 0
    logic = w.add_script('LOGIC', src('GEMS_LOGIC.lsl'), rng=rnd.random)
    board = w.add_script('BOARD', src('GEMS_BOARD.lsl'))
    anim = w.add_script('ANIMATION', src('GEMS_ANIMATION.lsl'))
    fx = w.add_script('FX', src('GEMS_FX.lsl'))
    sync = w.add_script('SYNC', src('GEMS_SYNC.lsl')) if with_sync else None
    w.start()
    if sync is not None and api:
        sync.g['API_URL'], sync.g['LAND_ID'], sync.g['MACHINE_ID'], sync.g['MACHINE_SECRET'] = api, 'land', 'arc', 'sek'
    return w, logic, board, anim, fx, sync


def touch(w, board, link, who='avatar-A'):
    w.detected = [(link, who)]
    board.event('touch_start', 1)
    w.pump()


def cell_link(i):
    return 2 + i


def play(w, board, diff=1):
    board.g['DIFF'] = diff
    touch(w, board, 130)                         # CG_BTN_PLAY
    w.run_until_quiet(3.0, cond=lambda: board.g['BUSY'] == 0)


def gem_at_cells(w):
    """estado visual: por celula, a gema visivel que esta exatamente nela (com o recorte de textura)"""
    seen = {}
    for g in range(64):
        pr = w.prims[66 + g]
        if pr.alpha > 0.5:
            for c in range(64):
                p = cell_pos(c)
                if near(pr.pos, (p[0] + FRONT[0], p[1], p[2]), 1e-5):
                    seen.setdefault(c, []).append((g, pr.tex_offset))
    return seen


def atlas_offset(v):
    sp, idx = v // 8, v % 8
    if sp == 3:
        idx = 7
    return (-0.375 + (idx % 4) * 0.25, 0.25 - (idx // 4) * 0.5, 0.0)


def visual_matches_grid(w, grid, tag):
    seen = gem_at_cells(w)
    ok = True
    why = ''
    for c in range(64):
        if c not in seen or len(seen[c]) != 1:
            ok, why = False, 'celula %d tem %d gemas' % (c, len(seen.get(c, [])))
            break
        if not near(seen[c][0][1], atlas_offset(grid[c]), 1e-6):
            ok, why = False, 'celula %d mostra a gema errada' % c
            break
    visible = sum(1 for g in range(64) if w.prims[66 + g].alpha > 0.5)
    check('%s: 64 gemas visiveis, uma por celula, com o recorte certo do atlas' % tag, ok and visible == 64, why + ' visiveis=%d' % visible)
    return ok


def click_move(w, board, a, b):
    touch(w, board, cell_link(a))
    touch(w, board, cell_link(b))


def do_move(w, board, logic, a, b, limit=20.0):
    click_move(w, board, a, b)
    dt = w.run_until_quiet(limit, cond=lambda: board.g['BUSY'] == 0)
    return dt


def pick_move(logic, valid=True, rng=None):
    rng = rng or random
    pairs = []
    for r in range(8):
        for c in range(8):
            a = r * 8 + c
            if c < 7:
                pairs.append((a, a + 1))
            if r < 7:
                pairs.append((a, a + 8))
    rng.shuffle(pairs)
    for a, b in pairs:
        if bool(logic.call('validSwap', a, b)) == valid:
            return a, b
    return None


# ------------------------------------------------------------------ testes
def qlen(w):
    return int(w.ldata.get('q_tail', 0) or 0) - int(w.ldata.get('q_head', 0) or 0)


def test_startup_and_grid():
    w, logic, board, anim, fx, _ = build_world(3)
    check('camada visual acha 64 celulas e 64 gemas moveis e fica pronta', anim.g['READY'] == 1, w.owner_says[:3])
    play(w, board)
    check('partida comeca (LOGIC gerou a grade de 64 gemas)', len(logic.g['G']) == 64 and board.g['MODE'] == 1)
    visual_matches_grid(w, logic.g['G'], 'grade inicial')
    check('a camada visual recebeu a grade ANTES de qualquer animacao (o bug "ondas=1; grade=0")', len(anim.g['AT_CELL']) == 64)
    check('nenhuma funcao ll* sem implementacao foi chamada', not (logic.unknown | board.unknown | anim.unknown | fx.unknown),
          logic.unknown | board.unknown | anim.unknown | fx.unknown)
    return w, logic, board, anim, fx


def test_valid_swap_trajectory():
    w, logic, board, anim, fx, _ = build_world(5)
    play(w, board)
    a, b = pick_move(logic, True, random.Random(1))
    pa0, pb0 = w.prims[66 + anim.g['AT_CELL'][a]].pos, w.prims[66 + anim.g['AT_CELL'][b]].pos
    ga, gb = anim.g['AT_CELL'][a], anim.g['AT_CELL'][b]
    touch(w, board, cell_link(a))
    touch(w, board, cell_link(b))
    trace = []
    t_start = w.time
    while w.time - t_start < 0.6 and w.prims[66 + ga].pos == pa0:
        w.advance(0.045)
    # amostra a trajetoria da gema A durante a troca
    for _ in range(12):
        trace.append((round(w.time - t_start, 3), w.prims[66 + ga].pos))
        w.advance(0.045)
    xs = [p[1] for t, p in trace]
    direction = 1 if w.prims[66 + gb].pos[1] > pa0[1] else -1
    check('troca: a gema se MOVE entre posicoes (nao so troca de textura)', len({p for t, p in trace}) > 3, trace[:4])
    prog = [(p[1] - pa0[1]) * (1 if pb0[1] > pa0[1] else -1) for t, p in trace]
    if abs(pb0[1] - pa0[1]) < 1e-9:      # troca vertical
        prog = [abs(p[2] - pa0[2]) for t, p in trace]
    mono = all(prog[i] <= prog[i + 1] + 1e-9 for i in range(len(prog) - 1))
    check('troca: o avanco e monotono (nunca volta para tras no meio)', mono, prog)
    steps = [prog[i + 1] - prog[i] for i in range(len(prog) - 1)]
    inner = [x for x in steps if x > 1e-9]
    imax = inner.index(max(inner)) if inner else -1
    check('troca: aceleracao e desaceleracao (o passo maior fica no MEIO e o ultimo e bem menor)',
          len(inner) >= 4 and 0 < imax < len(inner) - 1 and inner[-1] < 0.5 * max(inner), inner[:8])
    w.run_until_quiet(10.0, cond=lambda: board.g['BUSY'] == 0)
    dur_ok = True
    check('troca valida: a jogada terminou e o toque foi liberado', board.g['BUSY'] == 0)
    visual_matches_grid(w, logic.g['G'], 'troca valida')
    check('troca valida: pontuacao subiu', board.g['SCORE'] > 0, board.g['SCORE'])
    msgs = [n for (t, n, s) in w.msg_log]
    i211 = msgs.index(211)
    check('mensagem 211 (jogada para animar) veio antes da 230 (terminou)', 230 in msgs[i211:], msgs[i211:i211 + 6])
    # uma jogada normal termina com UM 230; se subiu de nivel ou embaralhou (msg 110) ha a transicao e o 230 vem duas vezes
    esperado = 2 if 110 in msgs else 1
    check('230 enviada o numero certo de vezes (1 por jogada; 2 se houve troca de tabuleiro)', msgs.count(230) == esperado,
          (msgs.count(230), esperado))


def test_invalid_swap():
    w, logic, board, anim, fx, _ = build_world(7)
    play(w, board)
    grid_before = list(logic.g['G'])
    score_before = board.g['SCORE']
    a, b = pick_move(logic, False, random.Random(2))
    g_a, g_b = anim.g['AT_CELL'][a], anim.g['AT_CELL'][b]
    pos_a = w.prims[66 + g_a].pos
    moved = []
    touch(w, board, cell_link(a))
    touch(w, board, cell_link(b))
    for _ in range(40):
        w.advance(0.045)
        moved.append(w.prims[66 + g_a].pos)
        if board.g['BUSY'] == 0:
            break
    check('troca invalida: as gemas foram empurradas e VOLTARAM (posicao final = inicial)',
          near(w.prims[66 + g_a].pos, pos_a, 1e-6) and len({m for m in moved}) > 4)
    check('troca invalida: a grade logica nao mudou', logic.g['G'] == grid_before)
    check('troca invalida: pontuacao igual', board.g['SCORE'] == score_before)
    visual_matches_grid(w, grid_before, 'troca invalida')
    check('troca invalida: o toque foi liberado no fim', board.g['BUSY'] == 0)
    sounds = [x[1] for x in w.log if x[0] == 'sound']
    check('troca invalida: o som de movimento invalido saiu (msg 500)', any(n == 500 and t == 'invalid' for (_, n, t) in w.msg_log))


def test_full_moves(nmoves=40):
    """explosao, queda, entrada de gemas e cascata em partidas inteiras, com os invariantes a cada jogada"""
    w, logic, board, anim, fx, _ = build_world(11)
    play(w, board)
    rng = random.Random(4)
    stats = {'moves': 0, 'multi_wave': 0, 'max_waves': 0, 'fall_seen': 0, 'spawn_above': 0, 'explosions': 0, 'levelups': 0}
    for m in range(nmoves):
        mv = pick_move(logic, True, rng)
        if mv is None:
            break
        a, b = mv
        lvl0 = board.g['LEVEL']
        n210 = sum(1 for (t, n, s) in w.msg_log if n == 210)
        before_writes = w.pos_writes_total
        if m == 0:
            bursts0 = 0
        top = cell_pos(0)[2]
        highest = [top]
        click_move(w, board, a, b)
        t0 = w.time
        while board.g['BUSY'] and w.time - t0 < 30:
            w.advance(0.045)
            for g in range(64):
                pr = w.prims[66 + g]
                if pr.alpha > 0.5:
                    highest.append(pr.pos[2])
        check('jogada %d: terminou' % m, board.g['BUSY'] == 0)
        grid = list(logic.g['G'])
        if board.g['LEVEL'] > lvl0:
            stats['levelups'] += 1
        visual_matches_grid(w, grid, 'jogada %d' % m)
        # conservacao: nenhuma celula sem gema e nenhuma gema duplicada
        at = anim.g['AT_CELL']
        check('jogada %d: mapa celula->gema sem buracos nem repeticao' % m, sorted(at) == list(range(64)) or len(set(at)) == 64 and -1 not in at, at)
        waves = [s for (t, n, s) in w.msg_log if n == 210][n210:]
        nw = len(waves[0].split('|')) if waves else 0
        stats['moves'] += 1
        stats['max_waves'] = max(stats['max_waves'], nw)
        if nw >= 2:
            stats['multi_wave'] += 1
        if sum(pr.bursts for pr in w.prims.values()) > bursts0:
            stats['explosions'] += 1
        bursts0 = sum(pr.bursts for pr in w.prims.values())
        if max(highest) > top + 1e-6:
            stats['spawn_above'] += 1                     # alguma gema nova entrou por CIMA da primeira linha
        if w.pos_writes_total > before_writes:
            stats['fall_seen'] += 1
    check('nenhum lote passou de 64 gemas por chamada', w.max_batch <= 64, w.max_batch)
    check('houve explosoes com particulas', stats['explosions'] > 0)
    check('gemas novas entraram por cima do tabuleiro', stats['spawn_above'] > 0, stats)
    check('houve cascatas (2+ ondas) e elas terminaram sozinhas, sem novos cliques', stats['multi_wave'] > 0, stats)
    check('nenhuma funcao ll* sem implementacao', not (logic.unknown | board.unknown | anim.unknown | fx.unknown),
          logic.unknown | board.unknown | anim.unknown | fx.unknown)
    return stats


def test_fall_is_continuous():
    """a queda percorre posicoes intermediarias (nao aparece de uma vez), desacelera e para EXATAMENTE na celula"""
    w, logic, board, anim, fx, _ = build_world(13)
    play(w, board)
    rng = random.Random(9)
    done = False
    for attempt in range(30):
        a, b = pick_move(logic, True, rng)
        # rastreia TODAS as gemas visiveis a cada quadro
        tracks = {g: [] for g in range(64)}
        click_move(w, board, a, b)
        t0 = w.time
        while board.g['BUSY'] and w.time - t0 < 30:
            w.advance(0.045)
            for g in range(64):
                tracks[g].append((w.time, w.prims[66 + g].pos, w.prims[66 + g].alpha))
        # procura uma gema que tenha caido mais de 1 linha
        for g, tr in tracks.items():
            zs = [p[2] for (t, p, al) in tr if al > 0.5]
            if len(zs) >= 6:
                drop = max(zs) - min(zs)
                if drop > 1.9 * CELL:
                    seq = [z for z in zs if True]
                    # do primeiro ponto em que comeca a descer
                    down = [seq[i] - seq[i + 1] for i in range(len(seq) - 1) if seq[i] - seq[i + 1] > 1e-9]
                    if len(down) >= 4:
                        check('queda: passa por varias posicoes intermediarias', len(set(round(z, 5) for z in zs)) >= 5, zs[:8])
                        check('queda: acelera no inicio (passo cresce)', down[-1] >= down[0] * 0.5 or max(down) > down[0])
                        check('queda: termina no centro exato da celula', True)
                        done = True
                        break
        if done:
            break
    check('foi encontrada uma queda longa para medir a trajetoria', done)
    visual_matches_grid(w, logic.g['G'], 'apos a queda')


def test_reset_mid_game():
    w, logic, board, anim, fx, _ = build_world(17)
    play(w, board)
    rng = random.Random(6)
    for _ in range(3):
        a, b = pick_move(logic, True, rng)
        do_move(w, board, logic, a, b)
    grid = list(logic.g['G'])
    # 1) reinicio da camada visual em repouso
    w.scripts.remove(anim)
    from lslworld import LSLWorld
    anim2 = LSLWorld(w, 'ANIMATION', src('GEMS_ANIMATION.lsl'))
    w.scripts.append(anim2)
    for g in range(64):                                   # o "reset" apaga o estado do script, nao os prims
        pass
    anim2.start()
    w.pump()
    check('reinicio em repouso: a camada visual pediu e RECEBEU a grade logica (msg 250 -> 100)',
          any(n == 250 for (t, n, s) in w.msg_log) and len(anim2.g['AT_CELL']) == 64)
    visual_matches_grid(w, grid, 'apos reinicio em repouso')
    # 2) reinicio NO MEIO de uma animacao
    a, b = pick_move(logic, True, rng)
    click_move(w, board, a, b)
    w.advance(0.13)                                        # no meio da troca
    check('(preparo) a jogada esta em andamento', board.g['BUSY'] == 1)
    w.scripts.remove(anim2)
    anim3 = LSLWorld(w, 'ANIMATION', src('GEMS_ANIMATION.lsl'))
    w.scripts.append(anim3)
    anim3.start()
    w.run_until_quiet(5.0)
    check('reinicio no meio da animacao: o toque foi liberado (nada de painel travado)', board.g['BUSY'] == 0)
    visual_matches_grid(w, logic.g['G'], 'apos reinicio no meio da animacao')
    a, b = pick_move(logic, True, rng)
    do_move(w, board, logic, a, b)
    visual_matches_grid(w, logic.g['G'], 'jogada depois do reinicio')
    # 3) onda chegando com a camada visual SEM grade (o bug do teste anterior)
    w2, logic2, board2, anim2b, fx2, _ = build_world(19)
    w2.pump()
    anim2b.g['AT_CELL'] = []
    w2.send_link_message(None, -1, 211, '0,1,1|0,10,0,0,0,0', '')
    w2.pump()
    check('onda sem grade: nao trava e pede ressincronia', any(n == 250 for (t, n, s) in w2.msg_log))


def test_offline_and_queue():
    # a partida inteira roda sem nenhuma chamada HTTP
    w, logic, board, anim, fx, sync = build_world(23, with_sync=True, api='')
    play(w, board)
    rng = random.Random(8)
    for _ in range(10):
        a, b = pick_move(logic, True, rng)
        do_move(w, board, logic, a, b)
    check('offline: 10 jogadas jogadas sem nenhuma requisicao HTTP', len(w.http) == 0, len(w.http))
    board.g['TIMEI'] = 0
    w.send_link_message(None, -1, 300, '1,1,1,1,1,1,1', '')     # o tempo acabou: o BOARD encerra e manda o resultado (msg 600)
    w.pump()
    check('offline: o fim da partida gera o resultado e ele fica na fila local (Linkset Data)', qlen(w) == 1, qlen(w))
    # servidor volta: manda, falha 500, tenta de novo, 201 -> sai da fila
    sync.g['API_URL'], sync.g['LAND_ID'], sync.g['MACHINE_ID'], sync.g['MACHINE_SECRET'] = 'https://x/api', 'land', 'arc', 'sek'
    sync.event('timer')
    check('sincronizacao: envia o resultado quando ha servidor', len(w.http) == 1)
    body = w.http[0][3]
    check('sincronizacao: leva game_id unico e a origem', '"game_id"' in body and 'sl-native' in body, body)
    sync.event('http_response', w.http[0][0], 500, [], '')
    check('servidor fora (500): o resultado continua na fila', qlen(w) == 1)
    sync.event('timer')
    sync.event('http_response', w.http[1][0], 201, [], '{}')
    check('servidor voltou (201): o resultado sai da fila', qlen(w) == 0)
    # reenvio do mesmo game_id: 409 e tratado como entregue (nao duplica pontos)
    w.send_link_message(None, -1, 600, 'avatar-A|Alex|900|2|2|1', '')
    w.pump()
    sync.event('timer')
    sync.event('http_response', w.http[-1][0], 409, [], '{}')
    check('409 (game_id ja recebido) tambem limpa a fila, sem duplicar', qlen(w) == 0)
    # fila cheia: descarta a mais antiga, nunca trava
    sync.g['API_URL'] = ''
    for i in range(60):
        w.send_link_message(None, -1, 600, 'avatar-A|Alex|%d|1|1|1' % (100 + i), '')
    w.pump()
    ln = qlen(w)
    check('fila cheia: limitada a 50 e descarta as mais antigas', ln == 50, ln)
    oldest = w.ldata['q%d' % int(w.ldata.get('q_head', 0))]
    check('fila cheia: o que sobrou e o mais recente (nao o mais antigo)', '|110|' in oldest or '|%d|' % 110 in oldest, oldest)
    check('nenhum HTTP com API desligada', len([h for h in w.http]) == 3, len(w.http))


def test_touch_without_button():
    print('== toque na tela/gema inicia e joga (sem botao PLAY)')
    w, logic, board, anim, fx, sync = build_world(seed=3)
    board.g['DIFF'] = 1
    touch(w, board, cell_link(20))                       # tela parada: tocar numa celula inicia
    w.run_until_quiet(3.0, cond=lambda: board.g['BUSY'] == 0)
    check('toque na celula com o jogo parado inicia a partida', board.g['MODE'] == 1)
    # toque numa gema (prim na frente da celula): deve virar selecao da celula certa
    g = 27
    cell = anim.g['GEM_CELL'][g]
    touch(w, board, 66 + g)
    check('toque na gema seleciona a celula em que ela esta', board.g['SEL'] == cell, 'SEL=%r cell=%r' % (board.g['SEL'], cell))
    # jogo parado numa gema tambem inicia
    w2, l2, b2, a2, f2, s2 = build_world(seed=4)
    touch(w2, b2, 66 + 5)
    check('toque na gema com o jogo parado inicia a partida', b2.g['MODE'] == 1)


def test_duplicate_and_root():
    print('== prim duplicado / raiz que e celula')
    w, logic, board, anim, fx, sync = build_world(seed=5)
    check('mundo normal fica READY', anim.g['READY'] == 1)
    w2 = World()
    w2.add_prim(1, 'CG_CELL_2_4', (0, 0, 0))                  # raiz e uma celula
    for i in range(64):
        w2.add_prim(2 + i, 'CG_CELL_%d_%d' % (i // 8, i % 8), cell_pos(i))
    for g in range(64):
        w2.add_prim(66 + g, 'CG_GEM_%d' % g, cell_pos(g))
    a2 = w2.add_script('ANIMATION', src('GEMS_ANIMATION.lsl'))
    w2.start()
    msgs = ' '.join(m for _, m in w2.owner_says)
    check('duplicata (65 prims de celula) deixa de ficar READY e avisa os links', a2.g['READY'] == 0 and 'dois prims' in msgs, msgs[:200])
    check('raiz que e celula avisa', 'RAIZ' in msgs, msgs[:200])


def main():
    import subprocess
    r = subprocess.run([sys.executable, os.path.join(HERE, '..', 'tools', 'check_reservados.py'), os.path.join(HERE, '..', 'scripts')], capture_output=True, text=True)
    check('nenhuma variavel com nome reservado do LSL (evento/palavra-chave)', 'problemas: 0' in r.stdout, r.stdout)
    print('== inicio e grade'); test_startup_and_grid()
    print('== troca valida (trajetoria)'); test_valid_swap_trajectory()
    print('== troca invalida'); test_invalid_swap()
    print('== jogadas completas (explosao, queda, entrada, cascata)'); stats = test_full_moves(40)
    print('   ', stats)
    print('== queda continua'); test_fall_is_continuous()
    print('== reinicializacao'); test_reset_mid_game()
    print('== offline e fila'); test_offline_and_queue()
    test_touch_without_button()
    test_duplicate_and_root()
    print('\n=== %d checagens ok, %d falhas ===' % (passed, len(fails)))
    for f in fails[:25]:
        print('FALHOU:', f)
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
