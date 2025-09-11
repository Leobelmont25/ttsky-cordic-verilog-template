`default_nettype none
`timescale 1ns/1ps

/* TinyTapeout-style testbench:
 * - Dumps signals to VCD (view in GTKWave)
 * - Works for RTL and Gate-Level (GL_TEST)
 * - Instantiates tt_um_cordic_wrapper
 */
module tb;

  // ---- VCD dump ----
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
    #1; // garante algum tempo > 0
  end

  // ---- Signals ----
  reg         clk;
  reg         rst_n;
  reg         ena;
  reg  [7:0]  ui_in;
  reg  [7:0]  uio_in;
  wire [7:0]  uo_out;
  wire [7:0]  uio_out;
  wire [7:0]  uio_oe;

`ifdef GL_TEST
  // Gate-level power pins
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  // ---- DUT ----
  // Substitua o nome abaixo se seu top mudar
  tt_um_cordic_wrapper dut (
`ifdef GL_TEST
    .VPWR   (VPWR),
    .VGND   (VGND),
`endif
    .ui_in  (ui_in),     // Dedicated inputs (8 bits)
    .uo_out (uo_out),    // Dedicated outputs (8 bits)
    .uio_in (uio_in),    // Bidirectional: input path
    .uio_out(uio_out),   // Bidirectional: output path
    .uio_oe (uio_oe),    // Bidirectional: enable path (1 = output)
    .ena    (ena),       // goes high when design is selected
    .clk    (clk),       // clock
    .rst_n  (rst_n)      // active-low reset
  );

  // ---- Clock 100 MHz ----
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // ---- Handshake aliases (conforme seu wrapper) ----
  // uio_in[0] = IN_VALID,  uio_out[1] = IN_READY
  // uio_out[2] = OUT_VALID, uio_in[3] = OUT_READY
  wire in_ready  = uio_out[1];
  wire out_valid = uio_out[2];

  // ---- Simple stimulus just to get waveforms ----
  initial begin
    // Init
    rst_n   = 1'b0;
    ena     = 1'b0;
    ui_in   = 8'h00;
    uio_in  = 8'h00;

    // Reset
    repeat (20) @(posedge clk);
    rst_n = 1'b1;
    ena   = 1'b1;

    // Pequeno atraso pós-reset
    repeat (5) @(posedge clk);

    // ===== Envia X[7:0], X[15:8], Y[7:0], Y[15:8] =====
    send_byte(8'h20); // X LSB
    send_byte(8'h4E); // X MSB  => X = 0x4E20 = 20000
    send_byte(8'h98); // Y LSB
    send_byte(8'h3A); // Y MSB  => Y = 0x3A98 = 15000

    // ===== Consome 6 bytes: mag LSB/MSB, phase[7:0],15:8,23:16,31:24 =====
    consume_bytes(6);

    // Keep sim running a bit for viewing
    repeat (50) @(posedge clk);
    $finish;
  end

  // ---- Tasks ----
  task send_byte(input [7:0] b);
  begin
    // espera o IN_READY subir (wrapper pronto para o próximo byte)
    @(posedge clk);
    while (in_ready !== 1'b1) @(posedge clk);

    // coloca o byte e pulsa IN_VALID por 1 ciclo
    ui_in      <= b;
    uio_in[0]  <= 1'b1;  // IN_VALID = 1
    @(posedge clk);
    uio_in[0]  <= 1'b0;  // IN_VALID = 0
    // opcional: tri-state lógico do ui_in não é necessário, mas pode-se limpar
    // ui_in <= 8'h00;
  end
  endtask

  task consume_bytes(input integer n);
    integer i;
  begin
    for (i = 0; i < n; i = i + 1) begin
      // aguarda OUT_VALID, então dá OUT_READY por 1 ciclo
      @(posedge clk);
      while (out_valid !== 1'b1) @(posedge clk);
      $display("[TB] out byte %0d = 0x%02x", i, uo_out);
      uio_in[3] <= 1'b1;    // OUT_READY
      @(posedge clk);
      uio_in[3] <= 1'b0;
    end
  end
  endtask

endmodule

`default_nettype wire
