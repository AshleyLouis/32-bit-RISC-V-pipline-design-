#!/usr/bin/env python3
"""Minimal two-pass RV32I assembler for the EGO1 RISC-V SoC project.

Emits one 32-bit instruction word per line as 8 lowercase hex digits, matching
the $readmemh INIT_FILE format used by soc_bram*.v. Instruction memory starts at
address 0. Supports the RV32I subset the CPU implements, ABI register names, and
a handful of pseudo-instructions.

Usage:  python asm.py input.S output.hex
"""
import sys
import re

# ---- registers -------------------------------------------------------------
ABI = {
    'zero': 0, 'ra': 1, 'sp': 2, 'gp': 3, 'tp': 4,
    't0': 5, 't1': 6, 't2': 7, 's0': 8, 'fp': 8, 's1': 9,
    'a0': 10, 'a1': 11, 'a2': 12, 'a3': 13, 'a4': 14, 'a5': 15,
    'a6': 16, 'a7': 17, 's2': 18, 's3': 19, 's4': 20, 's5': 21,
    's6': 22, 's7': 23, 's8': 24, 's9': 25, 's10': 26, 's11': 27,
    't3': 28, 't4': 29, 't5': 30, 't6': 31,
}


def reg(tok):
    t = tok.strip().lower()
    if t in ABI:
        return ABI[t]
    if re.fullmatch(r'x\d+', t):
        n = int(t[1:])
        if 0 <= n <= 31:
            return n
    raise ValueError(f"bad register '{tok}'")


def imm(tok, lo, hi):
    """Parse an integer immediate (dec/hex, signed) and range-check."""
    t = tok.strip()
    v = int(t, 16) if t.lower().startswith(('0x', '-0x')) else int(t, 0) if t.lower().startswith('0x') else int(t, 0)
    if not (lo <= v <= hi):
        raise ValueError(f"immediate {v} out of range [{lo},{hi}]")
    return v


def parse_int(t):
    t = t.strip()
    neg = t.startswith('-')
    if neg:
        t = t[1:]
    v = int(t, 16) if t.lower().startswith('0x') else int(t, 0)
    return -v if neg else v


MEM_RE = re.compile(r'^\s*(-?(?:0x)?[0-9a-fA-F]+)\s*\(\s*([a-zA-Z0-9]+)\s*\)\s*$')


def mem(tok):
    m = MEM_RE.match(tok)
    if not m:
        raise ValueError(f"bad memory operand '{tok}'")
    return parse_int(m.group(1)), reg(m.group(2))


# ---- encoders --------------------------------------------------------------
def R(f7, f3, op):
    return lambda a: (f7 << 25) | (reg(a[2]) << 20) | (reg(a[1]) << 15) | (f3 << 12) | (reg(a[0]) << 7) | op


def I(f3, op):
    def enc(a):
        v = parse_int(a[2]) & 0xFFF
        return (v << 20) | (reg(a[1]) << 15) | (f3 << 12) | (reg(a[0]) << 7) | op
    return enc


def SHIFT(f7, f3):
    def enc(a):
        sh = parse_int(a[2]) & 0x1F
        return (f7 << 25) | (sh << 20) | (reg(a[1]) << 15) | (f3 << 12) | (reg(a[0]) << 7) | 0x13
    return enc


def LOAD(f3):
    def enc(a):
        off, rs1 = mem(a[1])
        return ((off & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (reg(a[0]) << 7) | 0x03
    return enc


def STORE(f3):
    def enc(a):
        off, rs1 = mem(a[1])
        rs2 = reg(a[0])
        off &= 0xFFF
        return (((off >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((off & 0x1F) << 7) | 0x23
    return enc


def U(op):
    return lambda a: ((parse_int(a[1]) & 0xFFFFF) << 12) | (reg(a[0]) << 7) | op


# Branch/jump encoders need the label table + current PC; handled specially.
BRANCH_F3 = {'beq': 0, 'bne': 1, 'blt': 4, 'bge': 5, 'bltu': 6, 'bgeu': 7}

RTYPE = {
    'add': R(0x00, 0, 0x33), 'sub': R(0x20, 0, 0x33), 'sll': R(0x00, 1, 0x33),
    'slt': R(0x00, 2, 0x33), 'sltu': R(0x00, 3, 0x33), 'xor': R(0x00, 4, 0x33),
    'srl': R(0x00, 5, 0x33), 'sra': R(0x20, 5, 0x33), 'or': R(0x00, 6, 0x33),
    'and': R(0x00, 7, 0x33),
}
ITYPE = {
    'addi': I(0, 0x13), 'slti': I(2, 0x13), 'sltiu': I(3, 0x13),
    'xori': I(4, 0x13), 'ori': I(6, 0x13), 'andi': I(7, 0x13),
    'jalr': I(0, 0x67),
}
SHIFTS = {'slli': SHIFT(0x00, 1), 'srli': SHIFT(0x00, 5), 'srai': SHIFT(0x20, 5)}
LOADS = {'lb': LOAD(0), 'lh': LOAD(1), 'lw': LOAD(2), 'lbu': LOAD(4), 'lhu': LOAD(5)}
STORES = {'sb': STORE(0), 'sh': STORE(1), 'sw': STORE(2)}
UTYPE = {'lui': U(0x37), 'auipc': U(0x17)}


def split_ops(s):
    return [x.strip() for x in s.split(',')] if s.strip() else []


def li_words(rd, val):
    """Expand `li rd, val` to 1 or 2 instructions (lui/addi with carry fix)."""
    val &= 0xFFFFFFFF
    lo = val & 0xFFF
    if lo & 0x800:                       # low 12 bits sign-extend negative
        hi = (val + 0x1000) & 0xFFFFFFFF  # compensate with +1 in upper
    else:
        hi = val
    hi20 = (hi >> 12) & 0xFFFFF
    lo12 = lo if not (lo & 0x800) else lo - 0x1000
    out = []
    if hi20 != 0:
        out.append(('lui', [f'x{rd}', str(hi20)]))
        if lo12 != 0:
            out.append(('addi', [f'x{rd}', f'x{rd}', str(lo12)]))
    else:
        out.append(('addi', [f'x{rd}', 'x0', str(lo12)]))
    return out


def expand_pseudo(mn, ops):
    """Return a list of (mnemonic, ops) real instructions for a pseudo-op."""
    if mn == 'li':
        return li_words(reg(ops[0]), parse_int(ops[1]))
    if mn == 'mv':
        return [('addi', [ops[0], ops[1], '0'])]
    if mn == 'nop':
        return [('addi', ['x0', 'x0', '0'])]
    if mn == 'j':
        return [('jal', ['x0', ops[0]])]
    if mn == 'jr':
        return [('jalr', ['x0', ops[0], '0'])]
    if mn == 'ret':
        return [('jalr', ['x0', 'ra', '0'])]
    if mn == 'beqz':
        return [('beq', [ops[0], 'x0', ops[1]])]
    if mn == 'bnez':
        return [('bne', [ops[0], 'x0', ops[1]])]
    if mn == 'not':
        return [('xori', [ops[0], ops[1], '-1'])]
    if mn == 'neg':
        return [('sub', [ops[0], 'x0', ops[1]])]
    return [(mn, ops)]


def assemble(text):
    # Tokenize into (mnemonic, ops, source_line) after stripping comments/labels.
    raw = []
    for lineno, line in enumerate(text.splitlines(), 1):
        line = re.split(r'//|#|;', line, 1)[0].strip()
        while ':' in line:                       # labels (possibly inline)
            label, _, rest = line.partition(':')
            raw.append(('__label__', label.strip(), lineno))
            line = rest.strip()
        if not line:
            continue
        parts = line.split(None, 1)
        mn = parts[0].lower()
        ops = split_ops(parts[1]) if len(parts) > 1 else []
        raw.append((mn, ops, lineno))

    # Pass 1: assign addresses, expand pseudo-ops, collect labels.
    labels = {}
    prog = []   # list of (mnemonic, ops, addr, lineno)
    addr = 0
    for item in raw:
        if item[0] == '__label__':
            name = item[1]
            if name in labels:
                raise ValueError(f"duplicate label '{name}'")
            labels[name] = addr
            continue
        mn, ops, lineno = item
        for rmn, rops in expand_pseudo(mn, ops):
            prog.append((rmn, rops, addr, lineno))
            addr += 4

    # Pass 2: encode.
    words = []
    for mn, ops, addr, lineno in prog:
        try:
            words.append(encode(mn, ops, addr, labels) & 0xFFFFFFFF)
        except Exception as e:
            raise SystemExit(f"asm error (line {lineno}): {mn} {','.join(ops)}\n  {e}")
    return words


def encode(mn, ops, addr, labels):
    if mn in RTYPE:
        return RTYPE[mn](ops)
    if mn in ITYPE:
        return ITYPE[mn](ops)
    if mn in SHIFTS:
        return SHIFTS[mn](ops)
    if mn in LOADS:
        return LOADS[mn](ops)
    if mn in STORES:
        return STORES[mn](ops)
    if mn in UTYPE:
        return UTYPE[mn](ops)
    if mn in BRANCH_F3:
        rs1, rs2 = reg(ops[0]), reg(ops[1])
        target = labels[ops[2]] if ops[2] in labels else parse_int(ops[2]) + addr
        off = target - addr
        if off & 1 or not (-4096 <= off <= 4094):
            raise ValueError(f"branch offset {off} invalid")
        o = off & 0x1FFF
        b12 = (o >> 12) & 1
        b11 = (o >> 11) & 1
        b10_5 = (o >> 5) & 0x3F
        b4_1 = (o >> 1) & 0xF
        f3 = BRANCH_F3[mn]
        return (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | \
               (f3 << 12) | (b4_1 << 8) | (b11 << 7) | 0x63
    if mn == 'jal':
        rd = reg(ops[0])
        target = labels[ops[1]] if ops[1] in labels else parse_int(ops[1]) + addr
        off = target - addr
        if off & 1 or not (-(1 << 20) <= off < (1 << 20)):
            raise ValueError(f"jal offset {off} invalid")
        o = off & 0x1FFFFF
        b20 = (o >> 20) & 1
        b10_1 = (o >> 1) & 0x3FF
        b11 = (o >> 11) & 1
        b19_12 = (o >> 12) & 0xFF
        return (b20 << 31) | (b19_12 << 12) | (b11 << 20) | (b10_1 << 21) | (rd << 7) | 0x6F
    raise ValueError(f"unknown instruction '{mn}'")


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: python asm.py input.S output.hex")
    with open(sys.argv[1]) as f:
        words = assemble(f.read())
    with open(sys.argv[2], 'w', newline='\n') as f:
        for w in words:
            f.write(f"{w:08x}\n")
    print(f"{sys.argv[1]} -> {sys.argv[2]}: {len(words)} words")


if __name__ == '__main__':
    main()
