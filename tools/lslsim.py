"""lslsim - interpretador do SUBCONJUNTO de LSL usado em scripts/GEMS_LOGIC.lsl (so para testes fora do Second Life).

Cobre: variaveis globais, funcoes, eventos, integer/float/string/key/list, if/else, for, while, do-while, return,
operadores (aritmeticos, comparacao, logicos SEM curto-circuito como no LSL, bit a bit, ++/--, atribuicao composta),
casts, listas e um conjunto pequeno de funcoes ll* (as usadas pela logica).

NAO e o LSL real: nao mede memoria nem tempo, usa ponto flutuante de 64 bits (o Second Life usa 32) e nao verifica
tipos com o rigor do compilador da Linden. Serve para provar que o ALGORITMO bate com o logic.js; a validacao final
(memoria, tempo, comportamento no viewer) e dentro do Second Life.
"""
import math
import re

TYPES = ('integer', 'float', 'string', 'key', 'list', 'vector', 'rotation')

# Constantes do LSL. Os numeros de PRIM_* / ANIM_* / PSYS_* sao os reais quando conhecidos; onde o valor nao importa
# para os testes basta que sejam distintos (o mundo de teste interpreta as listas de parametros por esses numeros).
CONSTS = {
    'TRUE': 1, 'FALSE': 0, 'PI': 3.14159265, 'TWO_PI': 6.2831853, 'EOF': '\n\n\n',
    'NULL_KEY': '00000000-0000-0000-0000-000000000000', 'ZERO_VECTOR': (0.0, 0.0, 0.0),
    'LINK_ROOT': 1, 'LINK_SET': -1, 'LINK_ALL_OTHERS': -2, 'LINK_ALL_CHILDREN': -3, 'LINK_THIS': -4,
    'ALL_SIDES': -1,
    'PRIM_SIZE': 7, 'PRIM_TEXTURE': 17, 'PRIM_COLOR': 18, 'PRIM_FULLBRIGHT': 20, 'PRIM_GLOW': 25, 'PRIM_TEXT': 26,
    'PRIM_POS_LOCAL': 33, 'PRIM_LINK_TARGET': 34, 'PRIM_ROT_LOCAL': 29,
    'INVENTORY_TEXTURE': 0, 'INVENTORY_SOUND': 1, 'INVENTORY_OBJECT': 6, 'INVENTORY_NOTECARD': 7, 'INVENTORY_NONE': -1,
    'ANIM_ON': 1, 'LOOP': 2, 'REVERSE': 4, 'PING_PONG': 8, 'SMOOTH': 16, 'ROTATE': 32, 'SCALE': 64,
    'CHANGED_INVENTORY': 1, 'CHANGED_LINK': 32, 'CHANGED_OWNER': 128, 'CHANGED_REGION_START': 1024,
    'STRING_TRIM': 3, 'JSON_OBJECT': 'json-object', 'HTTP_METHOD': 0, 'HTTP_MIMETYPE': 1, 'HTTP_VERIFY_CERT': 3,
    'LINKSETDATA_OK': 0, 'LINKSETDATA_EMEMORY': 1,
    'PSYS_PART_FLAGS': 0, 'PSYS_SRC_PATTERN': 9, 'PSYS_PART_START_COLOR': 1, 'PSYS_PART_END_COLOR': 3,
    'PSYS_PART_START_ALPHA': 2, 'PSYS_PART_END_ALPHA': 4, 'PSYS_PART_START_SCALE': 5, 'PSYS_PART_END_SCALE': 6,
    'PSYS_PART_MAX_AGE': 7, 'PSYS_SRC_BURST_PART_COUNT': 15, 'PSYS_SRC_BURST_RATE': 13, 'PSYS_SRC_BURST_RADIUS': 16,
    'PSYS_SRC_BURST_SPEED_MIN': 17, 'PSYS_SRC_BURST_SPEED_MAX': 18, 'PSYS_SRC_ACCEL': 8, 'PSYS_SRC_MAX_AGE': 19,
    'PSYS_PART_START_GLOW': 26, 'PSYS_PART_EMISSIVE_MASK': 256, 'PSYS_PART_INTERP_COLOR_MASK': 1,
    'PSYS_PART_INTERP_SCALE_MASK': 2, 'PSYS_PART_FOLLOW_VELOCITY_MASK': 16, 'PSYS_SRC_PATTERN_EXPLODE': 2,
    'PARCEL_DETAILS_NAME': 0,
}

TOKEN_RE = re.compile(r'''
    (?P<ws>\s+|//[^\n]*|/\*.*?\*/)
  | (?P<float>\d+\.\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?|\d+[eE][+-]?\d+)
  | (?P<int>0[xX][0-9a-fA-F]+|\d+)
  | (?P<str>"(?:\\.|[^"\\])*")
  | (?P<id>[A-Za-z_][A-Za-z_0-9]*)
  | (?P<op>\+\+|--|\+=|-=|\*=|/=|%=|==|!=|<=|>=|&&|\|\||<<|>>|[-+*/%<>=!&|^~(){}\[\],;:.])
''', re.X | re.S)


def tokenize(src):
    pos = 0
    out = []
    while pos < len(src):
        m = TOKEN_RE.match(src, pos)
        if not m:
            raise SyntaxError('caractere inesperado %r na posicao %d' % (src[pos], pos))
        pos = m.end()
        k = m.lastgroup
        if k == 'ws':
            continue
        out.append((k, m.group(k)))
    out.append(('eof', ''))
    return out


class Return(Exception):
    def __init__(self, v):
        self.v = v


class Parser:
    def __init__(self, toks):
        self.t = toks
        self.i = 0

    def peek(self, o=0):
        return self.t[self.i + o]

    def next(self):
        tok = self.t[self.i]
        self.i += 1
        return tok

    def accept(self, val):
        if self.peek()[1] == val and self.peek()[0] in ('op', 'id'):
            self.i += 1
            return True
        return False

    def expect(self, val):
        tok = self.next()
        if tok[1] != val:
            raise SyntaxError('esperado %r mas veio %r (token %d)' % (val, tok[1], self.i))
        return tok

    # ---------- programa ----------
    def program(self):
        gvars, funcs, events = [], {}, {}
        while self.peek()[0] != 'eof':
            t = self.peek()
            if t[1] in ('default', 'state'):
                self.next()
                if t[1] == 'state':
                    self.next()
                self.expect('{')
                while not self.accept('}'):
                    name = self.next()[1]
                    self.expect('(')
                    params = self.params()
                    body = self.block()
                    events[name] = (params, body)
                continue
            if t[1] in TYPES and self.peek(1)[0] == 'id' and self.peek(2)[1] == '(':
                rtype = self.next()[1]
                name = self.next()[1]
                self.expect('(')
                params = self.params()
                funcs[name] = (rtype, params, self.block())
            elif t[1] in TYPES:
                self.next()
                name = self.next()[1]
                init = None
                if self.accept('='):
                    init = self.expr()
                self.expect(';')
                gvars.append((t[1], name, init))
            elif t[0] == 'id' and self.peek(1)[1] == '(':
                name = self.next()[1]
                self.expect('(')
                params = self.params()
                funcs[name] = ('void', params, self.block())
            else:
                raise SyntaxError('declaracao inesperada: %r' % (t,))
        return gvars, funcs, events

    def params(self):
        ps = []
        if self.accept(')'):
            return ps
        while True:
            typ = self.next()[1]
            name = self.next()[1]
            ps.append((typ, name))
            if self.accept(')'):
                return ps
            self.expect(',')

    # ---------- instrucoes ----------
    def block(self):
        self.expect('{')
        stmts = []
        while not self.accept('}'):
            stmts.append(self.stmt())
        return ('block', stmts)

    def stmt(self):
        t = self.peek()
        if t[1] == '{' and t[0] == 'op':
            return self.block()
        if t[0] == 'id':
            if t[1] == 'if':
                self.next(); self.expect('(')
                c = self.expr(); self.expect(')')
                a = self.stmt()
                b = None
                if self.peek()[1] == 'else':
                    self.next()
                    b = self.stmt()
                return ('if', c, a, b)
            if t[1] == 'while':
                self.next(); self.expect('(')
                c = self.expr(); self.expect(')')
                return ('while', c, self.stmt())
            if t[1] == 'do':
                self.next()
                body = self.stmt()
                self.expect('while'); self.expect('(')
                c = self.expr(); self.expect(')'); self.expect(';')
                return ('dowhile', body, c)
            if t[1] == 'for':
                self.next(); self.expect('(')
                init = self.expr_list(';')
                cond = None if self.peek()[1] == ';' else self.expr()
                self.expect(';')
                incr = self.expr_list(')')
                return ('for', init, cond, incr, self.stmt())
            if t[1] == 'return':
                self.next()
                e = None if self.peek()[1] == ';' else self.expr()
                self.expect(';')
                return ('return', e)
            if t[1] in TYPES and self.peek(1)[0] == 'id':
                self.next()
                name = self.next()[1]
                init = None
                if self.accept('='):
                    init = self.expr()
                self.expect(';')
                return ('decl', t[1], name, init)
        if t[1] == ';':
            self.next()
            return ('block', [])
        e = self.expr()
        self.expect(';')
        return ('expr', e)

    def expr_list(self, end):
        es = []
        if self.accept(end):
            return es
        while True:
            es.append(self.expr())
            if self.accept(end):
                return es
            self.expect(',')

    # ---------- expressoes (precedencia C, atribuicao associa a direita) ----------
    BIN = [
        ('||',), ('&&',), ('|',), ('^',), ('&',), ('==', '!='), ('<', '<=', '>', '>='),
        ('<<', '>>'), ('+', '-'), ('*', '/', '%'),
    ]

    def expr(self):
        return self.assign()

    def assign(self):
        left = self.binary(0)
        t = self.peek()
        if t[0] == 'op' and t[1] in ('=', '+=', '-=', '*=', '/=', '%='):
            self.next()
            right = self.assign()
            if left[0] != 'var':
                raise SyntaxError('atribuicao a algo que nao e variavel')
            return ('assign', t[1], left[1], right)
        return left

    def binary(self, lvl):
        if lvl == len(self.BIN):
            return self.unary()
        left = self.binary(lvl + 1)
        while self.peek()[0] == 'op' and self.peek()[1] in self.BIN[lvl]:
            op = self.next()[1]
            right = self.binary(lvl + 1)
            left = ('bin', op, left, right)
        return left

    def unary(self):
        t = self.peek()
        if t[0] == 'op':
            if t[1] in ('-', '!', '~', '+'):
                self.next()
                return ('un', t[1], self.unary())
            if t[1] in ('++', '--'):
                self.next()
                v = self.unary()
                return ('preinc', t[1], v[1])
            if t[1] == '(' and self.peek(1)[1] in TYPES and self.peek(2)[1] == ')':
                self.next()
                typ = self.next()[1]
                self.next()
                return ('cast', typ, self.unary())
        return self.postfix()

    def postfix(self):
        e = self.primary()
        while True:
            t = self.peek()
            if t[0] == 'op' and t[1] == '.' and self.peek(1)[0] == 'id' and self.peek(1)[1] in ('x', 'y', 'z', 's'):
                self.next()
                e = ('member', e, self.next()[1])
                continue
            if t[0] == 'op' and t[1] in ('++', '--') and e[0] == 'var':
                self.next()
                return ('postinc', t[1], e[1])
            return e

    def primary(self):
        t = self.next()
        k, v = t
        if k == 'int':
            return ('lit', int(v, 0))
        if k == 'float':
            return ('lit', float(v))
        if k == 'str':
            return ('lit', bytes(v[1:-1], 'utf-8').decode('unicode_escape'))
        if k == 'id':
            if self.peek()[1] == '(' and self.peek()[0] == 'op':
                self.next()
                args = self.expr_list(')')
                return ('call', v, args)
            return ('var', v)
        if v == '(':
            e = self.expr()
            self.expect(')')
            return e
        if v == '[':
            items = self.expr_list(']')
            return ('list', items)
        if v == '<':                      # literal de vetor <x,y,z> ou rotacao <x,y,z,s>
            parts = [self.binary(7)]      # nivel acima de '<'/'>': o '>' final fecha o literal
            while self.accept(','):
                parts.append(self.binary(7))
            self.expect('>')
            return ('vec', parts)
        raise SyntaxError('expressao inesperada: %r' % (t,))


def _trunc_div(a, b):
    if b == 0:
        raise ZeroDivisionError('divisao por zero (o LSL real da erro de execucao)')
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


def _c_mod(a, b):
    if b == 0:
        raise ZeroDivisionError('modulo por zero')
    return a - b * _trunc_div(a, b)


class LSL:
    """Uma instancia = um script. rng() devolve floats em [0,1) (injetavel para testes deterministicos)."""

    def __init__(self, source, rng=None, extra=None):
        self.gvars, self.funcs, self.events = Parser(tokenize(source)).program()
        self.rng = rng or (lambda: 0.5)
        self.g = {}
        self.outbox = []            # llMessageLinked capturadas: (link, num, str, id)
        self.steps = 0
        self.max_steps = 5_000_000
        self.builtins = self._make_builtins()
        if extra:
            self.builtins.update(extra)          # funcoes do mundo de teste (prims, relogio, barramento...)
        self.unknown = set()                     # ll* chamadas sem implementacao (o teste pode exigir vazio)
        for typ, name, init in self.gvars:
            self.g[name] = self.default(typ) if init is None else self.coerce(typ, self.ev(init, {}))

    # ---------- valores ----------
    @staticmethod
    def default(typ):
        return {'integer': 0, 'float': 0.0, 'string': '', 'key': '', 'list': [],
                'vector': (0.0, 0.0, 0.0), 'rotation': (0.0, 0.0, 0.0, 1.0)}.get(typ, 0)

    @staticmethod
    def coerce(typ, v):
        if typ == 'float' and isinstance(v, int):
            return float(v)
        return v

    def to_s(self, v):
        if isinstance(v, tuple):
            return '<' + ', '.join('%.5f' % x for x in v) + '>'
        if isinstance(v, float):
            return '%.6f' % v
        if isinstance(v, list):
            return ''.join(self.to_s(x) for x in v)
        return str(v)

    def cast(self, typ, v):
        if typ == 'integer':
            if isinstance(v, str):
                m = re.match(r'\s*([+-]?\d+)', v)
                return int(m.group(1)) if m else 0
            return int(v)
        if typ == 'float':
            if isinstance(v, str):
                m = re.match(r'\s*([+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?)', v)
                return float(m.group(1)) if m else 0.0
            return float(v)
        if typ in ('string', 'key'):
            return self.to_s(v)
        if typ == 'list':
            return v if isinstance(v, list) else [v]
        return v

    @staticmethod
    def truthy(v):
        if isinstance(v, list):
            return len(v) > 0
        return bool(v)

    # ---------- execucao ----------
    def call(self, name, *args):
        """Chama uma funcao do script (ou builtin)."""
        if name in self.funcs:
            rtype, params, body = self.funcs[name]
            env = {}
            for (typ, pname), a in zip(params, args):
                env[pname] = self.coerce(typ, a)
            try:
                self.run(body, [env])
            except Return as r:
                return r.v
            return None
        if name not in self.builtins:
            self.unknown.add(name)
            return 0
        return self.builtins[name](*args)

    def event(self, name, *args):
        params, body = self.events[name]
        env = {}
        for (typ, pname), a in zip(params, args):
            env[pname] = self.coerce(typ, a)
        try:
            self.run(body, [env])
        except Return:
            pass

    def lookup(self, name, scopes):
        for s in reversed(scopes):
            if name in s:
                return s
        if name in self.g:
            return self.g
        if name in CONSTS:
            return {name: CONSTS[name]}
        raise NameError('variavel nao declarada: %s' % name)

    def ev(self, e, scopes):
        self.steps += 1
        if self.steps > self.max_steps:
            raise RuntimeError('passos demais (laco infinito?)')
        k = e[0]
        if k == 'lit':
            return e[1]
        if k == 'var':
            return self.lookup(e[1], scopes)[e[1]]
        if k == 'bin':
            op = e[1]
            a = self.ev(e[2], scopes)
            b = self.ev(e[3], scopes)            # sem curto-circuito, como no LSL
            return self.binop(op, a, b)
        if k == 'un':
            v = self.ev(e[2], scopes)
            if e[1] == '-':
                return tuple(-x for x in v) if isinstance(v, tuple) else -v
            if e[1] == '!':
                return 0 if self.truthy(v) else 1
            if e[1] == '~':
                return ~v
            return v
        if k == 'assign':
            op, name, rhs = e[1], e[2], self.ev(e[3], scopes)
            sc = self.lookup(name, scopes)
            if op != '=':
                rhs = self.binop(op[0], sc[name], rhs)
            if isinstance(sc[name], float) and isinstance(rhs, int):
                rhs = float(rhs)
            sc[name] = rhs
            return rhs
        if k == 'preinc' or k == 'postinc':
            sc = self.lookup(e[2], scopes)
            old = sc[e[2]]
            sc[e[2]] = old + (1 if e[1] == '++' else -1)
            return sc[e[2]] if k == 'preinc' else old
        if k == 'vec':
            return tuple(float(self.ev(x, scopes)) for x in e[1])
        if k == 'member':
            v = self.ev(e[1], scopes)
            return v['xyzs'.index(e[2])] if isinstance(v, tuple) else 0.0
        if k == 'cast':
            return self.cast(e[1], self.ev(e[2], scopes))
        if k == 'list':
            return [self.ev(x, scopes) for x in e[1]]
        if k == 'call':
            args = [self.ev(a, scopes) for a in e[2]]
            return self.call(e[1], *args)
        raise RuntimeError('no desconhecido %r' % (k,))

    def binop(self, op, a, b):
        if isinstance(a, tuple) or isinstance(b, tuple):
            return self.vecop(op, a, b)
        if op == '+':
            if isinstance(a, list):
                return a + (b if isinstance(b, list) else [b])
            if isinstance(b, list):
                return [a] + b
            if isinstance(a, str) or isinstance(b, str):
                return self.to_s(a) + self.to_s(b)
            return a + b
        if op == '-':
            return a - b
        if op == '*':
            return a * b
        if op == '/':
            if isinstance(a, int) and isinstance(b, int):
                return _trunc_div(a, b)
            return a / b
        if op == '%':
            return _c_mod(a, b)
        if op == '==':
            return 1 if a == b else 0
        if op == '!=':
            return 1 if a != b else 0
        if op == '<':
            return 1 if a < b else 0
        if op == '<=':
            return 1 if a <= b else 0
        if op == '>':
            return 1 if a > b else 0
        if op == '>=':
            return 1 if a >= b else 0
        if op == '&&':
            return 1 if (self.truthy(a) and self.truthy(b)) else 0
        if op == '||':
            return 1 if (self.truthy(a) or self.truthy(b)) else 0
        if op == '&':
            return a & b
        if op == '|':
            return a | b
        if op == '^':
            return a ^ b
        if op == '<<':
            return a << b
        if op == '>>':
            return a >> b
        raise RuntimeError('operador %r' % op)

    def vecop(self, op, a, b):
        # vetores/rotacoes como tuplas de floats: + e - entre iguais, * por escalar, * entre vetores = produto escalar
        if op in ('==', '!='):
            eq = 1 if a == b else 0
            return eq if op == '==' else 1 - eq
        at, bt = isinstance(a, tuple), isinstance(b, tuple)
        if op == '+' and at and bt:
            return tuple(x + y for x, y in zip(a, b))
        if op == '-' and at and bt:
            return tuple(x - y for x, y in zip(a, b))
        if op == '*':
            if at and bt:
                return sum(x * y for x, y in zip(a, b))
            if at:
                return tuple(x * float(b) for x in a)
            return tuple(float(a) * y for y in b)
        if op == '/' and at and not bt:
            return tuple(x / float(b) for x in a)
        raise TypeError('operacao %r nao suportada entre %r e %r' % (op, a, b))

    def run(self, s, scopes):
        k = s[0]
        if k == 'block':
            scopes = scopes + [{}]
            for x in s[1]:
                self.run(x, scopes)
        elif k == 'expr':
            self.ev(s[1], scopes)
        elif k == 'decl':
            scopes[-1][s[2]] = self.default(s[1]) if s[3] is None else self.coerce(s[1], self.ev(s[3], scopes))
        elif k == 'if':
            if self.truthy(self.ev(s[1], scopes)):
                self.run(s[2], scopes)
            elif s[3] is not None:
                self.run(s[3], scopes)
        elif k == 'while':
            while self.truthy(self.ev(s[1], scopes)):
                self.run(s[2], scopes)
        elif k == 'dowhile':
            while True:
                self.run(s[1], scopes)
                if not self.truthy(self.ev(s[2], scopes)):
                    break
        elif k == 'for':
            for x in s[1]:
                self.ev(x, scopes)
            while s[2] is None or self.truthy(self.ev(s[2], scopes)):
                self.run(s[4], scopes)
                for x in s[3]:
                    self.ev(x, scopes)
        elif k == 'return':
            raise Return(None if s[1] is None else self.ev(s[1], scopes))
        else:
            raise RuntimeError('instrucao desconhecida %r' % (k,))

    # ---------- funcoes ll* ----------
    def _make_builtins(self):
        def norm(i, n):
            return i + n if i < 0 else i

        def l2i(lst, i):
            n = len(lst)
            i = norm(i, n)
            if i < 0 or i >= n:
                return 0
            v = lst[i]
            return int(v) if not isinstance(v, str) else self.cast('integer', v)

        def l2f(lst, i):
            n = len(lst)
            i = norm(i, n)
            if i < 0 or i >= n:
                return 0.0
            return float(lst[i]) if not isinstance(lst[i], str) else self.cast('float', lst[i])

        def l2s(lst, i):
            n = len(lst)
            i = norm(i, n)
            if i < 0 or i >= n:
                return ''
            return self.to_s(lst[i])

        def replace(dst, src, s, e):
            n = len(dst)
            s, e = norm(s, n), norm(e, n)
            if s <= e:
                return dst[:s] + list(src) + dst[e + 1:]
            return list(src) + dst[e + 1:s]       # intervalo "invertido": mantem so o que esta fora

        def delete(dst, s, e):
            n = len(dst)
            s, e = norm(s, n), norm(e, n)
            if s <= e:
                return dst[:s] + dst[e + 1:]
            return dst[e + 1:s]

        def sub(lst, s, e):
            n = len(lst)
            s, e = norm(s, n), norm(e, n)
            if s <= e:
                return lst[max(s, 0):e + 1]
            return lst[:e + 1] + lst[s:]

        def find(src, test):
            m = len(test)
            for i in range(len(src) - m + 1):
                if src[i:i + m] == test:
                    return i
            return -1

        def dump(lst, sep):
            return sep.join(self.to_s(x) for x in lst)

        def parse(s, seps, spacers):
            if not seps and not spacers:
                return [s] if s else []
            pat = '|'.join(re.escape(x) for x in list(seps) + list(spacers))
            parts = re.split('(%s)' % pat, s) if spacers else re.split(pat, s)
            keep = []
            for p in parts:
                if p == '' or (not spacers and False):
                    continue
                if p in seps:
                    continue
                keep.append(p)
            return keep

        def message(link, num, s, key):
            self.outbox.append((link, num, s, key))

        return {
            'llList2Integer': l2i, 'llList2Float': l2f, 'llList2String': l2s,
            'llGetListLength': lambda l: len(l),
            'llListReplaceList': replace, 'llDeleteSubList': delete, 'llList2List': sub,
            'llListInsertList': lambda d, i, p: d[:norm(p, len(d))] + list(i) + d[norm(p, len(d)):],
            'llListFindList': find, 'llDumpList2String': dump, 'llParseString2List': parse,
            'llFloor': lambda x: int(math.floor(x)), 'llCeil': lambda x: int(math.ceil(x)),
            'llRound': lambda x: int(math.floor(x + 0.5)), 'llAbs': abs, 'llFabs': abs,
            'llFrand': lambda x: self.rng() * x, 'llMessageLinked': message,
            'llGetMemoryLimit': lambda: 65536, 'llGetFreeMemory': lambda: 40000, 'llGetUsedMemory': lambda: 25000, 'llGetUnixTime': lambda: 0, 'llOwnerSay': lambda s: None, 'llSay': lambda c, s: None,
            'llCSV2List': lambda s: [x.strip() for x in s.split(',')] if s != '' else [],
            'llList2Vector': lambda l, i: (l[norm(i, len(l))] if isinstance(l[norm(i, len(l))], tuple) else (0.0, 0.0, 0.0)),
            'llParseStringKeepNulls': lambda s, seps, sp: (re.split('|'.join(re.escape(x) for x in seps), s) if seps else [s]),
            'llGetSubString': lambda s, a, b: (s[norm(a, len(s)):norm(b, len(s)) + 1] if norm(a, len(s)) <= norm(b, len(s)) else ''),
            'llStringLength': lambda s: len(s),
            'llSubStringIndex': lambda s, t: s.find(t),
            'llStringTrim': lambda s, m: s.strip(),
            'llSin': lambda x: math.sin(x), 'llCos': lambda x: math.cos(x),
            'llPow': lambda a, b: float(a) ** float(b),
            'llVecMag': lambda v: math.sqrt(sum(x * x for x in v)),
            'llSqrt': lambda x: math.sqrt(x),
        }
