# monitor.S — interactive serial monitor for PC-side verification of the SoC.
# Runs on both cores (multi-cycle @100 MHz, pipeline @50 MHz); the UART divisor
# is set in hardware per core, so the firmware is identical.
#
# On boot prints "RV32I OK\n" then loops reading single-letter commands and
# their hex arguments (see UART_VERIFICATION_PLAN.md). Command replies are
# plain; asynchronous ISR output is prefixed with '!' so the PC can tell them
# apart.
#
# Commands (each terminated by the letter; args are fixed 8-hex-digit fields):
#   P            -> "PONG\n"                 ping / liveness
#   R<8hex>      -> "=<8hex>\n"              read word at addr
#   W<8hex><8hex>-> "OK\n"                   write data to addr
#   C<1hex>      -> "=<8hex>\n"              read perf counter n (0..8)
#   T<8hex>      -> "OK\n"                   arm timer IRQ, deadline = now+N
#   E            -> ecall (prints "!TRAP c=.. e=..\n" from handler)
#   Z            -> illegal instr (same trap print)
#   Ie / Id      -> enable / disable UART RX interrupt
# Timer ISR prints "!TICK\n"; RX ISR prints "!RX<2hex>\n" (byte, uppercased).
#
# Memory map (see rv32_soc*.v):
#   0x10000030 UART_TX     0x10000034 UART_RX    0x10000038 UART_STATUS
#   0x1000003C UART_CTRL   0x10000040 MTIME      0x10000044 MTIMECMP
#   0x10000048 TIMER_CTRL  0x10000050 IRQ_STATUS 0x10000010.. perf counters

    .org 0x0
reset:
    li   sp, 0x7FF0            # stack top (BRAM is 32 KiB)
    li   t0, trap_entry
    csrw mtvec, t0
    li   t0, 0x1200
    csrw mscratch, t0         # ISR save-area base

    # banner
    li   a0, banner
    jal  ra, puts

    # enable global interrupts (individual sources enabled on demand)
    li   t0, 0x8
    csrs mstatus, t0

main:
    jal  ra, getc             # a0 = command char (blocking poll)
    li   t1, 0x50             # 'P'
    beq  a0, t1, cmd_ping
    li   t1, 0x52             # 'R'
    beq  a0, t1, cmd_read
    li   t1, 0x57             # 'W'
    beq  a0, t1, cmd_write
    li   t1, 0x43             # 'C'
    beq  a0, t1, cmd_counter
    li   t1, 0x54             # 'T'
    beq  a0, t1, cmd_timer
    li   t1, 0x45             # 'E'
    beq  a0, t1, cmd_ecall
    li   t1, 0x5A             # 'Z'
    beq  a0, t1, cmd_illegal
    li   t1, 0x49             # 'I'
    beq  a0, t1, cmd_irqctl
    # ignore CR/LF and anything else
    j    main

cmd_ping:
    li   a0, s_pong
    jal  ra, puts
    j    main

cmd_read:
    jal  ra, gethex32         # a0 = addr
    lw   a0, 0(a0)            # a0 = *addr
    jal  ra, put_eq_hex
    j    main

cmd_write:
    jal  ra, gethex32         # a0 = addr
    mv   s3, a0
    jal  ra, gethex32         # a0 = data
    sw   a0, 0(s3)
    li   a0, s_ok
    jal  ra, puts
    j    main

cmd_counter:
    jal  ra, gethex1          # a0 = n (0..15)
    slli a0, a0, 2            # word offset
    li   t0, 0x10000010
    add  a0, a0, t0
    lw   a0, 0(a0)
    jal  ra, put_eq_hex
    j    main

cmd_timer:
    jal  ra, gethex32         # a0 = N ticks
    li   t0, 0x10000040       # MTIME
    lw   t1, 0(t0)
    add  t1, t1, a0           # deadline = now + N
    li   t0, 0x10000044
    sw   t1, 0(t0)            # MTIMECMP
    li   t0, 0x10000048
    li   t1, 1
    sw   t1, 0(t0)            # enable timer
    li   t0, 0x80
    csrs mie, t0              # mie.MTIE
    li   a0, s_ok
    jal  ra, puts
    j    main

cmd_ecall:
    ecall
    j    main

cmd_illegal:
    .word 0x00000000
    j    main

cmd_irqctl:
    jal  ra, getc             # 'e' or 'd'
    li   t1, 0x65             # 'e'
    beq  a0, t1, irq_en
    # disable
    li   t0, 0x1
    li   t1, 0x1000003C
    sw   x0, 0(t1)            # UART_CTRL = 0 (rx_ie off)
    li   t0, 0x800
    csrc mie, t0              # mie.MEIE off
    li   a0, s_ok
    jal  ra, puts
    j    main
irq_en:
    li   t1, 0x1000003C
    li   t0, 1
    sw   t0, 0(t1)            # UART_CTRL rx_ie = 1
    li   t0, 0x800
    csrs mie, t0             # mie.MEIE on
    li   a0, s_ok
    jal  ra, puts
    j    main

    # PLACEHOLDER_HELPERS
# ---------------- UART primitives ----------------
# putc(a0=byte): wait for TX idle, then send.
putc:
    li   t0, 0x10000030       # UART_TX (bit0=tx_busy on read)
putc_wait:
    lw   t1, 0(t0)
    andi t1, t1, 1
    bnez t1, putc_wait
    sw   a0, 0(t0)
    ret

# getc() -> a0: block until RX has a byte, return it (clears rx_valid).
getc:
    li   t0, 0x10000038       # UART_STATUS bit0 = rx_valid
getc_wait:
    lw   t1, 0(t0)
    andi t1, t1, 1
    beqz t1, getc_wait
    li   t0, 0x10000034       # UART_RX (read clears rx_valid)
    lw   a0, 0(t0)
    andi a0, a0, 0xff
    ret

# puts(a0=ptr): print string stored one word per character (0 word = end).
# The CPU implements word loads only (no lbu), so strings are word-per-char.
puts:
    addi sp, sp, -12
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    sw   s1, 8(sp)
    mv   s0, a0
puts_loop:
    lw   s1, 0(s0)
    beqz s1, puts_done
    mv   a0, s1
    jal  ra, putc
    addi s0, s0, 4
    j    puts_loop
puts_done:
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    addi sp, sp, 12
    ret

# put_hex_nib(a0=low nibble): print one hex digit.
put_hex_nib:
    andi a0, a0, 0xf
    li   t0, 10
    blt  a0, t0, phn_dec
    addi a0, a0, 0x37         # 'A'-10
    j    putc
phn_dec:
    addi a0, a0, 0x30         # '0'
    j    putc

# put_hex8(a0): print 8 hex digits (MSB first). Uses stack for ra.
put_hex8:
    addi sp, sp, -8
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    mv   s0, a0
    li   s1, 28
ph8_loop:
    srl  a0, s0, s1
    jal  ra, put_hex_nib
    addi s1, s1, -4
    bgez s1, ph8_loop
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    addi sp, sp, 8
    ret

# put_hex2(a0): print 2 hex digits (low byte).
put_hex2:
    addi sp, sp, -8
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    mv   s0, a0
    srli a0, s0, 4
    jal  ra, put_hex_nib
    mv   a0, s0
    jal  ra, put_hex_nib
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    addi sp, sp, 8
    ret

# put_eq_hex(a0): print '=' then 8 hex digits then newline.
put_eq_hex:
    addi sp, sp, -8
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    mv   s0, a0
    li   a0, 0x3d             # '='
    jal  ra, putc
    mv   a0, s0
    jal  ra, put_hex8
    li   a0, 0x0a             # '\n'
    jal  ra, putc
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    addi sp, sp, 8
    ret

# nib_of(a0=ascii) -> a0 = 0..15 (assumes valid hex, upper or lower).
nib_of:
    li   t0, 0x3a             # ':'
    blt  a0, t0, no_dec
    ori  a0, a0, 0x20         # to lower
    addi a0, a0, -0x57        # 'a'-10
    ret
no_dec:
    addi a0, a0, -0x30
    ret

# gethex1() -> a0: read 1 hex char, return its value.
gethex1:
    addi sp, sp, -4
    sw   ra, 0(sp)
    jal  ra, getc
    jal  ra, nib_of
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

# gethex32() -> a0: read 8 hex chars, return the assembled word.
gethex32:
    addi sp, sp, -12
    sw   ra, 0(sp)
    sw   s0, 4(sp)
    sw   s1, 8(sp)
    li   s0, 0                # accumulator
    li   s1, 8                # count
gh_loop:
    jal  ra, getc
    jal  ra, nib_of
    slli s0, s0, 4
    or   s0, s0, a0
    addi s1, s1, -1
    bnez s1, gh_loop
    mv   a0, s0
    lw   ra, 0(sp)
    lw   s0, 4(sp)
    lw   s1, 8(sp)
    addi sp, sp, 12
    ret

    # PLACEHOLDER_HANDLER
# ==================== trap handler ====================
# mscratch holds the save-area base (0x1200). We save every register the
# handler body and the UART helpers clobber (t0-t2, a0-a2, ra); the helpers
# save/restore their own s0/s1 on the stack. The interrupted program's context
# is therefore fully preserved -> precise resume.
    .org 0x800
trap_entry:
    csrrw t0, mscratch, t0    # t0 = save base ; mscratch = caller's t0
    sw   ra, 0(t0)
    sw   t1, 4(t0)
    sw   t2, 8(t0)
    sw   a0, 12(t0)
    sw   a1, 16(t0)
    sw   a2, 20(t0)
    # stash caller's t0 (currently in mscratch) into the save area too
    csrr t1, mscratch
    sw   t1, 24(t0)

    csrr t1, mcause
    bltz t1, t_async          # bit31 set => asynchronous interrupt

    # ---- synchronous exception: print "!TRAP c=<cause> e=<epc>\n" ----
    li   a0, s_trap
    jal  ra, puts
    csrr a0, mcause
    jal  ra, put_hex8
    li   a0, 0x20             # ' '
    jal  ra, putc
    li   a0, 0x65             # 'e'
    jal  ra, putc
    li   a0, 0x3d             # '='
    jal  ra, putc
    csrr a0, mepc
    jal  ra, put_hex8
    li   a0, 0x0a
    jal  ra, putc
    # skip the faulting instruction so we can continue
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    j    t_restore

t_async:
    # timer? (mcause low bits == 7)
    andi t2, t1, 0x1f
    li   a1, 7
    beq  t2, a1, t_timer
    # else external (UART RX)
    j    t_ext

t_timer:
    # silence timer (clear MTIE) and announce
    li   t2, 0x80
    csrc mie, t2
    li   a0, s_tick
    jal  ra, puts
    j    t_restore

t_ext:
    # read the received byte, uppercase a-z, echo "!RX<hex>\n"
    li   t2, 0x10000034       # UART_RX
    lw   a0, 0(t2)
    andi a0, a0, 0xff
    mv   a1, a0
    li   a0, s_rx
    jal  ra, puts
    mv   a0, a1
    # uppercase if 'a'..'z'
    li   t2, 0x61
    blt  a0, t2, t_noup
    li   t2, 0x7a
    blt  t2, a0, t_noup
    addi a0, a0, -0x20
t_noup:
    jal  ra, put_hex2
    li   a0, 0x0a
    jal  ra, putc

t_restore:
    # t0 still holds the save base (nothing in the handler body clobbers t0).
    # Restore mscratch to the save base for the next trap, then reload regs.
    li   t1, 0x1200
    csrw mscratch, t1
    lw   ra, 0(t0)
    lw   t1, 4(t0)
    lw   t2, 8(t0)
    lw   a0, 12(t0)
    lw   a1, 16(t0)
    lw   a2, 20(t0)
    lw   t0, 24(t0)           # restore caller's t0 last (overwrites save base)
    mret

# ---------------- strings (one 32-bit word per character, 0 = terminator) ----
    .org 0xB00
banner:
    .word 0x52,0x56,0x33,0x32,0x49,0x20,0x4F,0x4B,0x0A,0    # "RV32I OK\n"
s_pong:
    .word 0x50,0x4F,0x4E,0x47,0x0A,0                        # "PONG\n"
s_ok:
    .word 0x4F,0x4B,0x0A,0                                  # "OK\n"
s_trap:
    .word 0x21,0x54,0x52,0x41,0x50,0x20,0x63,0x3D,0         # "!TRAP c="
s_tick:
    .word 0x21,0x54,0x49,0x43,0x4B,0x0A,0                   # "!TICK\n"
s_rx:
    .word 0x21,0x52,0x58,0                                  # "!RX"



