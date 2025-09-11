`timescale 1ns / 1ps

module CORDIC_wrapper_tb;

    localparam WIDTH      = 16;
    localparam CLK_PERIOD = 10; // 100 MHz

    reg  clk;
    reg  rst_n;
    reg  ena;
    reg  [7:0] ui_in;
    wire [7:0] uo_out;
    reg  [7:0] uio_in_tb;
    wire [7:0] uio_out_tb;
    wire [7:0] uio_en_tb;

    wire [7:0] uio_in_dut = uio_in_tb;

    // ============================
    // DUMP PARA GTKWave (VCD/FST)
    // ============================
    initial begin
        // --- VCD (padrão) ---
        $dumpfile("cordic_wrapper_tb.vcd");
        $dumpvars(0, CORDIC_wrapper_tb);   // tudo sob o top do TB

        // --- Dica: para reduzir arquivo, você pode comentar a linha acima
        // e abrir dumps específicos:
        // $dumpvars(1, tb_cordic_wrapper.dut);
        // $dumpvars(2, tb_cordic_wrapper.dut.u_cordic_core);

        // --- Alternativa FST (mais compacto): descomente estas duas linhas
        // e rode com: vvp -fst sim.test
        // $dumpfile("cordic_wrapper_tb.fst");
        // $dumpvars(0, tb_cordic_wrapper);
    end

    tt_um_cordic_wrapper #(.WIDTH(WIDTH)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .ena(ena),
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in_dut),
        .uio_en(uio_en_tb),
        .uio_out(uio_out_tb)
    );

    wire dut_in_ready   = uio_out_tb[1];
    wire dut_out_valid  = uio_out_tb[2];

    reg tb_in_valid;
    reg tb_out_ready;

    always @* begin
        uio_in_tb[0] = tb_in_valid;  // in_valid
        uio_in_tb[3] = tb_out_ready; // out_ready
    end

    // Clock
    always begin
        clk = 1'b0; #(CLK_PERIOD/2);
        clk = 1'b1; #(CLK_PERIOD/2);
    end

    // --- envio ---
    task send_first_byte(input [7:0] data);
    begin
        @(posedge clk);
        $display("[%0t ns] TB: Aguardando in_ready do DUT para enviar 0x%h...", $time, data);
        wait (dut_in_ready == 1'b1);
        ui_in <= data;
        tb_in_valid <= 1'b1;
        @(posedge clk);
        tb_in_valid <= 1'b0;
        ui_in <= 8'hzz;
    end
    endtask

    task send_next_byte(input [7:0] data);
    begin
        @(posedge clk);
        ui_in <= data;
        tb_in_valid <= 1'b1;
        @(posedge clk);
        tb_in_valid <= 1'b0;
        ui_in <= 8'hzz;
    end
    endtask

    // --- recepção ---
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

    // --- execução de um teste ---
    task run_test(input signed [WIDTH-1:0] x_val, input signed [WIDTH-1:0] y_val);
        reg signed [WIDTH-1:0] mag_res;
        reg signed [31:0]      phase_res;
        reg [7:0] byte_data;
    begin
        $display("\n=== Teste: X = %0d (0x%h), Y = %0d (0x%h) ===", x_val, x_val, y_val, y_val);

        send_first_byte(x_val[7:0]);
        send_next_byte(x_val[15:8]);
        send_next_byte(y_val[7:0]);
        send_next_byte(y_val[15:8]);

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

    // --- inicialização ---
    initial begin
        $display("--- INICIANDO TESTBENCH ---");
        rst_n <= 1'b0;
        ena <= 1'b1;
        ui_in <= 8'hzz;
        tb_in_valid <= 1'b0;
        tb_out_ready <= 1'b0;

        repeat(20) @(posedge clk);
        rst_n <= 1'b1;
        $display("[%0t ns] Reset liberado.", $time);

        wait (dut_in_ready == 1'b1);
        $display("[%0t ns] DUT pronto para receber.", $time);

        // Novos valores (diferentes dos anteriores), 1 por quadrante
        run_test( 12000,   8000);   // Q1: X>0, Y>0
        #(20*CLK_PERIOD);

        run_test(-15000,  10000);   // Q2: X<0, Y>0
        #(20*CLK_PERIOD);

        run_test(-18000, -22000);   // Q3: X<0, Y<0
        #(20*CLK_PERIOD);

        run_test( 25000, -12000);   // Q4: X>0, Y<0
        #(20*CLK_PERIOD);

        $display("\n--- TESTBENCH CONCLUÍDO ---");
        $finish;
    end

endmodule
