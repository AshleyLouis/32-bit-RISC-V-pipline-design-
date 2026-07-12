#!/usr/bin/env python3
"""PC-side serial link to the RV32I monitor firmware (programs/monitor.S).

Low-level transport only: open the COM port, send command lines, read replies,
and separate synchronous replies from asynchronous ISR output (lines the
firmware prefixes with '!'). tests.py builds the verification suite on top.

Requires pyserial:  pip install pyserial

Usage examples:
    python monitor.py --port COM5 ping
    python monitor.py --port COM5 read 0x10000010
    python monitor.py --port COM5 write 0x00000400 0xdeadbeef
"""
import sys
import time
import argparse
import queue
import threading

try:
    import serial
except ImportError:
    sys.exit("pyserial not installed. Run:  pip install pyserial")


class Monitor:
    # Plain lines the firmware emits unsolicited (boot/monitor-entry banner).
    # They are filtered out of the reply stream so they never desync a command.
    BANNER_LINES = ("RV32I OK",)

    def __init__(self, port, baud=9600, timeout=2.0):
        # Open without toggling DTR/RTS so we don't reset the board on connect
        # (a reset would re-emit the banner mid-session).
        self.ser = serial.Serial()
        self.ser.port = port
        self.ser.baudrate = baud
        self.ser.timeout = 0.1
        self.ser.dtr = False
        self.ser.rts = False
        self.ser.open()
        self.timeout = timeout
        self.sync_q = queue.Queue()    # normal reply lines
        self.async_q = queue.Queue()   # '!'-prefixed ISR lines
        self._buf = b""
        self._stop = threading.Event()
        self._rx = threading.Thread(target=self._reader, daemon=True)
        self._rx.start()

    def _reader(self):
        while not self._stop.is_set():
            data = self.ser.read(64)
            if not data:
                continue
            self._buf += data
            while b"\n" in self._buf:
                line, self._buf = self._buf.split(b"\n", 1)
                text = line.decode("ascii", "replace").rstrip("\r")
                if text == "":
                    continue
                if text in self.BANNER_LINES:
                    continue                       # unsolicited banner: ignore
                if text.startswith("!"):
                    self.async_q.put(text)
                else:
                    self.sync_q.put(text)

    def close(self):
        self._stop.set()
        self.ser.close()

    # ---- transport ----
    def send(self, s):
        """Send raw ASCII (no automatic newline; the protocol is char-based)."""
        self.ser.write(s.encode("ascii"))
        self.ser.flush()

    def reply(self, timeout=None):
        """Wait for the next synchronous reply line."""
        try:
            return self.sync_q.get(timeout=timeout or self.timeout)
        except queue.Empty:
            raise TimeoutError("no reply from board (timeout)")

    def async_line(self, timeout=None):
        """Wait for the next asynchronous ('!') ISR line."""
        try:
            return self.async_q.get(timeout=timeout or self.timeout)
        except queue.Empty:
            raise TimeoutError("no async/ISR line from board (timeout)")

    def drain_async(self):
        """Return all async lines currently queued (non-blocking)."""
        out = []
        try:
            while True:
                out.append(self.async_q.get_nowait())
        except queue.Empty:
            pass
        return out

    def drain_all(self):
        """Discard everything currently queued (sync + async), e.g. the boot
        banner. The banner 'RV32I OK' is a plain (sync) line, so drain_async
        alone would leave it in front of the first real reply."""
        for q in (self.sync_q, self.async_q):
            try:
                while True:
                    q.get_nowait()
            except queue.Empty:
                pass

    # ---- commands (mirror monitor.S) ----
    def ping(self):
        self.send("P")
        return self.reply()

    def read(self, addr):
        self.send("R%08x" % (addr & 0xFFFFFFFF))
        r = self.reply()
        return int(r.lstrip("="), 16)

    def write(self, addr, data):
        self.send("W%08x%08x" % (addr & 0xFFFFFFFF, data & 0xFFFFFFFF))
        return self.reply()

    def counter(self, n):
        self.send("C%x" % (n & 0xF))
        return int(self.reply().lstrip("="), 16)

    def arm_timer(self, ticks):
        self.send("T%08x" % (ticks & 0xFFFFFFFF))
        return self.reply()

    def ecall(self):
        self.send("E")
        return self.async_line()      # handler prints "!TRAP ..."

    def illegal(self):
        self.send("Z")
        return self.async_line()

    def rx_irq(self, enable):
        self.send("I" + ("e" if enable else "d"))
        return self.reply()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True, help="serial port, e.g. COM5 or /dev/ttyUSB0")
    ap.add_argument("--baud", type=int, default=9600)
    ap.add_argument("cmd", nargs="+", help="ping | read <addr> | write <addr> <data> | counter <n>")
    a = ap.parse_args()

    m = Monitor(a.port, a.baud)
    time.sleep(0.2)
    m.drain_async()   # discard boot banner leftovers
    try:
        c = a.cmd[0]
        if c == "ping":
            print(m.ping())
        elif c == "read":
            print("0x%08x" % m.read(int(a.cmd[1], 0)))
        elif c == "write":
            print(m.write(int(a.cmd[1], 0), int(a.cmd[2], 0)))
        elif c == "counter":
            print("0x%08x" % m.counter(int(a.cmd[1], 0)))
        else:
            print("unknown command", c)
    finally:
        m.close()


if __name__ == "__main__":
    main()
