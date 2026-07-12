# irq_selftest.S — self-test for the M-mode CSR / exception / interrupt logic.
# Runs unchanged on both the multi-cycle and pipeline cores.
#
# Writes 0xCAFE to the LED port on full pass, 0xDEAD on any failure (same
# convention as isa_selftest). Covers:
#   A. CSR read/write round-trip (mscratch)
#   B. synchronous exception: ecall            (mcause = 11)
#   C. synchronous exception: illegal instr    (mcause = 2)
#   D. asynchronous machine timer interrupt     (mcause = 0x8000_0007)
#      + proves the main loop resumes precisely after mret.
#
# Register / memory conventions:
#   mscratch holds the ISR save-area base (0x1100) except during test A.
#   Data words:  0x1000 = timer-fired flag,  0x1010 = last exception cause,
#                0x1100.. = ISR temp save area (t1,t2,t3).
#   Handler uses only t0..t3; the timer spin loop uses s1,t4,t5 which the
#   handler must NOT touch (that is the precise-resume check).

    .org 0x0
_start:
    li   t0, 0x300
    csrw mtvec, t0            # trap vector (direct mode)

    # ---- Test A: CSR read/write round-trip ----
    li   t0, 0x1234
    csrw mscratch, t0
    csrr t1, mscratch
    li   t2, 0x1234
    bne  t1, t2, fail

    # dedicate mscratch to the ISR save-area base from here on
    li   t0, 0x1100
    csrw mscratch, t0

    # ---- Test B: ecall (synchronous exception, mcause = 11) ----
    ecall
    li   t0, 0x1010
    lw   t1, 0(t0)
    li   t2, 11
    bne  t1, t2, fail

    # ---- Test C: illegal instruction (mcause = 2) ----
    .word 0x00000000         # opcode 0 -> illegal
    li   t0, 0x1010
    lw   t1, 0(t0)
    li   t2, 2
    bne  t1, t2, fail

    # ---- Test D: machine timer interrupt ----
    li   t0, 0x80            # mie.MTIE (bit 7)
    csrw mie, t0
    li   t0, 0x10000040      # MTIME
    lw   t1, 0(t0)
    addi t1, t1, 100         # deadline = now + 100 ticks
    li   t0, 0x10000044      # MTIMECMP
    sw   t1, 0(t0)
    li   t0, 0x10000048      # TIMER_CTRL
    li   t1, 1
    sw   t1, 0(t0)           # enable timer
    li   t0, 0x8             # mstatus.MIE (bit 3)
    csrs mstatus, t0         # global interrupt enable

    li   s1, 0               # main-loop counter (handler must preserve)
    li   t4, 0x1000          # timer-fired flag address
    li   t5, 0xABCD          # canary the handler must not clobber
spin:
    addi s1, s1, 1
    lw   t0, 0(t4)
    beqz t0, spin
    # timer fired: main kept running and canary intact?
    beqz s1, fail
    li   t0, 0xABCD
    bne  t5, t0, fail

    # ---- all passed ----
    li   t0, 0x10000000
    li   t1, 0xCAFE
    sw   t1, 0(t0)
    li   t0, 0x10000008      # also seven-seg display
    sw   t1, 0(t0)
done:
    j    done

fail:
    li   t0, 0x10000000
    li   t1, 0xDEAD
    sw   t1, 0(t0)
    li   t0, 0x10000008
    sw   t1, 0(t0)
fail_done:
    j    fail_done

    # ==================== trap handler ====================
    .org 0x300
handler:
    csrrw t0, mscratch, t0   # t0 <- save base ; mscratch <- caller t0
    sw   t1, 4(t0)
    sw   t2, 8(t0)
    sw   t3, 12(t0)

    csrr t1, mcause
    blt  t1, x0, is_interrupt # bit31 set => negative => async interrupt

    # ---- synchronous exception: record cause, skip faulting instruction ----
    li   t2, 0x1010
    sw   t1, 0(t2)           # EXC_CAUSE = mcause
    csrr t2, mepc
    addi t2, t2, 4           # advance past the 4-byte faulting instruction
    csrw mepc, t2
    j    hdone

is_interrupt:
    # ---- machine timer: silence the source and flag it ----
    li   t2, 0x80
    csrc mie, t2             # clear mie.MTIE so it won't re-fire
    li   t2, 0x1000
    li   t3, 1
    sw   t3, 0(t2)           # FLAG_TIMER = 1

hdone:
    lw   t3, 12(t0)
    lw   t2, 8(t0)
    lw   t1, 4(t0)
    csrrw t0, mscratch, t0   # restore: t0 <- caller t0 ; mscratch <- save base
    mret
