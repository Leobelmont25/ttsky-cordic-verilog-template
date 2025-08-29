module CORDIC_vec #(parameter integer width = 16, parameter integer GUARD = 2) (
    input  wire                       clock,
    input  wire signed [width-1:0]    x_start,
    input  wire signed [width-1:0]    y_start,
    output wire signed [width-1:0]    magnitude,
    output wire signed [31:0]         phase     // Q1.31 (angulo/PI)
);
    // ---------------- Parametrização ----------------
    localparam integer INTW = width + GUARD;          // largura interna
    localparam signed [15:0] INV_K = 16'sh26DF;       // ~0.6073 em Q2.14
    localparam integer        INV_K_Q_BITS = 14;

    // ---------------- ATAN LUT ----------------
    // (mantive sua geração por 'initial' para simulação; se o lint
    // reclamar de 'real', troque por $readmemh, ver nota ao final)
    reg signed [31:0] atan_table [0:width-1];
    integer i;
    initial begin
        for (i = 0; i < width; i = i + 1) begin
            real angle_rad;
            real angle_norm;
            angle_rad  = $atan(1.0 / (1 << i));               // atan(2^-i)
            angle_norm = angle_rad / 3.141592653589793;       // / PI
            atan_table[i] = $rtoi(angle_norm * (2.0**31));    // Q1.31
        end
    end

    // ---------------- Pré-processamento (quadrante) ----------------
    // Sign-extend de 16 → (INTW+1) bits ANTES de negar
    localparam integer EXT = (INTW + 1) - width;               // bits de extensão

    wire signed [INTW:0] x_ext = {{EXT{x_start[width-1]}}, x_start};
    wire signed [INTW:0] y_ext = {{EXT{y_start[width-1]}}, y_start};

    // Use o valor já estendido nos dois ramos (mesma largura)
    wire signed [INTW:0] x0_input = x_start[width-1] ? -x_ext : x_ext;
    wire signed [INTW:0] y0_input = x_start[width-1] ? -y_ext : y_ext;

    // Ângulo inicial (Q1.31), preservando larguras constantes
    wire signed [31:0] z0_input =
        (x_start[width-1] == 1'b0) ? 32'sd0 :
        (y_start[width-1] == 1'b0) ? -32'sh8000_0000 : 32'sh8000_0000;

    // ---------------- Pipeline CORDIC ----------------
    reg signed [INTW:0] x_pipe [0:width];
    reg signed [INTW:0] y_pipe [0:width];
    reg signed [31:0]   z_pipe [0:width];

    always @(posedge clock) begin
        x_pipe[0] <= x0_input;
        y_pipe[0] <= y0_input;
        z_pipe[0] <= z0_input;
    end

    genvar stage;
    generate
        for (stage = 0; stage < width; stage = stage + 1) begin : cordic_stage
            wire signed [INTW:0] x_shift = x_pipe[stage] >>> stage;
            wire signed [INTW:0] y_shift = y_pipe[stage] >>> stage;
            always @(posedge clock) begin
                if (y_pipe[stage] >= 0) begin
                    x_pipe[stage+1] <= x_pipe[stage] + y_shift;
                    y_pipe[stage+1] <= y_pipe[stage] - x_shift;
                    z_pipe[stage+1] <= z_pipe[stage] - atan_table[stage];
                end else begin
                    x_pipe[stage+1] <= x_pipe[stage] - y_shift;
                    y_pipe[stage+1] <= y_pipe[stage] + x_shift;
                    z_pipe[stage+1] <= z_pipe[stage] + atan_table[stage];
                end
            end
        end
    endgenerate

    // ---------------- Saídas ----------------
    wire signed [INTW:0]    scaled_magnitude = x_pipe[width];
    wire signed [INTW+16:0] mult_full        = scaled_magnitude * INV_K;  // (INTW+1)+16
    wire signed [INTW+16:0] mag_full_q       = mult_full >>> INV_K_Q_BITS; // mantém largura

    // Corte explícito p/ calar o linter sobre truncamento
    assign magnitude = mag_full_q[width-1:0];
    assign phase     = -z_pipe[width];

endmodule
