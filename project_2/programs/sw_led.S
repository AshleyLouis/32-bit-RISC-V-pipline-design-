// Minimal RV32I program for the EGO1 SoC smoke test.
// It mirrors {dip_sw, sw} to LED and seven-segment display data.

// x1 = GPIO base, 0x10000000
lui  x1, 0x10000

loop:
lw   x2, 4(x1)      // x2 = switch input
sw   x2, 0(x1)      // LED output
sw   x2, 8(x1)      // seven-segment debug value
jal  x0, loop
