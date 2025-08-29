// tt_um_cordic_wrapper.v — TinyTapeout topo (Verilog-2001)
module tt_um_cordic_wrapper #(parameter integer WIDTH = 16)
(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ena,
    input  wire [7:0]  ui_in,
    output wire [7:0]  uo_out,
    input  wire [7:0]  uio_in,
    output wire [7:0]  uio_out,
    output wire [7:0]  uio_oe
);

    // -------------------------------
    // --- Configuração de latência ---
    // -------------------------------
    localparam integer PIPE_LAT = WIDTH;            // nº de ciclos até saída válida
    reg  [PIPE_LAT:0]  latency_shifter;            // 1 bit extra
    wire               result_is_valid;

    // -------------------------------
    // --- Handshake I/O (uio) ---
    // -------------------------------
    wire in_valid;
    reg  in_ready;
    reg  out_valid;
    wire out_ready;

    // uio[2]=out_valid (saída), uio[1]=in_ready (saída)
    assign uio_oe       = 8'b0000_0110;
    assign in_valid     = uio_in[0];
    assign out_ready    = uio_in[3];
    assign uio_out[1]   = in_ready;
    assign uio_out[2]   = out_valid;
    assign uio_out[7:3] = 5'b0;
    assign uio_out[0]   = 1'b0;

    // Consumir bits de uio_in não usados (silencia verilator UNUSED)
    wire _unused_uio_in;
    assign _unused_uio_in = &{1'b0, uio_in[7:4], uio_in[2:1]};

    // -------------------------------
    // --- Estados Entrada/Saída ---
    // -------------------------------
    // Entrada
    localparam [2:0]
        S_IN_IDLE  = 3'd0,
        S_IN_X_MSB = 3'd1,
        S_IN_Y_LSB = 3'd2,
        S_IN_Y_MSB = 3'd3,
        S_IN_WAIT  = 3'd4;
    reg [2:0] in_state;

    // Saída
    localparam [2:0]
        S_OUT_IDLE     = 3'd0,
        S_OUT_MAG_LSB  = 3'd1,
        S_OUT_MAG_MSB  = 3'd2,
        S_OUT_PHASE_B0 = 3'd3,
        S_OUT_PHASE_B1 = 3'd4,
        S_OUT_PHASE_B2 = 3'd5,
        S_OUT_PHASE_B3 = 3'd6;
    reg [2:0] out_state;

    // -------------------------------
    // --- Registradores de dados ---
    // -------------------------------
    reg  signed [WIDTH-1:0] x_input_reg;
    reg  signed [WIDTH-1:0] y_input_reg;
    reg  signed [WIDTH-1:0] magnitude_reg;
    reg  signed [31:0]      phase_reg;
    reg  [7:0]              uo_out_reg;

    reg start_cordic_pipeline;
    reg result_ready_for_tx;

    // -------------------------------
    // --- Núcleo CORDIC ---
    // -------------------------------
    wire signed [WIDTH-1:0] cordic_mag_out;
    wire signed [31:0]      cordic_phase_out;

    CORDIC_vec #(.width(WIDTH)) u_cordic_core (
        .clock     (clk),
        .x_start   (x_input_reg),
        .y_start   (y_input_reg),
        .magnitude (cordic_mag_out),
        .phase     (cordic_phase_out)
    );

    // Busy flags
    wire pipeline_busy = |latency_shifter;
    wire tx_busy       = (out_state != S_OUT_IDLE) | result_ready_for_tx;
    wire core_busy     = pipeline_busy | tx_busy;

    // -------------------------------
    // --- FSM de Entrada ---
    // -------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_state              <= S_IN_IDLE;
            in_ready              <= 1'b1;
            start_cordic_pipeline <= 1'b0;
            x_input_reg           <= {WIDTH{1'b0}};
            y_input_reg           <= {WIDTH{1'b0}};
        end else if (ena) begin
            start_cordic_pipeline <= 1'b0;
            in_ready              <= (in_state != S_IN_WAIT);

            case (in_state)
                S_IN_IDLE: begin
                    if (in_valid & in_ready) begin
                        x_input_reg[7:0] <= ui_in;
                        in_state <= S_IN_X_MSB;
                    end
                end
                S_IN_X_MSB: begin
                    if (in_valid & in_ready) begin
                        x_input_reg[15:8] <= ui_in;
                        in_state <= S_IN_Y_LSB;
                    end
                end
                S_IN_Y_LSB: begin
                    if (in_valid & in_ready) begin
                        y_input_reg[7:0] <= ui_in;
                        in_state <= S_IN_Y_MSB;
                    end
                end
                S_IN_Y_MSB: begin
                    if (in_valid & in_ready) begin
                        y_input_reg[15:8] <= ui_in;
                        start_cordic_pipeline <= 1'b1; // dispara o CORDIC
                        in_state <= S_IN_WAIT;
                    end
                end
                S_IN_WAIT: begin
                    if (!core_busy)
                        in_state <= S_IN_IDLE;
                end
            endcase
        end
    end

    // -------------------------------
    // --- Controle de latência ---
    // -------------------------------
    assign result_is_valid = latency_shifter[PIPE_LAT];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latency_shifter     <= {(PIPE_LAT+1){1'b0}};
            magnitude_reg       <= {WIDTH{1'b0}};
            phase_reg           <= 32'sd0;
            result_ready_for_tx <= 1'b0;
        end else if (ena) begin
            latency_shifter <= {latency_shifter[PIPE_LAT-1:0], start_cordic_pipeline};

            if (result_is_valid) begin
                magnitude_reg       <= cordic_mag_out;
                phase_reg           <= cordic_phase_out;
                result_ready_for_tx <= 1'b1;
            end

            if (out_state != S_OUT_IDLE)
                result_ready_for_tx <= 1'b0;
        end
    end

    // -------------------------------
    // --- FSM de Saída ---
    // -------------------------------
    assign uo_out = uo_out_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_state  <= S_OUT_IDLE;
            out_valid  <= 1'b0;
            uo_out_reg <= 8'h00;
        end else if (ena) begin
            case (out_state)
                S_OUT_IDLE: begin
                    out_valid  <= 1'b0;
                    uo_out_reg <= 8'h00;
                    if (result_ready_for_tx) begin
                        out_state  <= S_OUT_MAG_LSB;
                        uo_out_reg <= magnitude_reg[7:0];
                        out_valid  <= 1'b1;
                    end
                end
                S_OUT_MAG_LSB: if (out_ready) begin
                    out_state  <= S_OUT_MAG_MSB;
                    uo_out_reg <= magnitude_reg[15:8];
                end
                S_OUT_MAG_MSB: if (out_ready) begin
                    out_state  <= S_OUT_PHASE_B0;
                    uo_out_reg <= phase_reg[7:0];
                end
                S_OUT_PHASE_B0: if (out_ready) begin
                    out_state  <= S_OUT_PHASE_B1;
                    uo_out_reg <= phase_reg[15:8];
                end
                S_OUT_PHASE_B1: if (out_ready) begin
                    out_state  <= S_OUT_PHASE_B2;
                    uo_out_reg <= phase_reg[23:16];
                end
                S_OUT_PHASE_B2: if (out_ready) begin
                    out_state  <= S_OUT_PHASE_B3;
                    uo_out_reg <= phase_reg[31:24];
                end
                S_OUT_PHASE_B3: if (out_ready) begin
                    out_state  <= S_OUT_IDLE;
                    out_valid  <= 1'b0;
                    uo_out_reg <= 8'h00;
                end
            endcase
        end
    end
endmodule
