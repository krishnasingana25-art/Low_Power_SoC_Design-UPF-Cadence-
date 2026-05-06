// alu_core.v
// Power Domain B - will be power gated when idle
// Clock gating on individual functional units

module alu_core (
    input  wire        clk,
    input  wire        rst_n,
    // Power gating interface
    input  wire        power_down_req,   // from controller
    output wire        power_down_ack,
    input  wire        isolate_en,       // isolation control
    // Operands
    input  wire [15:0] operand_a,
    input  wire [15:0] operand_b,
    input  wire [3:0]  opcode,
    input  wire        valid_in,
    // Results
    output reg  [31:0] result,
    output reg         result_valid,
    output reg         overflow,
    // Clock gating enables (per functional unit)
    input  wire        adder_en,
    input  wire        mult_en,
    input  wire        logic_en,
    input  wire        shift_en
);

    // ------------------------------------------------
    // CLOCK GATING - Per functional unit
    // Genus will map these to ICG cells
    // ------------------------------------------------
    wire clk_adder, clk_mult, clk_logic, clk_shift;

    // Cadence Genus recognizes this pattern for ICG insertion
    // EN must be sampled on falling edge (latch-based ICG)
    CLKGATETST_X1 icg_adder (
        .CLK   (clk),
        .EN    (adder_en),
        .TE    (1'b0),        // test enable - tie low for RTL
        .GCLK  (clk_adder)
    );

    CLKGATETST_X1 icg_mult (
        .CLK   (clk),
        .EN    (mult_en),
        .TE    (1'b0),
        .GCLK  (clk_mult)
    );

    CLKGATETST_X1 icg_logic (
        .CLK   (clk),
        .EN    (logic_en),
        .TE    (1'b0),
        .GCLK  (clk_logic)
    );

    CLKGATETST_X1 icg_shift (
        .CLK   (clk),
        .EN    (shift_en),
        .TE    (1'b0),
        .GCLK  (clk_shift)
    );

    // ------------------------------------------------
    // ADDER UNIT - clocked by clk_adder
    // ------------------------------------------------
    reg [31:0] add_result;
    reg        add_overflow;

    always @(posedge clk_adder or negedge rst_n) begin
        if (!rst_n) begin
            add_result   <= 32'h0;
            add_overflow <= 1'b0;
        end else begin
            {add_overflow, add_result[15:0]} <= 
                {1'b0, operand_a} + {1'b0, operand_b};
            add_result[31:16] <= 16'h0;
        end
    end

    // ------------------------------------------------
    // MULTIPLIER UNIT - clocked by clk_mult
    // 4-stage pipelined multiply
    // ------------------------------------------------
    reg [31:0] mult_result;
    reg [31:0] mult_pipe [0:2];

    always @(posedge clk_mult or negedge rst_n) begin
        if (!rst_n) begin
            mult_pipe[0] <= 32'h0;
            mult_pipe[1] <= 32'h0;
            mult_pipe[2] <= 32'h0;
            mult_result  <= 32'h0;
        end else begin
            mult_pipe[0] <= operand_a * operand_b;
            mult_pipe[1] <= mult_pipe[0];
            mult_pipe[2] <= mult_pipe[1];
            mult_result  <= mult_pipe[2];
        end
    end

    // ------------------------------------------------
    // LOGIC UNIT - clocked by clk_logic
    // ------------------------------------------------
    reg [31:0] logic_result;

    always @(posedge clk_logic or negedge rst_n) begin
        if (!rst_n) begin
            logic_result <= 32'h0;
        end else begin
            case (opcode[1:0])
                2'b00: logic_result <= {16'h0, operand_a & operand_b};
                2'b01: logic_result <= {16'h0, operand_a | operand_b};
                2'b10: logic_result <= {16'h0, operand_a ^ operand_b};
                2'b11: logic_result <= {16'h0, ~operand_a};
                default: logic_result <= 32'h0;
            endcase
        end
    end

    // ------------------------------------------------
    // SHIFT UNIT - clocked by clk_shift
    // ------------------------------------------------
    reg [31:0] shift_result;

    always @(posedge clk_shift or negedge rst_n) begin
        if (!rst_n) begin
            shift_result <= 32'h0;
        end else begin
            case (opcode[1:0])
                2'b00: shift_result <= {16'h0, operand_a << operand_b[3:0]};
                2'b01: shift_result <= {16'h0, operand_a >> operand_b[3:0]};
                2'b10: shift_result <= 
                    {{16{operand_a[15]}}, operand_a} >>> operand_b[3:0];
                default: shift_result <= 32'h0;
            endcase
        end
    end

    // ------------------------------------------------
    // OUTPUT MUX - selects result based on opcode[3:2]
    // ------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result       <= 32'h0;
            result_valid <= 1'b0;
            overflow     <= 1'b0;
        end else begin
            result_valid <= valid_in;
            overflow     <= 1'b0;
            case (opcode[3:2])
                2'b00: begin result <= add_result;   overflow <= add_overflow; end
                2'b01: begin result <= mult_result;  end
                2'b10: begin result <= logic_result; end
                2'b11: begin result <= shift_result; end
            endcase
        end
    end

    // ------------------------------------------------
    // POWER GATING ACKNOWLEDGE
    // Acknowledge when outputs are isolated and stable
    // ------------------------------------------------
    // In real design: daisy-chain through switch cells
    // Here: register the request for RTL simulation
    reg pg_ack_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pg_ack_reg <= 1'b0;
        else
            pg_ack_reg <= power_down_req & isolate_en;
    end
    assign power_down_ack = pg_ack_reg;

endmodule
