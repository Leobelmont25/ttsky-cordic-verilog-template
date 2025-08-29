module CORDIC_vec #(parameter integer width = 16, parameter integer GUARD = 2) (
    input  wire                       clock,
    input  wire signed [width-1:0]    x_start,
    input  wire signed [width-1:0]    y_start,
    output wire signed [width-1:0]    magnitude,
    output wire signed [31:0]         phase     // Q1.31 (angulo/PI)
);
    localparam integer INTW = width + GUARD;      // largura interna
    localparam signed [15:0] INV_K = 16'sh26DF;   // ~0.6073 Q2.14
    localparam integer        INV_K_Q_BITS = 14;

    // --------- ATAN(2^-i)/PI em Q1.31 (constante, sem 'real' / 'initial') ----------
    function [31:0] atan_q31;
        input integer idx;
        begin
            case (idx)
                0 : atan_q31 = 32'h2000_0000; // 0.25 * 2^31
                1 : atan_q31 = 32'h12E4_051E;
                2 : atan_q31 = 32'h09FB_385B;
                3 : atan_q31 = 32'h0511_11D4;
                4 : atan_q31 = 32'h028B_0D43;
                5 : atan_q31 = 32'h0145_D7E1;
                6 : atan_q31 = 32'h00A2_F61E;
                7 : atan_q31 = 32'h0051_7C55;
                8 : atan_q31 = 32'h0028_BE53;
                9 : atan_q31 = 32'h0014_5F2F;
                10: atan_q31 = 32'h000A_2F98;
                11: atan_q31 = 32'h0005_17CC;
                12: atan_q31 = 32'h0002_8BE6;
                13: atan_q31 = 32'h0001_45F3;
                14: atan_q31 = 32'h0000_A2FA;
                15: atan_q31 = 32'h0000_517D;
                default: atan_q31 = 32'h0000_0000; // para idx >= 16
            endcase
        end
    endfunction

    // --------- Pré-processamento (sign-extend antes de negar) ----------
    localparam integer EXT = (INTW + 1) - width;  // constante
    wire signed [INTW:0] x_ext = {{EXT{x_start[width-1]}}, x_start};
    wire signed [INTW:0] y_ext = {{EXT{y_start[width-1]}}, y_start};

    wire signed [INTW:0] x0_input = x_start[width-1] ? -x_ext : x_ext;
    wire signed [INTW:0] y0_input = x_start[width-1] ? -y_ext : y_ext;

    // Q1.31
    wire signed [31:0] z0_input =
        (x_start[width-1] == 1'b0) ? 32'sd0 :
        (y_start[width-1] == 1'b0) ? -32'sh8000_0000 : 32'sh8000_0000;

    // --------- Pipeline ----------
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
            localparam [31:0] ATAN = atan_q31(stage); // constante por estágio
            wire signed [INTW:0] x_shift = x_pipe[stage] >>> stage;
            wire signed [INTW:0] y_shift = y_pipe[stage] >>> stage;
            always @(posedge clock) begin
                if (y_pipe[stage] >= 0) begin
                    x_pipe[stage+1] <= x_pipe[stage] + y_shift;
                    y_pipe[stage+1] <= y_pipe[stage] - x_shift;
                    z_pipe[stage+1] <= z_pipe[stage] - ATAN;
                end else begin
                    x_pipe[stage+1] <= x_pipe[stage] - y_shift;
                    y_pipe[stage+1] <= y_pipe[stage] + x_shift;
                    z_pipe[stage+1] <= z_pipe[stage] + ATAN;
                end
            end
        end
    endgenerate

    // --------- Saídas (compatível com Icarus + sem UNUSED) ----------
    wire signed [INTW:0]    scaled_magnitude = x_pipe[width];
    wire signed [INTW+16:0] mult_full        = scaled_magnitude * INV_K;
    wire signed [INTW+16:0] mag_shifted_full = mult_full >>> INV_K_Q_BITS;

    assign magnitude = mag_shifted_full[width-1:0];

    // consome bits altos para silenciar linter UNUSED
    wire _unused_mag_hi;
    assign _unused_mag_hi = &{1'b0, mag_shifted_full[INTW+16:width]};

    assign phase = -z_pipe[width];
endmodule
