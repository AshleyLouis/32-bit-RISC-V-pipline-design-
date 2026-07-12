# ============================================================================
# demo_uart.S — MERGED firmware: the original dip_sw-selected demo views
# (modes 0..5, unchanged) PLUS a new mode 6 that enters the interactive serial
# monitor for PC-side verification (ping / peek-poke / perf / exceptions /
# UART-RX + timer interrupts). See UART_VERIFICATION_PLAN.md and
# INTERRUPT_UART_README.md.
#
# Runs on both cores (multi-cycle @100 MHz, pipeline @50 MHz); the UART divisor
# is set in hardware per core, so this one binary is identical for both.
#
# dip_sw[2:0] view select (as before):
#   0 : CAFE            (ISA correctness magic word, hex)
#   1 : live {dip_sw,sw}(flip switches, watch LEDs/7-seg follow)
#   2 : 5050            (sum 1..100 — proves it runs real programs)
#   3 : <cycles>        (benchmark cycle count, decimal)
#   4 : <instret>       (benchmark instructions retired, decimal)
#   5 : <CPI*100>       (e.g. 528 = 5.28 multi-cycle, 119 = 1.19 pipe)
#   6 : UART MONITOR    (NEW — enter serial monitor; run tools/tests.py on PC)
#   7 : FFFF            (unused-mode placeholder)
#
# NOTE: mode 6 enters the monitor and STAYS there (blocking on the serial link),
# per the chosen behaviour. Flip back to 0..5 BEFORE selecting 6 if you want the
# display views; to leave the monitor, reset the board (BTN) and don't select 6.
#
# Memory map (both cores):
#   0x1000_0000 LED (w)   0x1000_0004 {dip_sw,sw}(r)  0x1000_0008 7-seg (w)
#   0x1000_0010 cycles(r) 0x1000_0014 instret (r)
#   0x1000_0030 UART_TX   0x1000_0034 UART_RX   0x1000_0038 UART_STATUS
#   0x1000_003C UART_CTRL 0x1000_0040 MTIME     0x1000_0044 MTIMECMP
#   0x1000_0048 TIMER_CTRL 0x1000_0050 IRQ_STATUS
#
# Register plan for the demo part (as before): s0=base, s2=cycles, s3=instret,
# s4=result(5050), s5=CPI*100 (s2..s5 are packed-BCD after boot). The monitor
# part uses a stack (set up at reset) and its own conventions.
# ============================================================================

    .org 0x0
reset:
    li   sp, 0x7FF0           # stack top (BRAM is 32 KiB) — needed by to_bcd/monitor
    li   t0, trap_entry
    csrw mtvec, t0            # install trap vector up front
    li   t0, 0x1200
    csrw mscratch, t0         # ISR save-area base

    lui  s0, 0x10000          # s0 = peripheral base 0x1000_0000

    # ---- measured benchmark: sum 1..100 --------------------------------
    lw   t0, 16(s0)           # cycle counter  @ start
    lw   t1, 20(s0)           # instret        @ start
    li   a0, 0                # sum
    li   a1, 1                # i
    li   a2, 101              # limit (loop while i != 101)
bench:
    add  a0, a0, a1
    addi a1, a1, 1
    bne  a1, a2, bench
    lw   t2, 16(s0)           # cycle counter  @ end
    lw   t3, 20(s0)           # instret        @ end
    mv   s4, a0               # s4 = 5050 (raw)
    sub  s2, t2, t0           # s2 = cycles  (raw)
    sub  s3, t3, t1           # s3 = instret (raw)

    # ---- CPI*100 = cycles*100 / instret --------------------------------
    slli t0, s2, 6            # cycles*64
    slli t1, s2, 5            # cycles*32
    add  t0, t0, t1           # cycles*96
    slli t1, s2, 2            # cycles*4
    add  t0, t0, t1           # t0 = cycles*100
    li   t2, 0                # quotient
cpi_div:
    bltu t0, s3, cpi_done     # while (t0 >= instret)
    sub  t0, t0, s3
    addi t2, t2, 1
    j    cpi_div
cpi_done:
    mv   s5, t2               # s5 = CPI*100 (raw)

    # ---- convert the four decimal metrics to packed BCD ----------------
    mv   a0, s4
    jal  ra, to_bcd
    mv   s4, a0
    mv   a0, s2
    jal  ra, to_bcd
    mv   s2, a0
    mv   a0, s3
    jal  ra, to_bcd
    mv   s3, a0
    mv   a0, s5
    jal  ra, to_bcd
    mv   s5, a0

    # ---- main display loop: dip_sw[2:0] selects the view ---------------
disp:
    lw   t0, 4(s0)            # t0 = {dip_sw, sw}
    srli t1, t0, 8
    andi t1, t1, 7            # t1 = mode = dip_sw[2:0]
    li   t2, 0xffff           # default (mode 7)

    beq  t1, x0, m0
    li   t3, 1
    beq  t1, t3, m1
    li   t3, 2
    beq  t1, t3, m2
    li   t3, 3
    beq  t1, t3, m3
    li   t3, 4
    beq  t1, t3, m4
    li   t3, 5
    beq  t1, t3, m5
    li   t3, 6
    beq  t1, t3, enter_monitor   # NEW: mode 6 -> serial monitor
    j    show
m0:
    li   t2, 0xcafe           # correctness magic word
    j    show
m1:
    mv   t2, t0               # live switch mirror
    j    show
m2:
    mv   t2, s4               # 5050
    j    show
m3:
    mv   t2, s2               # cycles (BCD)
    j    show
m4:
    mv   t2, s3               # instret (BCD)
    j    show
m5:
    mv   t2, s5               # CPI*100 (BCD)
    j    show
show:
    sw   t2, 0(s0)            # -> LEDs
    sw   t2, 8(s0)            # -> seven-segment
    j    disp

# ---- to_bcd: a0 = unsigned value -> a0 = packed BCD (<= 8 digits) -------
# Repeated /10 (subtraction), building nibbles from least-significant digit.
# Clobbers t0..t4, a0; preserves all s registers and ra.
to_bcd:
    li   t0, 0                # packed result
    li   t1, 0                # nibble shift (bits)
tb_loop:
    li   t2, 0                # quotient = value / 10
tb_div:
    sltiu t4, a0, 10          # remainder settles when value < 10
    bne   t4, x0, tb_div_done
    addi  a0, a0, -10
    addi  t2, t2, 1
    j     tb_div
tb_div_done:
    sll   t3, a0, t1          # digit (a0 = remainder) into position
    or    t0, t0, t3
    addi  t1, t1, 4
    mv    a0, t2              # value = quotient
    bne   a0, x0, tb_loop
    mv    a0, t0
    ret

# ============================================================================
# ===============  UART MONITOR (entered from display mode 6)  ================
# Below here is the serial monitor: main command loop + helpers + trap handler
# + strings, kept functionally identical to programs/monitor.S. Light the LEDs
# with a marker (0x0060 = "..UART..") so it is obvious on the board that mode 6
# handed off to the monitor.
# ============================================================================
enter_monitor:
    li   t2, 0x0060
    sw   t2, 0(s0)            # LED marker: entered monitor mode
    # banner over UART so the PC knows the board is alive in monitor mode
    li   a0, banner
    jal  ra, puts
    # enable global interrupts (individual sources enabled on demand)
    li   t0, 0x8
    csrs mstatus, t0

mon_main:
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
    j    mon_main             # ignore CR/LF and anything else

cmd_ping:
    li   a0, s_pong
    jal  ra, puts
    j    mon_main

cmd_read:
    jal  ra, gethex32         # a0 = addr
    lw   a0, 0(a0)            # a0 = *addr
    jal  ra, put_eq_hex
    j    mon_main

cmd_write:
    jal  ra, gethex32         # a0 = addr
    mv   s3, a0
    jal  ra, gethex32         # a0 = data
    sw   a0, 0(s3)
    li   a0, s_ok
    jal  ra, puts
    j    mon_main

cmd_counter:
    jal  ra, gethex1          # a0 = n (0..15)
    slli a0, a0, 2            # word offset
    li   t0, 0x10000010
    add  a0, a0, t0
    lw   a0, 0(a0)
    jal  ra, put_eq_hex
    j    mon_main

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
    j    mon_main

cmd_ecall:
    ecall
    j    mon_main

cmd_illegal:
    .word 0x00000000
    j    mon_main

cmd_irqctl:
    jal  ra, getc             # 'e' or 'd'
    li   t1, 0x65             # 'e'
    beq  a0, t1, irq_en
    # disable
    li   t1, 0x1000003C
    sw   x0, 0(t1)            # UART_CTRL = 0 (rx_ie off)
    li   t0, 0x800
    csrc mie, t0              # mie.MEIE off
    li   a0, s_ok
    jal  ra, puts
    j    mon_main
irq_en:
    li   t1, 0x1000003C
    li   t0, 1
    sw   t0, 0(t1)            # UART_CTRL rx_ie = 1
    li   t0, 0x800
    csrs mie, t0             # mie.MEIE on
    li   a0, s_ok
    jal  ra, puts
    j    mon_main

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
    csrr t1, mscratch
    sw   t1, 24(t0)           # stash caller's t0

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
    csrr t1, mepc
    addi t1, t1, 4            # skip the faulting instruction
    csrw mepc, t1
    j    t_restore

t_async:
    andi t2, t1, 0x1f         # timer? (low cause bits == 7)
    li   a1, 7
    beq  t2, a1, t_timer
    j    t_ext

t_timer:
    li   t2, 0x80
    csrc mie, t2             # silence timer (clear MTIE)
    li   a0, s_tick
    jal  ra, puts
    j    t_restore

t_ext:
    li   t2, 0x10000034       # UART_RX
    lw   a0, 0(t2)
    andi a0, a0, 0xff
    mv   a1, a0
    li   a0, s_rx
    jal  ra, puts
    mv   a0, a1
    li   t2, 0x61             # uppercase 'a'..'z'
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
    li   t1, 0x1200
    csrw mscratch, t1        # restore save base for the next trap
    lw   ra, 0(t0)
    lw   t1, 4(t0)
    lw   t2, 8(t0)
    lw   a0, 12(t0)
    lw   a1, 16(t0)
    lw   a2, 20(t0)
    lw   t0, 24(t0)          # restore caller's t0 last
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
