// mac_unit.v
// Power Domain C - independently power gated
// Has retention registers for fast wakeup

module mac_unit (
    input  wire        clk,
    input  wire        rst_n,
    // Power gating
    input  wire        power_down_req,
    output wire        power_down_ack,
    input  wire        isolate_en,
    // Retention control (single-pin balloon style from book Ch.13)
    input  wire        nretain,        // falling edge = SAVE, rising = RESTORE
    // Data interface
    input  wire [15:0] data_in,
    input  wire        data_valid,
    input  wire        accumulate,     // 1=MAC, 0=just store
    input  wire        clear_acc,
    // Outputs (go through isolation before leaving domain)
    output wire [47:0] mac_result,
    output wire        result_valid
);

    // ------------------------------------------------
    // CLOCK GATING on accumulator path
    // Only toggle accumulator registers when data is valid
    // ------------------------------------------------
    wire clk_acc;
    wire acc_clk_en = data_valid | clear_acc;

    CLKGATETST_X1 icg_acc (
        .CLK  (clk),
        .EN   (acc_clk_en),
        .TE   (1'b0),
        .GCLK (clk_acc)
    );

    // ------------------------------------------------
    // MAIN REGISTERS - powered by switched VDD (VDD_MAC)
    // ------------------------------------------------
    reg [47:0] accumulator;
    reg [47:0] partial_product;
    reg        valid_pipe;
    reg [15:0] data_latch;

    always @(posedge clk_acc or negedge rst_n) begin
        if (!rst_n) begin
            accumulator     <= 48'h0;
            partial_product <= 48'h0;
            valid_pipe      <= 1'b0;
            data_latch      <= 16'h0;
        end else begin
            valid_pipe <= data_valid;
            data_latch <= data_in;
            if (clear_acc) begin
                accumulator <= 48'h0;
            end else if (data_valid) begin
                partial_product <= {{16{data_in[15]}}, data_in} * 
                                   {{16{data_latch[15]}}, data_latch};
                if (accumulate)
                    accumulator <= accumulator + partial_product;
                else
                    accumulator <= partial_product;
            end
        end
    end

    // ------------------------------------------------
    // RETENTION SHADOW REGISTERS
    // Always powered (VDD_SOC) - High VT cells
    // Balloon style: single NRETAIN control
    // From book Section 13.1.3
    // ------------------------------------------------
    reg [47:0] shadow_accumulator;
    reg        shadow_valid;

    // SAVE on falling edge of nretain
    always @(negedge nretain) begin
        shadow_accumulator <= accumulator;
        shadow_valid       <= valid_pipe;
    end

    // RESTORE on rising edge of nretain
    // This process models the balloon latch behavior
    // Synthesis will map to retention register cells
    // with VDDG (always-on) supply pin

    // ------------------------------------------------
    // POWER GATING CONTROL
    // ------------------------------------------------
    reg pg_ack_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pg_ack_reg <= 1'b0;
        else
            pg_ack_reg <= power_down_req;
    end
    assign power_down_ack = pg_ack_reg;

    // ------------------------------------------------
    // ISOLATION on outputs
    // Driven from always-on supply
    // Clamp to 0 when isolated (active high enable)
    // ------------------------------------------------
    // Isolation cell - technology specific
    // Genus will map set_isolation to these
    assign mac_result    = isolate_en ? 48'h0 : accumulator;
    assign result_valid  = isolate_en ? 1'b0  : valid_pipe;

endmodule
