// RV32I subset self-test for the multi-cycle CPU.
// PASS writes 0xCAFE to LED/display, FAIL writes 0xDEAD.

lui  x1, 0x10000      // GPIO base: 0x10000000

addi x2, x0, 5
addi x3, x0, 7
add  x4, x2, x3
addi x5, x0, 12
bne  x4, x5, fail

sub  x4, x3, x2
addi x5, x0, 2
bne  x4, x5, fail

addi x2, x0, 15
addi x3, x0, 51
and  x4, x2, x3
addi x5, x0, 3
bne  x4, x5, fail

or   x4, x2, x3
addi x5, x0, 63
bne  x4, x5, fail

xor  x4, x2, x3
addi x5, x0, 60
bne  x4, x5, fail

slli x4, x2, 2
addi x5, x0, 60
bne  x4, x5, fail

srli x4, x3, 4
addi x5, x0, 3
bne  x4, x5, fail

addi x2, x0, -8
srai x4, x2, 1
addi x5, x0, -4
bne  x4, x5, fail

addi x2, x0, -1
addi x3, x0, 1
slt  x4, x2, x3
addi x5, x0, 1
bne  x4, x5, fail

sltu x4, x2, x3
addi x5, x0, 0
bne  x4, x5, fail

lui  x6, 0
addi x6, x6, 256
addi x7, x0, 123
sw   x7, 0(x6)
lw   x8, 0(x6)
bne  x8, x7, fail

lw   x9, 4(x1)
sw   x9, 0(x1)
sw   x9, 8(x1)

addi x10, x0, 0
beq  x10, x0, branch_ok
jal  x0, fail

branch_ok:
addi x11, x0, 42
bne  x11, x0, pass
jal  x0, fail

pass:
lui  x12, 0x0000d
addi x12, x12, -1282
sw   x12, 0(x1)
sw   x12, 8(x1)
pass_loop:
jal  x0, pass_loop

fail:
lui  x12, 0x0000e
addi x12, x12, -339
sw   x12, 0(x1)
sw   x12, 8(x1)
fail_loop:
jal  x0, fail_loop
