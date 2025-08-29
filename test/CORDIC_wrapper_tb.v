`timescale 1ns/1ps

module tb_cordic_wrapper;
    // ---- Parâmetros do TB (apenas para RTL) ----
    localparam integer WIDTH_TB = 16;

    // ---- Sinais TT ----
    reg clk;
    reg rst_n;
    reg ena;

    reg  [7:0] ui_in;
    wire [7:0] uo_out;
    reg  [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    // ============================================================
    //  INSTÂNCIA DO DUT
    //  >> ÚNICA MUDANÇA: condicional para GL (sem parâmetros)
    // ============================================================
`ifdef GL
    // Netlist gate-level: módulo sintetizado normalmente NÃO expõe parâmetros
    tt_um_cordic_wrapper dut (
        .clk(clk), .rst_n(rst_n), .ena(ena),
        .ui_in(ui_in), .uo_out(uo_out),
        .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe)
    );
`else
    // RTL: pode passar o parâmetro de largura
    tt_um_cordic_wrapper #(.WIDTH(WIDTH_TB)) dut (
        .clk(clk), .rst_n(rst_n), .ena(ena),
        .ui_in(ui_in), .uo_out(uo_out),
        .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe)
    );
`endif

    // ---- Clock 100MHz ----
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---- Estímulos ----
    initial begin
        rst_n  = 1'b0;
        ena    = 1'b0;
        ui_in  = 8'h00;
        uio_in = 8'h00;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        ena   = 1'b1;

        // Envia X[7:0], X[15:8], Y[7:0], Y[15:8] quando in_ready=1
        send_byte(8'h24); // X LSB
        send_byte(8'h35); // X MSB
        send_byte(8'h81); // Y LSB
        send_byte(8'h5E); // Y MSB

        // Consome 6 bytes de saída: mag[7:0], mag[15:8], phase[7:0],15:8,23:16,31:24
        consume_bytes(6);

        repeat (20) @(posedge clk);
        $finish;
    end

    // ------------------------------------------------------------
    // Protocolo (mapeamento conforme seu wrapper)
    //   uio_in[0]  = in_valid   (entrada TB -> DUT)
    //   uio_out[1] = in_ready   (saída DUT -> TB)
    //   uio_in[3]  = out_ready  (entrada TB -> DUT)
    //   uio_out[2] = out_valid  (saída DUT -> TB)
    // ------------------------------------------------------------

    task send_byte(input [7:0] b);
    begin
        // espera in_ready
        while (uio_out[1] !== 1'b1) @(posedge clk);
        ui_in     <= b;
        uio_in[0] <= 1'b1;   // in_valid = 1
        @(posedge clk);
        uio_in[0] <= 1'b0;   // in_valid = 0
    end
    endtask

    task consume_bytes(input integer n);
        integer i;
    begin
        for (i = 0; i < n; i = i + 1) begin
            uio_in[3] <= 1'b1;                 // out_ready = 1
            while (uio_out[2] !== 1'b1) @(posedge clk); // espera out_valid
            $display("[TB] byte%0d = 0x%02x", i, uo_out);
            @(posedge clk);
            uio_in[3] <= 1'b0;                 // out_ready = 0
            @(posedge clk);
        end
    end
    endtask

endmodule
