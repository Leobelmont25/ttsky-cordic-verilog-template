/*
 * Wrapper para CORDIC para tapeout.
 * Versão revisada (fix deadlock de in_ready):
 * - in_ready alto durante a recepção dos 4 bytes (toda a transação).
 * - Estado S_IN_WAIT para bloquear novas entradas enquanto o core está ocupado.
 * - core_busy = pipeline_busy || tx_busy.
 */
module CORDIC_tapeout_wrapper #(parameter WIDTH = 16)
(
    input   wire            clk,
    input   wire            rst_n,
    input   wire            ena,
    input   wire [7:0]      ui_in,
    output  wire [7:0]      uo_out,
    input   wire [7:0]      uio_in,
    output  wire [7:0]      uio_en,
    output  wire [7:0]      uio_out
);

    // -------------------------------
    // --- Configuração de latência ---
    // -------------------------------
    localparam PIPE_LAT = WIDTH; // Nº de ciclos até saída válida do CORDIC
    reg [PIPE_LAT:0] latency_shifter; // Bit extra para segurança
    wire result_is_valid;

    // -------------------------------
    // --- Sinais de Handshake ---
    // -------------------------------
    wire in_valid;
    reg  in_ready;
    reg  out_valid;
    wire out_ready;

    // -------------------------------
    // --- Mapeamento I/O ---
    // -------------------------------
    assign uio_en     = 8'b00001100; // uio[2:1] são saídas
    assign in_valid   = uio_in[0];
    assign out_ready  = uio_in[3];
    assign uio_out[1] = in_ready;
    assign uio_out[2] = out_valid;
    // Demaís pinos de uio_out permanecem Z (via uio_en)

    // -------------------------------
    // --- Estados FSM Entrada ---
    // -------------------------------
    typedef enum logic [2:0] {
        S_IN_IDLE,
        S_IN_X_MSB,
        S_IN_Y_LSB,
        S_IN_Y_MSB,
        S_IN_WAIT   // novo: aguarda core ficar livre
    } in_state_e;
    reg in_state_e in_state;

    // -------------------------------
    // --- Estados FSM Saída ---
    // -------------------------------
    typedef enum logic [2:0] {
        S_OUT_IDLE,
        S_OUT_MAG_LSB,
        S_OUT_MAG_MSB,
        S_OUT_PHASE_B0,
        S_OUT_PHASE_B1,
        S_OUT_PHASE_B2,
        S_OUT_PHASE_B3
    } out_state_e;
    reg out_state_e out_state;

    // -------------------------------
    // --- Registradores de dados ---
    // -------------------------------
    reg signed [WIDTH-1:0]  x_input_reg;
    reg signed [WIDTH-1:0]  y_input_reg;
    reg signed [WIDTH-1:0]  magnitude_reg;
    reg signed [31:0]       phase_reg;
    reg [7:0]               uo_out_reg;

    // Controle de fluxo
    reg start_cordic_pipeline;
    reg result_ready_for_tx;

    // -------------------------------
    // --- Instanciação do CORDIC ---
    // -------------------------------
    wire signed [WIDTH-1:0] cordic_mag_out;
    wire signed [31:0]      cordic_phase_out;

    CORDIC_vec #(.width(WIDTH)) u_cordic_core (
        .clock      (clk),
        .x_start    (x_input_reg),
        .y_start    (y_input_reg),
        .magnitude  (cordic_mag_out),
        .phase      (cordic_phase_out)
    );

    // -------------------------------
    // --- Busy flags (ocupação do core) ---
    // -------------------------------
    wire pipeline_busy = |latency_shifter;                 // há operações em voo
    wire tx_busy       = (out_state != S_OUT_IDLE) || result_ready_for_tx;
    wire core_busy     = pipeline_busy || tx_busy;

    // -------------------------------
    // --- FSM de Entrada ---
    // -------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_state <= S_IN_IDLE;
            in_ready <= 1'b1;
            start_cordic_pipeline <= 1'b0;
            x_input_reg <= '0;
            y_input_reg <= '0;
        end else if (ena) begin
            start_cordic_pipeline <= 1'b0;

            // in_ready alto enquanto estamos esperando/consumindo os 4 bytes;
            // fica baixo apenas em S_IN_WAIT (core ocupado).
            in_ready <= (in_state != S_IN_WAIT);

            case (in_state)
                S_IN_IDLE: begin
                    if (in_valid && in_ready) begin
                        x_input_reg[7:0] <= ui_in;
                        in_state <= S_IN_X_MSB;
                    end
                end

                S_IN_X_MSB: begin
                    if (in_valid && in_ready) begin
                        x_input_reg[15:8] <= ui_in;
                        in_state <= S_IN_Y_LSB;
                    end
                end

                S_IN_Y_LSB: begin
                    if (in_valid && in_ready) begin
                        y_input_reg[7:0] <= ui_in;
                        in_state <= S_IN_Y_MSB;
                    end
                end

                S_IN_Y_MSB: begin
                    if (in_valid && in_ready) begin
                        y_input_reg[15:8] <= ui_in;
                        // dispara o CORDIC e entra em espera até core ficar livre
                        start_cordic_pipeline <= 1'b1;
                        in_state <= S_IN_WAIT;
                    end
                end

                S_IN_WAIT: begin
                    // Espera pipeline e transmissão terminarem para aceitar nova palavra
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
            latency_shifter     <= '0;
            magnitude_reg       <= '0;
            phase_reg           <= '0;
            result_ready_for_tx <= 1'b0;
        end else if (ena) begin
            latency_shifter <= {latency_shifter[PIPE_LAT-1:0], start_cordic_pipeline};

            if (result_is_valid) begin
                magnitude_reg       <= cordic_mag_out;
                phase_reg           <= cordic_phase_out;
                result_ready_for_tx <= 1'b1;
            end

            // Assim que a FSM de saída começar a transmitir, limpamos o "pronto"
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
            uo_out_reg <= '0;
        end else if (ena) begin
            case (out_state)
                S_OUT_IDLE: begin
                    out_valid <= 1'b0;
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
                    uo_out_reg <= '0;
                end
            endcase
        end
    end

endmodule

