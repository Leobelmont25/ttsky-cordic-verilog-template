`timescale 1ns/1ps

module CORDIC_wrapper_tb;
    // sinais TT
    initial begin
        $dumpfile("CORDIC_wrapper_tb.vcd");
        $dumpvars(0, CORDIC_wrapper_tb);
        #1;
    end
    
    reg clk, rst_n, ena;
    reg  [7:0] ui_in;
    wire [7:0] uo_out;
    reg  [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    // DUT SEM parâmetros (funciona em RTL e GL)
    tt_um_cordic_wrapper dut (
        .clk(clk), .rst_n(rst_n), .ena(ena),
        .ui_in(ui_in), .uo_out(uo_out),
        .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe)
    );

    // clock 100 MHz
    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        rst_n=0; ena=0; ui_in=8'h00; uio_in=8'h00;
        repeat(5) @(posedge clk);
        rst_n=1; ena=1;

        // envia X[7:0], X[15:8], Y[7:0], Y[15:8]
        send_byte(8'h24);
        send_byte(8'h35);
        send_byte(8'h81);
        send_byte(8'h5E);

        // consome 6 bytes: mag LSB/MSB, phase[7:0],15:8,23:16,31:24
        consume_bytes(6);

        repeat(20) @(posedge clk);
        $finish;
    end

    // protocolo (mapeamento do wrapper)
    // uio_in[0]=in_valid, uio_out[1]=in_ready, uio_in[3]=out_ready, uio_out[2]=out_valid
    task send_byte(input [7:0] b);
    begin
        while (uio_out[1] !== 1'b1) @(posedge clk); // espera in_ready
        ui_in <= b;
        uio_in[0] <= 1'b1; @(posedge clk);
        uio_in[0] <= 1'b0;
    end
    endtask

    task consume_bytes(input integer n);
        integer i;
    begin
        for (i=0;i<n;i=i+1) begin
            uio_in[3] <= 1'b1;                    // out_ready=1
            while (uio_out[2] !== 1'b1) @(posedge clk); // espera out_valid
            $display("[TB] byte%0d = 0x%02x", i, uo_out);
            @(posedge clk);
            uio_in[3] <= 1'b0; @(posedge clk);
        end
    end
    endtask
endmodule
