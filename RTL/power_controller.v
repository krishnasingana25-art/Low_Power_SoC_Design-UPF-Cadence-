// power_controller.v
// Always-On Domain A - VDD_SOC
// Controls power sequencing per book Chapter 5.4

module power_controller (
    input  wire        clk,           // always-on clock
    input  wire        rst_n,
    // System interface
    input  wire        sleep_req_alu,  // request to sleep ALU domain
    input  wire        sleep_req_mac,  // request to sleep MAC domain
    input  wire        wake_req_alu,
    input  wire        wake_req_mac,
    // ALU power domain control
    output reg         pg_req_alu,     // power gate request (active high = power down)
    input  wire        pg_ack_alu,     // acknowledge from switch fabric
    output reg         iso_alu,        // isolation enable
    output reg         rst_alu_n,      // reset to ALU
    // MAC power domain control
    output reg         pg_req_mac,
    input  wire        pg_ack_mac,
    output reg         iso_mac,
    output reg         rst_mac_n,
    output reg         nretain_mac,    // retention control
    // Clock gate enables for ALU sub-units
    output reg         alu_adder_en,
    output reg         alu_mult_en,
    output reg         alu_logic_en,
    output reg         alu_shift_en,
    // Status
    output wire        alu_active,
    output wire        mac_active,
    // Opcode hint for smart clock gating
    input  wire [3:0]  opcode_hint
);

    // ------------------------------------------------
    // POWER STATE MACHINE - ALU Domain
    // Based on book Figure 5-8 (with retention)
    // ------------------------------------------------
    // States per book Section 5.4.1
    localparam ALU_ON       = 3'd0;  // fully operational
    localparam ALU_ISOLATE  = 3'd1;  // assert isolation
    localparam ALU_GATE     = 3'd2;  // assert power gate
    localparam ALU_OFF      = 3'd3;  // power gated, waiting
    localparam ALU_WAKE     = 3'd4;  // de-assert power gate
    localparam ALU_RESTORE  = 3'd5;  // de-assert isolation
    localparam ALU_INIT     = 3'd6;  // de-assert reset

    reg [2:0] alu_state, alu_next;

    // ------------------------------------------------
    // POWER STATE MACHINE - MAC Domain
    // Includes retention (nretain) per book Figure 5-8
    // ------------------------------------------------
    localparam MAC_ON       = 3'd0;
    localparam MAC_ISOLATE  = 3'd1;  // isolate outputs
    localparam MAC_SAVE     = 3'd2;  // save retention state
    localparam MAC_GATE     = 3'd3;  // power gate
    localparam MAC_OFF      = 3'd4;  // waiting
    localparam MAC_WAKE     = 3'd5;  // restore power
    localparam MAC_RESTORE  = 3'd6;  // restore retention state
    localparam MAC_UNINIT   = 3'd7;  // de-isolate

    reg [2:0] mac_state, mac_next;

    // Timeout counter for power-up settling
    // Book Section 5.4.2: handshake protocol
    reg [5:0] settle_cnt;

    // ------------------------------------------------
    // ALU STATE REGISTER
    // ------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            alu_state <= ALU_INIT;
        else
            alu_state <= alu_next;
    end

    // ------------------------------------------------
    // ALU NEXT STATE LOGIC
    // ------------------------------------------------
    always @(*) begin
        alu_next = alu_state;
        case (alu_state)
            ALU_INIT:    alu_next = ALU_ON;

            ALU_ON: begin
                if (sleep_req_alu)
                    alu_next = ALU_ISOLATE;
            end

            ALU_ISOLATE: begin
                // Wait 1 cycle for isolation to settle
                alu_next = ALU_GATE;
            end

            ALU_GATE: begin
                // Wait for power gate acknowledge (handshake)
                // Book Section 5.4.2
                if (pg_ack_alu)
                    alu_next = ALU_OFF;
            end

            ALU_OFF: begin
                if (wake_req_alu)
                    alu_next = ALU_WAKE;
            end

            ALU_WAKE: begin
                // Handshake: wait for ack to de-assert
                // meaning power is fully restored
                if (!pg_ack_alu)
                    alu_next = ALU_RESTORE;
            end

            ALU_RESTORE: begin
                alu_next = ALU_INIT;
            end

            ALU_INIT: begin
                alu_next = ALU_ON;
            end

            default: alu_next = ALU_INIT;
        endcase
    end

    // ------------------------------------------------
    // ALU OUTPUT LOGIC
    // Per book: power up sequence (Section 5.4.1)
    // Order: pg -> iso -> rst
    // ------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pg_req_alu  <= 1'b0;
            iso_alu     <= 1'b0;
            rst_alu_n   <= 1'b0;
        end else begin
            case (alu_state)
                ALU_ON: begin
                    pg_req_alu <= 1'b0;
                    iso_alu    <= 1'b0;
                    rst_alu_n  <= 1'b1;
                end
                ALU_ISOLATE: begin
                    iso_alu    <= 1'b1; // assert isolation first
                    rst_alu_n  <= 1'b0; // assert reset
                end
                ALU_GATE: begin
                    pg_req_alu <= 1'b1; // request power gate
                end
                ALU_OFF: begin
                    pg_req_alu <= 1'b1;
                    iso_alu    <= 1'b1;
                end
                ALU_WAKE: begin
                    pg_req_alu <= 1'b0; // de-assert power gate
                end
                ALU_RESTORE: begin
                    iso_alu    <= 1'b0; // release isolation
                    rst_alu_n  <= 1'b1;
                end
            endcase
        end
    end

    // ------------------------------------------------
    // MAC STATE REGISTER
    // ------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mac_state <= MAC_ON;
        else
            mac_state <= mac_next;
    end

    // ------------------------------------------------
    // MAC NEXT STATE LOGIC (with retention)
    // ------------------------------------------------
    always @(*) begin
        mac_next = mac_state;
        case (mac_state)
            MAC_ON: begin
                if (sleep_req_mac) mac_next = MAC_ISOLATE;
            end
            MAC_ISOLATE:  mac_next = MAC_SAVE;
            MAC_SAVE:     mac_next = MAC_GATE;   // 1-cycle save pulse
            MAC_GATE: begin
                if (pg_ack_mac) mac_next = MAC_OFF;
            end
            MAC_OFF: begin
                if (wake_req_mac) mac_next = MAC_WAKE;
            end
            MAC_WAKE: begin
                if (!pg_ack_mac) mac_next = MAC_RESTORE;
            end
            MAC_RESTORE:  mac_next = MAC_UNINIT;
            MAC_UNINIT:   mac_next = MAC_ON;
            default:      mac_next = MAC_ON;
        endcase
    end

    // ------------------------------------------------
    // MAC OUTPUT LOGIC
    // Sequence: iso -> save -> reset -> pg_gate (sleep)
    // Wake:     pg_wake -> reset_off -> restore -> de-iso
    // Book Figure 5-8
    // ------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pg_req_mac  <= 1'b0;
            iso_mac     <= 1'b0;
            rst_mac_n   <= 1'b1;
            nretain_mac <= 1'b1;
        end else begin
            case (mac_state)
                MAC_ON: begin
                    pg_req_mac  <= 1'b0;
                    iso_mac     <= 1'b0;
                    rst_mac_n   <= 1'b1;
                    nretain_mac <= 1'b1; // retention latch tracks live data
                end
                MAC_ISOLATE: begin
                    iso_mac   <= 1'b1;  // isolate outputs
                    rst_mac_n <= 1'b0;  // assert reset
                end
                MAC_SAVE: begin
                    nretain_mac <= 1'b0; // falling edge = SAVE
                    // shadow register captures state
                end
                MAC_GATE: begin
                    pg_req_mac <= 1'b1; // request power gate
                end
                MAC_OFF: begin
                    // nretain stays low - holding shadow data
                end
                MAC_WAKE: begin
                    pg_req_mac <= 1'b0; // wake power gate
                end
                MAC_RESTORE: begin
                    nretain_mac <= 1'b1; // rising edge = RESTORE
                    rst_mac_n   <= 1'b1;
                end
                MAC_UNINIT: begin
                    iso_mac <= 1'b0;    // de-assert isolation
                end
            endcase
        end
    end

    // ------------------------------------------------
    // INTELLIGENT CLOCK GATING CONTROL
    // Based on opcode hint - saves power in ALU_ON state
    // Book Section 2.1: only enable needed functional units
    // ------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_adder_en <= 1'b0;
            alu_mult_en  <= 1'b0;
            alu_logic_en <= 1'b0;
            alu_shift_en <= 1'b0;
        end else begin
            // Decode opcode to enable only needed unit
            // Other units stay clock gated -> zero dynamic power
            alu_adder_en <= (opcode_hint[3:2] == 2'b00) & (alu_state == ALU_ON);
            alu_mult_en  <= (opcode_hint[3:2] == 2'b01) & (alu_state == ALU_ON);
            alu_logic_en <= (opcode_hint[3:2] == 2'b10) & (alu_state == ALU_ON);
            alu_shift_en <= (opcode_hint[3:2] == 2'b11) & (alu_state == ALU_ON);
        end
    end

    // Status outputs
    assign alu_active = (alu_state == ALU_ON);
    assign mac_active = (mac_state == MAC_ON);

endmodule
