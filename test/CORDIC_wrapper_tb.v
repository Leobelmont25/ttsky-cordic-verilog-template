`timescale 1ns / 1ps
// Descomente se o seu template usa essa diretiva global
// `default_nettype none

// ================================
// Parametrização via macro WIDTH
// ================================
`ifndef WIDTH
  `define WIDTH 16
`endif

module CORDIC_wrapper_tb;

    // ----------------------------
    // Parâmetros de TB
    // ----------------------------
    localparam int WIDTH_TB   = `WIDTH;
    localparam int CLK_PERIOD = 10; // 100 MHz

    // ----------------------------
    // Sinais do TB
    // ----------------------------
    reg  clk;
    reg  rst_n;
    reg  ena;
    reg  [7:0] ui_in;
    wire [7:0] uo_out;
    reg  [7:0] uio_in_tb;
    wire [7:0] uio_out_tb;
    wire [7:0] uio_oe_tb;

    // Map interno para o DUT
    wire [7:0] uio_in_dut = uio_in_tb;

    // ============================
    // Dump para GTKWave (VCD)
    // ============================
    initial begin
        // O CI costuma procurar esse caminho:
        $dumpfile("test/tb.vcd");
        $dumpvars(0, CORDIC_wrapper_tb);
    end

    // ============================
    // DUT: tt_um_cordic_wrapper
    //   (parametrizado via macro)
// ============================
    tt_um_cordic_wrapper #(.WIDTH(WIDTH_TB)) dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .ena    (ena),
        .ui_in  (ui_in),
        .uo_out (uo_out),
        .uio_in (uio_in_dut),
        .uio_out(uio_out_tb),
        .uio_oe (uio_oe_tb)
    );

    // Handshake do DUT via uio
    wire dut_in_ready  = uio_out_tb[1];
    wire dut_out_valid = uio_out_tb[2];

    reg tb_in_valid;
    reg tb_out_ready;

    // Direciona sinais para o DUT
    always @* begin
        uio_in_tb[0] = tb_in_valid;  // in_valid
        uio_in_tb[3] = tb_out_ready; // out_ready
        // Demais bits de uio_in não usados
        uio_in_tb[2:1] = 2'b00;
        uio_in_tb[7:4] = 4'b0000;
    end

    // ----------------------------
    // Clock
    // ----------------------------
    always begin
        clk = 1'b0; #(CLK_PERIOD/2);
        clk = 1'b1; #(CLK_PERIOD/2);
    end

    // ----------------------------
    // Tarefas de envio/recepção
    // ----------------------------
    task send_first_byte(input [7:0] data);
    begin
        @(posedge clk);
        $display("[%0t ns] TB: Aguardando in_ready do DUT para enviar 0x%h...", $time, data);
        wait (dut_in_ready == 1'b1);
        ui_in <= data;
        tb_in_valid <= 1'b1;
        @(posedge clk);
        tb_in_valid <= 1'b0;
        ui_in <= 8'h00;
    end
    endtask

    task send_next_byte(input [7:0] data);
    begin
        @(posedge clk);
        ui_in <= data;
        tb_in_valid <= 1'b1;
        @(posedge clk);
        tb_in_valid <= 1'b0;
        ui_in <= 8'h00;
    end
    endtask

    task receive_byte(output [7:0] data);
    begin
        @(posedge clk);
        wait (dut_out_valid == 1'b1);
        data = uo_out;
        tb_out_ready <= 1'b1;
        @(posedge clk);
        tb_out_ready <= 1'b0;
    end
    endtask

    task run_test(input signed [WIDTH_TB-1:0] x_val, input signed [WIDTH_TB-1:0] y_val);
        reg signed [WIDTH_TB-1:0] mag_res;
        reg signed [31:0]         phase_res;
        reg [7:0] byte_data;
    begin
        $display("\n=== Teste: X = %0d (0x%h), Y = %0d (0x%h) ===", x_val, x_val, y_val, y_val);

        // envia 4 bytes (X LSB/MSB, Y LSB/MSB)
        send_first_byte(x_val[7:0]);
        send_next_byte (x_val[15:8]);
        send_next_byte (y_val[7:0]);
        send_next_byte (y_val[15:8]);

        // recebe 6 bytes (mag[7:0], mag[15:8], phase[7:0], phase[15:8], phase[23:16], phase[31:24])
        receive_byte(byte_data); mag_res[7:0]   = byte_data;
        receive_byte(byte_data); mag_res[15:8]  = byte_data;
        receive_byte(byte_data); phase_res[7:0]   = byte_data;
        receive_byte(byte_data); phase_res[15:8]  = byte_data;
        receive_byte(byte_data); phase_res[23:16] = byte_data;
        receive_byte(byte_data); phase_res[31:24] = byte_data;

        $display(">>> Resultado: Magnitude = %0d (0x%h)", mag_res, mag_res);
        $display(">>> Resultado: Fase = %0d (0x%h)", phase_res, phase_res);
    end
    endtask

    // ----------------------------
    // Sequência de teste
    // ----------------------------
    initial begin
        $display("--- INICIANDO TESTBENCH ---");
        rst_n <= 1'b0;
        ena   <= 1'b1;
        ui_in <= 8'h00;
        tb_in_valid  <= 1'b0;
        tb_out_ready <= 1'b0;

        // Reset “confortável”
        repeat(20) @(posedge clk);
        rst_n <= 1'b1;
        $display("[%0t ns] Reset liberado.", $time);

        // Espera DUT sinalizar pronto
        wait (dut_in_ready == 1'b1);
        $display("[%0t ns] DUT pronto para receber.", $time);

        // --- NOVOS valores (diferentes dos anteriores), 1 por quadrante ---
        run_test( 16'sd12000,  16'sd8000 );   // Q1: X>0, Y>0
        #(20*CLK_PERIOD);

        run_test(-16'sd15000,  16'sd10000);   // Q2: X<0, Y>0
        #(20*CLK_PERIOD);

        run_test(-16'sd18000, -16'sd22000);   // Q3: X<0, Y<0
        #(20*CLK_PERIOD);

        run_test( 16'sd25000, -16'sd12000);   // Q4: X>0, Y<0
        #(20*CLK_PERIOD);

        $display("\n--- TESTBENCH CONCLUÍDO ---");
        $finish;
    end

endmodule
