#!/usr/bin/env python3
"""Automated verification suite for the RV32I SoC over UART.

Drives the monitor firmware (programs/monitor.S) through the checklist in
UART_VERIFICATION_PLAN.md and prints a PASS/FAIL summary. Every check has a
timeout so a runaway/hung CPU is reported rather than hanging the runner.

Requires pyserial:  pip install pyserial

Usage:  python tests.py --port COM5 [--baud 9600]

NOTE: the board's USB-UART shares the FTDI chip with JTAG. Close the Vivado
Hardware Manager (or disconnect the hw_target) before running, or the port
will be busy.
"""
import sys
import time
import argparse

from monitor import Monitor

# Memory map (see rv32_soc*.v)
BRAM_TEST = 0x00000400
LED       = 0x10000000
SWITCHES  = 0x10000004
PERF_CYCLE   = 0
PERF_INSTRET = 1


class Runner:
    def __init__(self, m):
        self.m = m
        self.results = []

    def check(self, name, fn):
        try:
            ok, detail = fn()
        except TimeoutError as e:
            ok, detail = False, "TIMEOUT: %s" % e
        except Exception as e:
            ok, detail = False, "ERROR: %s" % e
        self.results.append((name, ok, detail))
        mark = "PASS" if ok else "FAIL"
        print("[%s] %-32s %s" % (mark, name, detail))

    def summary(self):
        n = len(self.results)
        p = sum(1 for _, ok, _ in self.results if ok)
        print("\n%d/%d checks passed." % (p, n))
        return p == n


def build_tests(r):
    m = r.m

    # A. link + liveness
    r.check("ping", lambda: (m.ping() == "PONG", "PONG"))

    # B. memory round-trip (several patterns)
    def mem_rt():
        for v in (0xDEADBEEF, 0x00000000, 0xFFFFFFFF, 0xA5A5A5A5, 0x12345678):
            m.write(BRAM_TEST, v)
            got = m.read(BRAM_TEST)
            if got != v:
                return False, "wrote %08x read %08x" % (v, got)
        return True, "5 patterns OK"
    r.check("memory read/write", mem_rt)

    # C. LED MMIO write/read
    def led_rt():
        m.write(LED, 0x1234)
        got = m.read(LED) & 0xFFFF
        return got == 0x1234, "led=%04x" % got
    r.check("LED MMIO", led_rt)

    # D. switches (informational — depends on physical position)
    def sw_read():
        v = m.read(SWITCHES)
        return True, "switches=0x%08x (verify against board)" % v
    r.check("switch read", sw_read)

    # E. performance counters advance
    def perf():
        c1 = m.counter(PERF_CYCLE)
        time.sleep(0.05)
        c2 = m.counter(PERF_CYCLE)
        i1 = m.counter(PERF_INSTRET)
        return (c2 > c1 and i1 > 0), "cycle %u->%u instret=%u" % (c1, c2, i1)
    r.check("perf counters advance", perf)

    # F. synchronous exceptions
    def exc_ecall():
        line = m.ecall()          # expect "!TRAP c=0000000b e=..."
        return ("TRAP" in line and "0000000b" in line.lower()), line
    r.check("ecall exception (cause 11)", exc_ecall)

    def exc_illegal():
        line = m.illegal()        # expect "!TRAP c=00000002 ..."
        return ("TRAP" in line and "00000002" in line.lower()), line
    r.check("illegal-instr exception (cause 2)", exc_illegal)

    # G. UART RX interrupt: enable, send byte, expect "!RX<HEX>"
    def rx_irq():
        m.rx_irq(True)
        m.drain_async()
        m.send("a")               # 0x61 -> firmware uppercases to 'A'=0x41
        line = m.async_line()
        m.rx_irq(False)
        return line.upper().startswith("!RX41"), line
    r.check("RX interrupt echo", rx_irq)

    # H. timer interrupt heartbeat
    def timer_irq():
        m.drain_async()
        m.arm_timer(50000)        # deadline = now + 50000 ticks
        line = m.async_line(timeout=3.0)
        return line.startswith("!TICK"), line
    r.check("timer interrupt", timer_irq)

    # I. precise resume: main loop still responds after interrupts
    def resume():
        return (m.ping() == "PONG", "monitor alive after IRQs")
    r.check("main loop resumes after IRQ", resume)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True)
    ap.add_argument("--baud", type=int, default=9600)
    a = ap.parse_args()

    m = Monitor(a.port, a.baud)
    time.sleep(0.3)
    m.drain_all()                 # discard the boot banner (a plain line) + any async
    r = Runner(m)
    try:
        build_tests(r)
    finally:
        ok = r.summary()
        m.close()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
