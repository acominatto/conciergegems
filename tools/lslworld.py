"""lslworld - mundo de teste para varios scripts LSL conversando entre si (so para testes fora do Second Life).

Simula o que o Concierge Gems 2.0 precisa do simulador:
  * um linkset com prims nomeados (posicao local, cor/alpha, glow, textura, tamanho);
  * link_message entregue a TODOS os scripts, inclusive o remetente, em ordem, sem custo de tempo;
  * um relogio virtual: llGetTime, llResetTime e llSetTimerEvent por script (o timer dispara a cada `tick` s);
  * Linkset Data (dicionario), notecards ausentes, HTTP com respostas programadas pelo teste.

O QUE ISTO NAO E: nao reproduz a latencia real do simulador, o limite de atualizacoes de prim por segundo, nem a
interpolacao do viewer. Prova que a LOGICA de movimento e de mensagens chega ao estado certo; a fluidez visual so
se mede dentro do Second Life.
"""
import heapq
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lslsim import LSL, CONSTS  # noqa: E402


class Prim:
    def __init__(self, name, pos):
        self.name = name
        self.pos = tuple(float(x) for x in pos)
        self.alpha = 1.0
        self.color = (1.0, 1.0, 1.0)
        self.glow = 0.0
        self.tex = None
        self.tex_offset = (0.0, 0.0, 0.0)
        self.size = (0.1, 0.1, 0.01)
        self.text = ''
        self.anim_on = False
        self.particles = False
        self.bursts = 0                 # quantas rajadas de particulas ja recebeu
        self.anim_starts = 0            # quantas animacoes de textura ja iniciou
        self.pos_writes = 0


class World:
    def __init__(self):
        self.prims = {}                 # link -> Prim (link 1 = raiz)
        self.scripts = []               # instancias LSLWorld
        self.time = 0.0
        self.queue = []                 # mensagens pendentes: (seq, dest_script_or_None, ...)
        self.ldata = {}
        self.inventory = {}             # nome -> tipo
        self.http = []                  # requisicoes feitas: (key, url, params, body)
        self.http_seq = 0
        self.owner_says = []
        self.unix = 1_800_000_000
        self.detected = []              # [(link, key)]
        self.log = []                   # eventos de interesse para os testes
        self.msg_log = []               # (tempo, num, texto) de todo link_message enviado
        self.pos_writes_total = 0
        self.max_batch = 0              # maior lote de prims mexidos numa unica chamada

    # ---------- prims ----------
    def add_prim(self, link, name, pos):
        self.prims[link] = Prim(name, pos)

    def link_by_name(self, name):
        for k, v in self.prims.items():
            if v.name == name:
                return k
        return 0

    # ---------- scripts ----------
    def add_script(self, name, source, rng=None):
        sc = LSLWorld(self, name, source, rng)
        self.scripts.append(sc)
        return sc

    def start(self):
        for sc in self.scripts:
            sc.start()
        self.pump()

    # ---------- barramento e relogio ----------
    def send_link_message(self, sender, link, num, text, key):
        self.msg_log.append((round(self.time, 4), num, text))
        for sc in self.scripts:
            self.queue.append((sc, sender, num, text, key))

    def pump(self):
        """entrega todas as mensagens pendentes (tempo zero); um handler pode gerar mais mensagens"""
        guard = 0
        while self.queue:
            guard += 1
            if guard > 200000:
                raise RuntimeError('barramento em laco (mensagens sem fim)')
            sc, sender, num, text, key = self.queue.pop(0)
            sc.deliver('link_message', sender, num, text, key)

    def advance(self, seconds, step=None):
        """avanca o relogio disparando os timers dos scripts na ordem certa"""
        end = self.time + seconds
        while True:
            self.pump()
            nxt = None
            for sc in self.scripts:
                if sc.timer_interval > 0:
                    t = sc.timer_next
                    if nxt is None or t < nxt[0]:
                        nxt = (t, sc)
            if nxt is None or nxt[0] > end:
                self.time = end
                self.pump()
                return
            self.time = max(self.time, nxt[0])
            sc = nxt[1]
            sc.timer_next = self.time + sc.timer_interval
            sc.deliver('timer')
            self.pump()

    def run_until_quiet(self, limit=30.0, cond=None):
        """avanca ate nenhum timer estar ativo (ou `cond()` ser verdadeira). Devolve o tempo gasto."""
        t0 = self.time
        while self.time - t0 < limit:
            self.pump()
            if cond and cond():
                return self.time - t0
            active = [s for s in self.scripts if s.timer_interval > 0]
            if not active and not self.queue:
                return self.time - t0
            self.advance(min(s.timer_interval for s in active) if active else 0.01)
        return self.time - t0


class LSLWorld(LSL):
    def __init__(self, world, name, source, rng=None):
        self.world = world
        self.name = name
        self.timer_interval = 0.0
        self.timer_next = 0.0
        self.t0 = 0.0                   # llResetTime
        LSL.__init__(self, source, rng, extra=self._world_builtins())

    def start(self):
        if 'state_entry' in self.events:
            self.event('state_entry')

    def deliver(self, ev, *args):
        if ev in self.events:
            self.event(ev, *args)

    # ---------- funcoes ll* que dependem do mundo ----------
    def _world_builtins(self):
        w = self

        def target_link(link):
            return link

        def apply_params(link, params):
            """interpreta uma lista de parametros de prim (PRIM_LINK_TARGET muda o alvo)"""
            i = 0
            cur = link
            touched = set()
            while i < len(params):
                code = params[i]
                if code == CONSTS['PRIM_LINK_TARGET']:
                    cur = int(params[i + 1])
                    i += 2
                    continue
                prim = w.world.prims.get(cur)
                if code == CONSTS['PRIM_POS_LOCAL']:
                    if prim:
                        prim.pos = tuple(params[i + 1])
                        prim.pos_writes += 1
                        w.world.pos_writes_total += 1
                        touched.add(cur)
                    i += 2
                elif code == CONSTS['PRIM_COLOR']:
                    if prim:
                        prim.color = tuple(params[i + 2])
                        prim.alpha = float(params[i + 3])
                    i += 4
                elif code == CONSTS['PRIM_GLOW']:
                    if prim:
                        prim.glow = float(params[i + 2])
                    i += 3
                elif code == CONSTS['PRIM_FULLBRIGHT']:
                    i += 3
                elif code == CONSTS['PRIM_TEXTURE']:
                    if prim:
                        prim.tex = params[i + 2]
                        prim.tex_offset = tuple(params[i + 4])
                    i += 6
                elif code == CONSTS['PRIM_SIZE']:
                    if prim:
                        prim.size = tuple(params[i + 1])
                    i += 2
                elif code == CONSTS['PRIM_TEXT']:
                    if prim:
                        prim.text = params[i + 1]
                    i += 4
                else:
                    raise RuntimeError('parametro de prim desconhecido: %r' % (code,))
            return len(touched)

        def set_link_params_fast(link, params):
            n = apply_params(link, list(params))
            if n > w.world.max_batch:
                w.world.max_batch = n

        def get_link_params(link, want):
            prim = w.world.prims.get(link)
            out = []
            for code in want:
                if prim is None:
                    out.append((0.0, 0.0, 0.0))
                elif code == CONSTS['PRIM_POS_LOCAL']:
                    out.append(prim.pos)
                elif code == CONSTS['PRIM_SIZE']:
                    out.append(prim.size)
                else:
                    out.append(0)
            return out

        def message_linked(link, num, text, key):
            w.world.send_link_message(w, link, num, text, key)

        def set_timer(t):
            w.timer_interval = float(t)
            w.timer_next = w.world.time + float(t)

        def ldw(k, v):
            new = str(v)
            used = sum(len(a) + len(b) for a, b in w.world.ldata.items())
            if used + len(k) + len(new) > 128 * 1024:
                return CONSTS['LINKSETDATA_EMEMORY']
            w.world.ldata[k] = new
            return CONSTS['LINKSETDATA_OK']

        def tex_anim(link, mode, face, x, y, a, b, r):
            pr = w.world.prims.get(link)
            if pr is not None:
                pr.anim_on = bool(mode & 1)
                if mode & 1:
                    pr.anim_starts += 1

        def particles(link, lst):
            pr = w.world.prims.get(link)
            if pr is not None:
                pr.particles = len(lst) > 0
                if len(lst) > 0:
                    pr.bursts += 1

        def http(url, params, body):
            w.world.http_seq += 1
            key = 'http-%d' % w.world.http_seq
            w.world.http.append((key, url, list(params), body, w))
            return key

        def json_obj(kind, lst):
            import json
            d = {}
            for i in range(0, len(lst), 2):
                d[str(lst[i])] = lst[i + 1]
            return json.dumps(d)

        return {
            'llSetLinkPrimitiveParamsFast': set_link_params_fast,
            'llSetLinkPrimitiveParams': set_link_params_fast,
            'llGetLinkPrimitiveParams': get_link_params,
            'llGetLinkName': lambda k: (w.world.prims[k].name if k in w.world.prims else ''),
            'llGetNumberOfPrims': lambda: len(w.world.prims),
            'llGetLinkNumberOfSides': lambda k: 1,
            'llMessageLinked': message_linked,
            'llSetTimerEvent': set_timer,
            'llGetTime': lambda: w.world.time - w.t0,
            'llResetTime': lambda: setattr(w, 't0', w.world.time),
            'llGetUnixTime': lambda: int(w.world.unix + w.world.time),
            'llOwnerSay': lambda s: w.world.owner_says.append((w.name, s)),
            'llRegionSayTo': lambda k, c, s: w.world.log.append(('say_to', str(k), s)),
            'llSetLinkTextureAnim': tex_anim,
            'llLinkParticleSystem': particles,
            'llSetLinkAlpha': lambda link, a, face: setattr(w.world.prims.get(link, Prim('?', (0, 0, 0))), 'alpha', float(a)),
            'llLinksetDataRead': lambda k: w.world.ldata.get(k, ''),
            'llLinksetDataWrite': ldw,
            'llLinksetDataDelete': lambda k: (w.world.ldata.pop(k, None), 0)[1],
            'llGetInventoryType': lambda n: w.world.inventory.get(n, -1),
            'llGetInventoryNumber': lambda t: sum(1 for v in w.world.inventory.values() if v == t),
            'llGetInventoryName': lambda t, i: [k for k, v in w.world.inventory.items() if v == t][i],
            'llGetNotecardLine': lambda n, i: 'nc-%s-%d' % (n, i),
            'llGetKey': lambda: 'obj-0000',
            'llGetOwner': lambda: 'owner-0000',
            'llGetDisplayName': lambda k: str(k),
            'llGetUsername': lambda k: str(k),
            'llKey2Name': lambda k: str(k),
            'llDetectedLinkNumber': lambda i: (w.world.detected[i][0] if i < len(w.world.detected) else 0),
            'llDetectedKey': lambda i: (w.world.detected[i][1] if i < len(w.world.detected) else ''),
            'llHTTPRequest': http,
            'llList2Json': json_obj,
            'llTriggerSound': lambda n, v: w.world.log.append(('sound', n)),
            'llPlaySound': lambda n, v: w.world.log.append(('sound', n)),
            'llPreloadSound': lambda n: None,
            'llSetObjectName': lambda n: None,
            'llResetScript': lambda: w.world.log.append(('reset', w.name)),
            'llGetMemoryLimit': lambda: 65536, 'llGetFreeMemory': lambda: 40000, 'llGetUsedMemory': lambda: 25000,
            'llSetLinkPrimitiveParamsFastNoop': lambda *a: None,
        }
