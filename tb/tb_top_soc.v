// tb_top_soc.v
// Testbench providing realistic switching activity
// Activity factor directly affects dynamic power in Voltus

`timescale 1ns/1ps

module tb_top_soc;

    // ------------------------------------------------
    // CLOCK AND RESET
    // ------------------------------------------------
    parameter CLK_PERIOD = 10; // 100 MHz
    
    reg clk;
    reg rst_n;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        rst_n = 0;
        #(CLK_PERIOD * 5);
        rst_n = 1;
    end

    // ------------------------------------------------
    // DUT SIGNALS
    // ------------------------------------------------
    reg         sleep_alu, sleep_mac;
    reg         wake_alu,  wake_mac;
    reg  [15:0] op_a, op_b;
    reg  [3:0]  opcode;
    reg         valid;
    reg         accumulate, clear_acc;

    wire [31:0] alu_out;
    wire        alu_valid;
    wire [47:0] mac_out;
    wire        mac_valid;
    wire        alu_active, mac_active;

    // ------------------------------------------------
    // DUT INSTANTIATION
    // ------------------------------------------------
    top_soc dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .sleep_alu  (sleep_alu),
        .sleep_mac  (sleep_mac),
        .wake_alu   (wake_alu),
        .wake_mac   (wake_mac),
        .op_a       (op_a),
        .op_b       (op_b),
        .opcode     (opcode),
        .valid      (valid),
        .accumulate (accumulate),
        .clear_acc  (clear_acc),
        .alu_out    (alu_out),
        .alu_valid  (alu_valid),
        .mac_out    (mac_out),
        .mac_valid  (mac_valid),
        .alu_active (alu_active),
        .mac_active (mac_active)
    );

    // ------------------------------------------------
    // VCD/SAIF DUMP for Activity Factor
    // Voltus reads SAIF for accurate switching activity
    // ------------------------------------------------
    integer    saif_file;
    
    initial begin
        // Dump VCD for waveform viewing
        $dumpfile("top_soc_sim.vcd");
        $dumpvars(0, tb_top_soc);
        
        // SAIF annotation for Voltus power analysis
        // Captures toggle counts -> activity factor
        $set_gate_level_monitoring("rtl");
        $set_toggle_region(dut);
        $toggle_start();
    end

    // ------------------------------------------------
    // TASK: Randomized ALU operations
    // Tests all opcodes to get realistic activity factor
    // Mirrors typical processor workload distribution
    // ------------------------------------------------
    integer op_count;
    integer seed;

    task run_alu_workload;
        input integer num_ops;
        input integer opcode_bias; // 0=random, 1=add-heavy, 2=mult-heavy
        integer i;
        begin
            for (i = 0; i < num_ops; i = i + 1) begin
                @(posedge clk);
                valid  <= 1'b1;
                op_a   <= $random(seed);
                op_b   <= $random(seed);

                case (opcode_bias)
                    0: opcode <= $random(seed) & 4'hF; // uniform random
                    1: opcode <= {2'b00, $random(seed) & 2'h3}; // add-heavy
                    2: opcode <= {2'b01, $random(seed) & 2'h3}; // mult-heavy
                    3: opcode <= {2'b10, $random(seed) & 2'h3}; // logic-heavy
                    default: opcode <= 4'h0;
                endcase
            end
            @(posedge clk);
            valid <= 1'b0;
        end
    endtask

    // ------------------------------------------------
    // TASK: MAC workload
    // ------------------------------------------------
    task run_mac_workload;
        input integer num_samples;
        integer i;
        begin
            clear_acc  <= 1'b1;
            accumulate <= 1'b1;
            @(posedge clk);
            clear_acc <= 1'b0;
            for (i = 0; i < num_samples; i = i + 1) begin
                @(posedge clk);
                op_a  <= $random(seed) & 16'hFFFF;
                valid <= 1'b1;
            end
            @(posedge clk);
            valid <= 1'b0;
        end
    endtask

    // ------------------------------------------------
    // TASK: Power gate ALU, measure leakage
    // ------------------------------------------------
    task power_gate_alu;
        begin
            $display("[%0t] Requesting ALU power gate...", $time);
            sleep_alu <= 1'b1;
            @(posedge clk);
            sleep_alu <= 1'b0;
            // Wait for full power gate sequence
            wait (!alu_active);
            $display("[%0t] ALU power gated. Leakage period...", $time);
            // Stay gated for 100 cycles (measuring leakage savings)
            repeat (100) @(posedge clk);
        end
    endtask

    // ------------------------------------------------
    // TASK: Wake ALU from power gate
    // ------------------------------------------------
    task wake_alu_domain;
        begin
            $display("[%0t] Requesting ALU wakeup...", $time);
            wake_alu <= 1'b1;
            @(posedge clk);
            wake_alu <= 1'b0;
            wait (alu_active);
            $display("[%0t] ALU active again.", $time);
        end
    endtask

    // ================================================
    // MAIN SIMULATION SCENARIOS
    // Each phase captures different power profile
    // ================================================
    initial begin
        // Initialize
        sleep_alu  = 0; sleep_mac = 0;
        wake_alu   = 0; wake_mac  = 0;
        op_a       = 0; op_b      = 0;
        opcode     = 0; valid     = 0;
        accumulate = 0; clear_acc = 0;
        seed       = 42;

        wait (rst_n);
        repeat (10) @(posedge clk);

        // ============================================
        // PHASE 1: BASELINE - All domains ON
        // No power saving techniques active
        // Captures worst-case power reference
        // ============================================
        $display("\n=== PHASE 1: BASELINE - All domains ON ===");
        $toggle_start();
        
        // Run mixed workload for 500 cycles
        fork
            run_alu_workload(400, 0);  // random opcodes
            run_mac_workload(400);
        join
        
        $toggle_stop();
        $toggle_report("saif/phase1_baseline.saif", 1'b1, "tb_top_soc.dut");
        $display("Phase 1 complete. Check saif/phase1_baseline.saif");

        // ============================================
        // PHASE 2: CLOCK GATING ONLY
        // Same workload but with smart opcode dispatch
        // Only the needed functional unit gets clock
        // ============================================
        $display("\n=== PHASE 2: CLOCK GATING - Add-heavy workload ===");
        $toggle_start();

        // Only adder active -> 75% of ALU clock gated
        run_alu_workload(400, 1);  // add-heavy

        $toggle_stop();
        $toggle_report("saif/phase2_clock_gating.saif", 1'b1, "tb_top_soc.dut");

        // ============================================
        // PHASE 3: POWER GATING - ALU gated
        // MAC continues working, ALU in sleep
        // Measures leakage reduction of Domain B
        // ============================================
        $display("\n=== PHASE 3: POWER GATING ALU ===");
        $toggle_start();

        // Start MAC work
        fork
            begin
                // MAC runs continuously
                run_mac_workload(600);
            end
            begin
                // Gate ALU after 50 cycles
                repeat(50) @(posedge clk);
                power_gate_alu();    // gates for 100 cycles
                wake_alu_domain();
            end
        join

        $toggle_stop();
        $toggle_report("saif/phase3_power_gate_alu.saif", 1'b1, "tb_top_soc.dut");

        // ============================================
        // PHASE 4: BOTH DOMAINS GATED
        // Deep sleep - only controller active
        // Measures minimum power floor
        // ============================================
        $display("\n=== PHASE 4: DEEP SLEEP - Both domains gated ===");
        $toggle_start();

        // Gate both compute domains
        sleep_alu <= 1'b1; @(posedge clk); sleep_alu <= 1'b0;
        sleep_mac <= 1'b1; @(posedge clk); sleep_mac <= 1'b0;

        wait (!alu_active && !mac_active);
        $display("[%0t] Both domains gated. Minimum leakage period...", $time);
        repeat (200) @(posedge clk);  // 200 cycles at minimum power

        // Wake both
        wake_alu <= 1'b1; @(posedge clk); wake_alu <= 1'b0;
        wake_mac <= 1'b1; @(posedge clk); wake_mac <= 1'b0;
        wait (alu_active && mac_active);
        repeat(10) @(posedge clk);

        $toggle_stop();
        $toggle_report("saif/phase4_deep_sleep.saif", 1'b1, "tb_top_soc.dut");

        // ============================================
        // PHASE 5: ALL TECHNIQUES COMBINED
        // Realistic workload with power management
        // ============================================
        $display("\n=== PHASE 5: ALL TECHNIQUES COMBINED ===");
        $toggle_start();

        repeat (20) begin : workload_loop
            // Active burst - smart clock gating active
            run_alu_workload(25, 1);   // add-heavy -> mult,logic,shift gated
            run_mac_workload(25);
            // Sleep between bursts
            power_gate_alu();
            wake_alu_domain();
        end

        $toggle_stop();
        $toggle_report("saif/phase5_combined.saif", 1'b1, "tb_top_soc.dut");

        $display("\n=== SIMULATION COMPLETE ===");
        $display("SAIFs generated for Voltus analysis in ./saif/");
        $finish;
    end

    // ------------------------------------------------
    // POWER MONITOR: Log domain activity
    // ------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            $fwrite(32'h8000_0002, 
                "%0t,alu_active=%b,mac_active=%b,opcode=%h,valid=%b\n",
                $time, alu_active, mac_active, opcode, valid);
        end
    end

    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * 100000);
        $display("TIMEOUT");
        $finish;
    end

endmodule
