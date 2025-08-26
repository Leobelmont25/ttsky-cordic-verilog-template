How it works

This project implements a vectoring CORDIC core wrapped with a simple byte-stream, valid/ready interface compatible with the TinyTapeout template.

Function: Given signed 16-bit Cartesian inputs X and Y, the core computes:
Magnitude 𝑟=𝑥2+𝑦2 (16-bit signed, non-negative).

Phase θ=atan2(y,x) in Q1.31 fixed-point, normalized by π (i.e., value = 𝜃/𝜋×2^31, two’s complement).

Pipeline latency: PIPE_LAT = WIDTH cycles (default WIDTH=16, so 16 cycles).

Protocol:

Input: 4 bytes → X[7:0], X[15:8], Y[7:0], Y[15:8]

Output: 6 bytes → MAG[7:0], MAG[15:8], PHASE[7:0], PHASE[15:8], PHASE[23:16], PHASE[31:24]

Handshake (bidirectional uio pins):

IN_VALID (uio[0], input): pulse once per input byte.

IN_READY (uio[1], output): high when wrapper ready to accept input.

OUT_VALID (uio[2], output): high while output byte is valid.

OUT_READY (uio[3], input): pulse once per output byte consumed.

Throughput is one result per (4 + PIPE_LAT + 6) cycles.

How to test

You can exercise the core in simulation or hardware by driving the protocol.

Reset & enable

Hold rst_n = 0 for ≥ 20 clock cycles, then set rst_n = 1.

Keep ena = 1.

Wait until IN_READY = 1.

Send inputs (4 bytes)

Present each byte of X and Y on ui[7:0], pulse IN_VALID per byte.

Order: X LSB → X MSB → Y LSB → Y MSB.

After the 4th byte, IN_READY will drop while the pipeline runs.

Wait for output

After ~16 cycles (default WIDTH), OUT_VALID rises with the first result byte.

Read outputs (6 bytes)

While OUT_VALID = 1, read uo[7:0].

Pulse OUT_READY to step through: MAG LSB, MAG MSB, PHASE[7:0], PHASE[15:8], PHASE[23:16], PHASE[31:24].

After the 6th byte, OUT_VALID drops and IN_READY goes high again.

Example test vectors

Q1: X=20000, Y=15000 → Magnitude ≈ 25000, Phase ≈ 0.643 rad (Q1.31 ≈ 439,887,038)

Q2: X=−15000, Y=10000 → Magnitude ≈ 18027, Phase ≈ 2.55 rad (Q1.31 ≈ 1,747,533,392)

Q3: X=−18000, Y=−22000 → Magnitude ≈ 28431, Phase ≈ −2.26 rad (Q1.31 ≈ −1,544,333,270)

Q4: X=25000, Y=−12000 → Magnitude ≈ 27732, Phase ≈ −0.445 rad (Q1.31 ≈ −304,422,737)

External hardware

None required.
The design only uses standard TinyTapeout pins.
You can drive it directly from:

An FPGA or microcontroller acting as the master.

A logic analyzer for observation.

Optional: A host can be added to decode the Q1.31 phase into radians/degrees and print results via UART/USB.
