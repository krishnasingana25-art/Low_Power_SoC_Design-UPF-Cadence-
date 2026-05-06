// top_soc.v
// Integrates all three power domains
// Isolation cells at domain boundaries

module top_soc (
    input  wire        clk,
    input  wire        rst_n,
    // External control
    input  wire        sleep_alu,
    input  wire        sleep_mac,
    input  wire        wake_alu,
    input  wire        wake_mac,
    // Data inputs
    input  wire [15:0] op_a,
    input  wire [15:0] op_b,
    input  wire [3:0]  opcode,
    input  wire        valid,
    input  wire        accumulate,
    input  wire        clear_acc,
    // Outputs
    output wire [31:0] alu_out,
    output wire        alu_valid,
    output wire [47:0] mac_out,
    output wire        mac_valid,
    output wire        alu_active,
    output wire        mac_active
);

    // ------------------------------------------------
    // DOMAIN A: CONTROLLER (Always On - VDD_SOC)
    // ------------------------------------------------
    wire        pg_req_alu, pg_ack_alu, iso_alu, rst_alu_n;
    wire        pg_req_mac, pg_ack_mac, iso_mac, rst_mac_n;
    wire        nretain_mac;
    wire        alu_adder_en, alu_mult_en, alu_logic_en, alu_shift_en;

    power_controller u_ctrl (
        .clk          (clk),
        .rst_n        (rst_n),
        .sleep_req_alu (sleep_alu),
        .sleep_req_mac (sleep_mac),
        .wake_req_alu  (wake_alu),
        .wake_req_mac  (wake_mac),
        .pg_req_alu    (pg_req_alu),
        .pg_ack_alu    (pg_ack_alu),
        .iso_alu       (iso_alu),
        .rst_alu_n     (rst_alu_n),
        .pg_req_mac    (pg_req_mac),
        .pg_ack_mac    (pg_ack_mac),
        .iso_mac       (iso_mac),
        .rst_mac_n     (rst_mac_n),
        .nretain_mac   (nretain_mac),
        .alu_adder_en  (alu_adder_en),
        .alu_mult_en   (alu_mult_en),
        .alu_logic_en  (alu_logic_en),
        .alu_shift_en  (alu_shift_en),
        .alu_active    (alu_active),
        .mac_active    (mac_active),
        .opcode_hint   (opcode)
    );

    // ------------------------------------------------
    // DOMAIN B: ALU (Power Gated - VDD_ALU)
    // Isolation cells driven by iso_alu (always-on net)
    // ------------------------------------------------
    wire [31:0] alu_result_raw;
    wire        alu_valid_raw;
    wire        alu_overflow_raw;

    alu_core u_alu (
        .clk            (clk),
        .rst_n          (rst_alu_n),
        .power_down_req (pg_req_alu),
        .power_down_ack (pg_ack_alu),
        .isolate_en     (iso_alu),
        .operand_a      (op_a),
        .operand_b      (op_b),
        .opcode         (opcode),
        .valid_in       (valid),
        .result         (alu_result_raw),
        .result_valid   (alu_valid_raw),
        .overflow       (alu_overflow_raw),
        .adder_en       (alu_adder_en),
        .mult_en        (alu_mult_en),
        .logic_en       (alu_logic_en),
        .shift_en       (alu_shift_en)
    );

    // ------------------------------------------------
    // ISOLATION CELLS: Domain B -> Top
    // AND-style (clamp to 0) per book Section 5.2.1
    // Always powered by VDD_SOC
    // UPF will instantiate proper library cells
    // ------------------------------------------------
    // iso_alu=1 means ISOLATE (clamp to 0)
    assign alu_out   = iso_alu ? 32'h0 : alu_result_raw;
    assign alu_valid = iso_alu ? 1'b0  : alu_valid_raw;

    // ------------------------------------------------
    // DOMAIN C: MAC (Power Gated with Retention - VDD_MAC)
    // ------------------------------------------------
    wire [47:0] mac_result_raw;
    wire        mac_valid_raw;

    mac_unit u_mac (
        .clk            (clk),
        .rst_n          (rst_mac_n),
        .power_down_req (pg_req_mac),
        .power_down_ack (pg_ack_mac),
        .isolate_en     (iso_mac),
        .nretain        (nretain_mac),
        .data_in        (op_a),
        .data_valid     (valid & mac_active),
        .accumulate     (accumulate),
        .clear_acc      (clear_acc),
        .mac_result     (mac_result_raw),
        .result_valid   (mac_valid_raw)
    );

    // Isolation: Domain C -> Top
    assign mac_out   = iso_mac ? 48'h0 : mac_result_raw;
    assign mac_valid = iso_mac ? 1'b0  : mac_valid_raw;

endmodule
