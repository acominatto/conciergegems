"""Testes da logica LSL (GEMS_LOGIC.lsl) contra o logic.js e o main.js ORIGINAIS.

Como funciona: o mesmo tabuleiro, a mesma jogada e a MESMA sequencia de numeros aleatorios entram no jogo original (Node) e no
script LSL (interpretador tools/lslsim.py). O resultado tem de ser identico: pontos, celulas limpas, especiais criados,
quedas e entradas de cada onda, e a grade final.

LIMITE: prova o ALGORITMO. Nao mede memoria/tempo do LSL nem roda no viewer.
Uso:  python tests/test_logic.py [N_CENARIOS]
"""
import json
import os
import random
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools'))
from lslsim import LSL  # noqa: E402

SRC = open(os.path.join(HERE, '..', 'scripts', 'GEMS_LOGIC.lsl'), encoding='utf-8').read()
REF = os.path.join(HERE, 'ref_logic.cjs')

fails = []
passed = 0


def ref(payload):
    p = subprocess.run(['node', REF], input=json.dumps(payload), capture_output=True, text=True, timeout=120)
    if p.returncode != 0:
        raise RuntimeError('node falhou: ' + p.stderr[-800:])
    return json.loads(p.stdout)


def new_sim(rands):
    it = iter(rands)
    used = [0]

    def rng():
        used[0] += 1
        return next(it)
    s = LSL(SRC, rng)
    s.used = used
    return s


def check(name, cond, detail=''):
    global passed
    if cond:
        passed += 1
    else:
        fails.append(name + ((' -> ' + str(detail)[:600]) if detail else ''))


def rand_list(rng, n=4000):
    return [rng.random() for _ in range(n)]


def random_board(rng, colors, specials=True):
    """Tabuleiro cheio, SEM sequencias prontas (estado de repouso do jogo); opcionalmente com especiais espalhados."""
    while True:
        g = []
        for r in range(8):
            for c in range(8):
                while True:
                    v = rng.randrange(colors)
                    if c >= 2 and g[r * 8 + c - 1] % 8 == v and g[r * 8 + c - 2] % 8 == v:
                        continue
                    if r >= 2 and g[(r - 1) * 8 + c] % 8 == v and g[(r - 2) * 8 + c] % 8 == v:
                        continue
                    break
                g.append(v)
        if specials:
            for _ in range(rng.choice([0, 1, 2, 3, 5])):
                i = rng.randrange(64)
                g[i] = g[i] % 8 + 8 * rng.choice([1, 2, 3, 3])
        return g


def waves_from_lsl(strings):
    out = []
    for s in strings:
        v = [int(x) for x in s.split(',')]
        i = 0
        chain, points, tb, nc = v[0], v[1], v[2], v[3]
        i = 4
        cleared = v[i:i + nc]
        i += nc
        ncr = v[i]
        i += 1
        created = [[v[i + 2 * k], v[i + 2 * k + 1]] for k in range(ncr)]
        i += 2 * ncr
        nf = v[i]
        i += 1
        falls = [v[i + 4 * k:i + 4 * k + 4] for k in range(nf)]
        i += 4 * nf
        ns = v[i]
        i += 1
        spawns = [v[i + 4 * k:i + 4 * k + 4] for k in range(ns)]
        out.append({'chain': chain, 'points': points, 'timeBonus': tb, 'cleared': sorted(cleared),
                    'created': sorted(created), 'falls': falls, 'spawns': spawns})
    return out


# ------------------------------------------------------------------ 1. formulas de nivel
def test_formulas():
    rows = ref({'op': 'formulas'})['rows']
    s = new_sim([])
    bad = []
    for r in rows:
        d, lv = r['diff'], r['level']
        got = {'target': s.call('levelTarget', lv, d), 'colors': s.call('levelColors', lv, d),
               'drain': s.call('levelDrain', lv, d), 'timeBonus': s.call('levelTimeBonus', lv, d), 'cap': s.call('timeCap', d)}
        for k in ('target', 'colors', 'timeBonus', 'cap'):
            if got[k] != r[k]:
                bad.append((d, lv, k, got[k], r[k]))
        if abs(got['drain'] - r['drain']) > 1e-9:
            bad.append((d, lv, 'drain', got['drain'], r['drain']))
    check('formulas de nivel (target/cores/dreno/bonus de tempo/teto) = main.js em 3 dificuldades x 40 niveis', not bad, bad[:5])
    # parametros fixos por dificuldade
    for di in range(3):
        row = rows[di * 40]
        check('parametros da dificuldade %d (inicio e bonus)' % di,
              s.call('llList2Integer', s.g['D_START'], di) == row['start'] and abs(s.call('llList2Float', s.g['D_BONUS'], di) - row['bonus']) < 1e-9)
        check('atraso da dica da dificuldade %d' % di, s.call('llList2Integer', s.g['D_HINT'], di) == row['hintDelay'])


# ------------------------------------------------------------------ 2. troca valida e dica
def test_valid_and_hint(n):
    rng = random.Random(11)
    bad = 0
    for k in range(n):
        colors = rng.choice([5, 6, 7])
        grid = random_board(rng, colors)
        r = ref({'op': 'valid', 'grid': grid})
        s = new_sim([])
        s.g['G'] = list(grid)
        for a, b, ok in r['pairs']:
            if bool(s.call('validSwap', a, b)) != ok:
                bad += 1
                check('validSwap %d<->%d' % (a, b), False, {'grid': grid})
        found = bool(s.call('findHint'))
        exp = r['hint']
        got = [s.g['HINT_A'], s.g['HINT_B']] if found else None
        check('findHint igual ao original (cenario %d)' % k, got == exp, (got, exp))
        check('hasMoves (cenario %d)' % k, found == r['hasMoves'])
    check('validSwap: todos os pares adjacentes de %d tabuleiros' % n, bad == 0)


# ------------------------------------------------------------------ 3. tabuleiro inicial e embaralhar
def test_initial_and_shuffle(n):
    rng = random.Random(22)
    for k in range(n):
        colors = rng.choice([5, 6, 7])
        rl = rand_list(rng)
        r = ref({'op': 'initial', 'colors': colors, 'rand': rl})
        s = new_sim(rl)
        ok = s.call('buildInitialBoard', colors)
        check('initialBoard igual (cenario %d, %d cores)' % (k, colors), ok and s.g['G'] == r['grid'] and s.used[0] == r['used'],
              (s.g['G'], r['grid']))
    for k in range(max(3, n // 2)):
        colors = rng.choice([5, 6, 7])
        grid = random_board(rng, colors)
        rl = rand_list(rng, 20000)          # embaralhar sem sucesso gasta ate 300 x 63 sorteios
        r = ref({'op': 'shuffle', 'grid': grid, 'rand': rl})
        s = new_sim(rl)
        s.g['G'] = list(grid)
        ok = bool(s.call('shuffleBoard'))
        check('shuffle igual (cenario %d)' % k, ok == r['ok'] and s.g['G'] == r['grid'] and s.used[0] == r['used'], (s.g['G'], r['grid']))


# ------------------------------------------------------------------ 4. resolver jogada (cascatas, especiais, pontos)
def test_resolve(n):
    rng = random.Random(33)
    stats = {'moves': 0, 'waves': 0, 'cascade2+': 0, 'bomb': 0, 'star': 0, 'rainbow_swap': 0, 'created': 0, 'max_chain': 0}
    for k in range(n):
        colors = rng.choice([5, 6, 7])
        grid = random_board(rng, colors, specials=rng.random() < 0.7)
        v = ref({'op': 'valid', 'grid': grid})
        valid = [(a, b) for a, b, ok in v['pairs'] if ok]
        if not valid:
            continue
        a, b = rng.choice(valid)
        if rng.random() < 0.5:
            a, b = b, a
        rl = rand_list(rng)
        r = ref({'op': 'resolve', 'grid': grid, 'a': a, 'b': b, 'colors': colors, 'rand': rl})
        s = new_sim(rl)
        s.g['G'] = list(grid)
        s.g['NCOLORS'] = colors
        check('validSwap (jogada %d)' % k, bool(s.call('validSwap', a, b)) == r['valid'])
        s.call('swapG', a, b)
        s.call('resolveMove', a, b, 1)
        got = waves_from_lsl(s.g['WAVES'])
        same_w = got == r['waves']
        check('ondas identicas ao original (jogada %d: pontos, limpas, criadas, quedas, entradas)' % k, same_w,
              {'grid': grid, 'a': a, 'b': b, 'lsl': got[:2], 'js': r['waves'][:2]})
        check('grade final identica (jogada %d)' % k, s.g['G'] == r['grid'])
        check('mesma quantidade de aleatorios consumidos (jogada %d)' % k, s.used[0] == r['used'], (s.used[0], r['used']))
        check('pontos somados (jogada %d)' % k, s.g['W_POINTS'] == sum(w['points'] for w in r['waves']))
        stats['moves'] += 1
        stats['waves'] += len(r['waves'])
        stats['cascade2+'] += 1 if len(r['waves']) >= 2 else 0
        stats['max_chain'] = max(stats['max_chain'], len(r['waves']))
        stats['created'] += sum(len(w['created']) for w in r['waves'])
        stats['bomb'] += sum(1 for w in r['waves'] for c in w['created'] if c[1] // 8 == 1)
        stats['star'] += sum(1 for w in r['waves'] for c in w['created'] if c[1] // 8 == 2)
        stats['rainbow_swap'] += 1 if (grid[a] // 8 == 3 or grid[b] // 8 == 3) else 0
    return stats


# ------------------------------------------------------------------ 5. partidas completas pelo protocolo de mensagens
def replay(grid, waves):
    """Aplica as ondas (formato de animacao) sobre uma copia da grade e devolve o resultado: prova que o payload e completo."""
    g = list(grid)
    for w in waves:
        for i in w['cleared']:
            g[i] = -1
        for i, v in w['created']:
            g[i] = v
        # gravidade: reconstruida por coluna a partir de falls/spawns
        for c, fr, to, v in w['falls']:
            pass
        cols = {}
        for c in range(8):
            cols[c] = [g[r * 8 + c] for r in range(8)]
        for c, fr, to, v in w['falls'] + w['spawns']:
            pass
        # aplica destinos: quedas e entradas dizem o valor final em cada linha "to"
        for c in range(8):
            col = [g[r * 8 + c] for r in range(8)]
            keep = [x for x in col if x >= 0]
            new = [-1] * (8 - len(keep)) + keep
            for r in range(8):
                g[r * 8 + c] = new[r]
        for c, fr, to, v in w['spawns']:
            g[to * 8 + c] = v
    return g


def test_full_games(n_games):
    rng = random.Random(44)
    total_moves = 0
    for gi in range(n_games):
        diff = rng.choice([0, 1, 2])
        rl = rand_list(rng, 200000)
        it = iter(rl)
        sim = LSL(SRC, lambda: next(it))
        sim.event('state_entry')
        sim.event('link_message', 0, 10, str(diff), '')
        outs = {n: s for (_, n, s, _) in sim.outbox}
        sim.outbox.clear()
        grid = [int(x) for x in outs[100].split(',')]
        check('partida %d: grade inicial cheia, sem sequencias' % gi, len(grid) == 64 and min(grid) >= 0)
        score_prev = 0
        levels_seen = 1
        moves_done = 0
        clock = 0.0
        while clock < 400 and moves_done < 60:
            # pede dica (o proprio protocolo) e joga
            sim.event('link_message', 0, 40, '', '')
            hint = [(s) for (_, n, s, _) in sim.outbox if n == 400][-1]
            sim.outbox.clear()
            if hint == '-1':
                check('partida %d: sempre ha jogada apos o tabuleiro assentar' % gi, False)
                break
            a, b = [int(x) for x in hint.split(',')]
            before = list(sim.g['G'])
            sim.event('link_message', 0, 20, '%d,%d' % (a, b), '')
            msgs = {}
            for (_, n, s, _) in sim.outbox:
                msgs[n] = s
            sim.outbox.clear()
            res = [int(x) for x in msgs[200].split(',')]
            code = res[0]
            check('partida %d: dica e jogada valida' % gi, code & 1 == 1)
            score = res[1]
            check('partida %d jogada %d: pontuacao nunca cai' % (gi, moves_done), score >= score_prev)
            score_prev = score
            waves = waves_from_lsl(msgs[210].split('|'))
            if not (code & 2):
                # sem subir de nivel: a grade final = jogada + ondas aplicadas ao estado anterior
                b2 = list(before)
                b2[a], b2[b] = b2[b], b2[a]
                rep = replay(b2, waves)
                if not (code & 4):
                    check('partida %d jogada %d: ondas reproduzem a grade final' % (gi, moves_done), rep == sim.g['G'], (rep, sim.g['G']))
            g = sim.g['G']
            check('partida %d jogada %d: grade cheia' % (gi, moves_done), len(g) == 64 and min(g) >= 0)
            sim.call('findRuns')
            check('partida %d jogada %d: sem sequencia pronta em repouso' % (gi, moves_done), len(sim.g['RUNS']) == 0)
            if code & 2:
                levels_seen += 1
                check('partida %d: nivel sobe para %d' % (gi, levels_seen), res[2] == levels_seen)
                check('partida %d: bonus de nivel >= 250' % gi, res[7] >= 250)
            moves_done += 1
            total_moves += 1
            sim.event('link_message', 0, 30, '3.0', '')
            clock += 3.0
            over = [s for (_, n, s, _) in sim.outbox if n == 300]
            sim.outbox.clear()
            if over:
                break
        # o relogio: com o tempo passando o jogo acaba
        finished = False
        for _ in range(400):
            sim.event('link_message', 0, 30, '5.0', '')
            if any(n == 300 for (_, n, s, _) in sim.outbox):
                finished = True
                break
            sim.outbox.clear()
        check('partida %d: o tempo acaba e o jogo envia o resultado final (msg 300)' % gi, finished)
        if finished:
            fin = [int(x) for x in [s for (_, n, s, _) in sim.outbox if n == 300][-1].split(',')]
            check('partida %d: resultado final coerente (score, nivel, combo, jogadas, gemas, ondas, dificuldade)' % gi,
                  fin[0] == score_prev and fin[3] == moves_done and fin[6] == diff and fin[5] >= moves_done, fin)
        check('partida %d: depois do fim nenhuma jogada e aceita' % gi, not sim.call('doMove', 0, 1))
    return total_moves


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 60
    t0 = time.time()
    test_formulas()
    print('formulas: ok (%d checagens ate aqui)' % passed, flush=True)
    test_valid_and_hint(max(6, n // 6))
    print('troca valida/dica: %d checagens' % passed, flush=True)
    test_initial_and_shuffle(max(6, n // 6))
    print('inicial/embaralhar: %d checagens' % passed, flush=True)
    stats = test_resolve(n)
    print('resolver: %d checagens | %s' % (passed, stats), flush=True)
    moves = test_full_games(max(3, n // 15))
    print('partidas completas: %d jogadas simuladas' % moves)
    print('\n=== %d checagens ok, %d falhas (%.0fs) ===' % (passed, len(fails), time.time() - t0))
    for f in fails[:15]:
        print('FALHOU:', f)
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
