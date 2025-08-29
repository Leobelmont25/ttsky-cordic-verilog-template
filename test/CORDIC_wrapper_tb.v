`timescale 1ns/1ps

module tb_cordic_wrapper;
    // clock/reset
    reg clk;
    reg rst_n;
    reg ena;

    // TT I/O
    reg  [7:0] ui_in;
    wire [7:0] uo_out;
    reg  [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    // DUT = seu topo TT
    tt_um_cordic_wrapper #(.WIDTH(16)) dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .ena    (ena),
        .ui_in  (ui_in),
        .uo_out (uo_out),
        .uio_in (uio_in),
        .uio_out(uio_out),
        .uio_oe (uio_oe)
    );

    // clock 10ns
    initial clk = 0;
    always #5 clk = ~clk;

    // simples “driver” do seu protocolo:
    // uio_oe[1]=in_ready (saída do DUT), uio_oe[2]=out_valid (saída do DUT)
    // uio_in[0]=in_valid (entrada para DUT), uio_in[3]=out_ready (entrada para DUT)
    initial begin
        rst_n   = 0;
        ena     = 0;
        ui_in   = 8'h00;
        uio_in  = 8'h00;

        repeat (5) @(posedge clk);
        rst_n = 1;
        ena   = 1;

        // envia X[7:0], X[15:8], Y[7:0], Y[15:8] quando in_ready=1
        send_byte(8'h24); // X LSB
        send_byte(8'h35); // X MSB
        send_byte(8'h81); // Y LSB
        send_byte(8'h5E); // Y MSB

        // consome 6 bytes de saída (mag[7:0], mag[15:8], phase[7:0],15:8,23:16,31:24)
        consume_bytes(6);

        repeat (20) @(posedge clk);
        $finish;
    end

    task send_byte(input [7:0] b);
    begin
        // espera in_ready (uio_out[1]) — lembre: uio_oe controla tri-state, mas no TB
        // podemos só olhar uio_out[1] porque o wrapper já define uio_oe internamente.
        while (uio_out[1] !== 1'b1) @(posedge clk);
        ui_in    <= b;
        uio_in[0]<= 1'b1;  // in_valid=1
        @(posedge clk);
        uio_in[0]<= 1'b0;  // in_valid=0
    end
    endtask

    task consume_bytes(input integer n);
        integer i;
    begin
        for (i=0;i<n;i=i+1) begin
            // sinaliza que pode consumir (out_ready=1)
            uio_in[3] <= 1'b1;
            // espera out_valid=1
            while (uio_out[2] !== 1'b1) @(posedge clk);
            // lê uo_out aqui se quiser ($display)
            $display("[TB] byte%0d = 0x%02x", i, uo_out);
            @(posedge clk);
            uio_in[3] <= 1'b0;
            @(posedge clk);
        end
    end
    endtask
endmodule
