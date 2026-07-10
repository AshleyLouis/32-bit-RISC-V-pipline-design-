// ============================================================================
// EGO1 RISC-V SoC — interactive classroom demo firmware
//
// One program that shows off the whole project. It runs on BOTH cores
// unchanged (multi-cycle top_ego1 and pipelined top_ego1_pipeline) because it
// only uses the RV32I subset both implement and the common memory map.
//
// At boot it runs a fixed benchmark (sum 1..100) while sampling the hardware
// cycle/instret counters, then derives CPI*100, and converts the metrics to
// packed BCD so the seven-segment shows DECIMAL digits.
//
// The main loop reads dip_sw[2:0] to pick what to show on the LEDs + 7-seg:
//   dip_sw = 0 : CAFE            (ISA correctness magic word, hex)
//            1 : live {dip_sw,sw}(flip switches, watch LEDs/7-seg follow)
//            2 : 5050            (sum 1..100 — proves it runs real programs)
//            3 : <cycles>        (benchmark cycle count, decimal)
//            4 : <instret>       (benchmark instructions retired, decimal)
//            5 : <CPI*100>       (e.g. 528 = 5.28 multi-cycle, 119 = 1.19 pipe)
//         6,7 : FFFF            (unused-mode placeholder)
//
// Memory map (both cores):
//   0x1000_0000 LED (w)   0x1000_0004 {dip_sw,sw} (r)   0x1000_0008 7-seg (w)
//   0x1000_0010 cycles(r) 0x1000_0014 instret (r)
//
// Register plan (flat code, no stack): s0=base, s2=cycles, s3=instret,
// s4=result(5050), s5=CPI*100 — s2..s5 hold packed-BCD forms after boot.
// ============================================================================

    lui  s0, 0x10000          // s0 = peripheral base 0x1000_0000

    // ---- measured benchmark: sum 1..100 --------------------------------
    lw   t0, 16(s0)           // cycle counter  @ start
    lw   t1, 20(s0)           // instret        @ start
    li   a0, 0                // sum
    li   a1, 1                // i
    li   a2, 101              // limit (loop while i != 101)
bench:
    add  a0, a0, a1
    addi a1, a1, 1
    bne  a1, a2, bench
    lw   t2, 16(s0)           // cycle counter  @ end
    lw   t3, 20(s0)           // instret        @ end
    mv   s4, a0               // s4 = 5050 (raw)
    sub  s2, t2, t0           // s2 = cycles  (raw)
    sub  s3, t3, t1           // s3 = instret (raw)

    // ---- CPI*100 = cycles*100 / instret --------------------------------
    slli t0, s2, 6            // cycles*64
    slli t1, s2, 5            // cycles*32
    add  t0, t0, t1           // cycles*96
    slli t1, s2, 2            // cycles*4
    add  t0, t0, t1           // t0 = cycles*100
    li   t2, 0                // quotient
cpi_div:
    bltu t0, s3, cpi_done     // while (t0 >= instret)
    sub  t0, t0, s3
    addi t2, t2, 1
    j    cpi_div
cpi_done:
    mv   s5, t2               // s5 = CPI*100 (raw)

    // ---- convert the four decimal metrics to packed BCD ----------------
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

    // ---- main display loop: dip_sw[2:0] selects the view ---------------
main:
    lw   t0, 4(s0)            // t0 = {dip_sw, sw}
    srli t1, t0, 8
    andi t1, t1, 7            // t1 = mode = dip_sw[2:0]
    li   t2, 0xffff           // default (modes 6,7)

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
    j    show
m0:
    li   t2, 0xcafe           // correctness magic word
    j    show
m1:
    mv   t2, t0               // live switch mirror
    j    show
m2:
    mv   t2, s4               // 5050
    j    show
m3:
    mv   t2, s2               // cycles (BCD)
    j    show
m4:
    mv   t2, s3               // instret (BCD)
    j    show
m5:
    mv   t2, s5               // CPI*100 (BCD)
    j    show
show:
    sw   t2, 0(s0)            // -> LEDs
    sw   t2, 8(s0)            // -> seven-segment
    j    main

// ---- to_bcd: a0 = unsigned value -> a0 = packed BCD (<= 8 digits) -------
// Repeated /10 (subtraction), building nibbles from least-significant digit.
// Clobbers t0..t4, a0; preserves all s registers and ra.
to_bcd:
    li   t0, 0                // packed result
    li   t1, 0                // nibble shift (bits)
tb_loop:
    li   t2, 0                // quotient = value / 10
tb_div:
    sltiu t4, a0, 10          // remainder settles when value < 10
    bne   t4, x0, tb_div_done
    addi  a0, a0, -10
    addi  t2, t2, 1
    j     tb_div
tb_div_done:
    sll   t3, a0, t1          // digit (a0 = remainder) into position
    or    t0, t0, t3
    addi  t1, t1, 4
    mv    a0, t2              // value = quotient
    bne   a0, x0, tb_loop
    mv    a0, t0
    ret
