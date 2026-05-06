# top_soc.sdc
# Synopsys Design Constraints for top_soc
# Multi-voltage, Multi-domain, Power-gated design
# Used by Genus (synthesis) and Tempus (signoff)

# ============================================================
# STEP 1: UNITS
# ============================================================
set_units \
    -time       ns \
    -capacitance pf \
    -resistance  kohm \
    -voltage     V \
    -current     mA

# ============================================================
# STEP 2: CLOCK DEFINITION
# ============================================================
# Primary system clock - 100MHz
# Period = 10ns
# Drives Domain A (controller) directly
# Distributed to Domain B and C through ICG cells

create_clock \
    -name   clk_sys \
    -period 10.0 \
    -waveform {0 5.0} \
    [get_ports clk]

# Clock uncertainty
# Accounts for jitter and skew
# Tighter for setup (0.2ns), relaxed for hold (0.1ns)
set_clock_uncertainty \
    -setup 0.2 \
    [get_clocks clk_sys]

set_clock_uncertainty \
    -hold  0.1 \
    [get_clocks clk_sys]

# Clock transition (rise/fall time at source)
set_clock_transition \
    -rise 0.1 \
    -fall 0.1 \
    [get_clocks clk_sys]

# Clock latency (insertion delay from port to first flop)
# Estimated before CTS, removed after CTS
set_clock_latency \
    -source 0.5 \
    [get_clocks clk_sys]

# ============================================================
# STEP 3: GENERATED CLOCKS
# Gated clocks for each ALU functional unit
# Generated from clk_sys through ICG cells
# Each has additional ICG cell delay (~0.1ns)
# ============================================================

# Adder unit gated clock
create_generated_clock \
    -name    clk_adder \
    -source  [get_ports clk] \
    -divide_by 1 \
    -master_clock clk_sys \
    [get_pins u_alu/icg_adder/GCLK]

# Multiplier unit gated clock
create_generated_clock \
    -name    clk_mult \
    -source  [get_ports clk] \
    -divide_by 1 \
    -master_clock clk_sys \
    [get_pins u_alu/icg_mult/GCLK]

# Logic unit gated clock
create_generated_clock \
    -name    clk_logic \
    -source  [get_ports clk] \
    -divide_by 1 \
    -master_clock clk_sys \
    [get_pins u_alu/icg_logic/GCLK]

# Shift unit gated clock
create_generated_clock \
    -name    clk_shift \
    -source  [get_ports clk] \
    -divide_by 1 \
    -master_clock clk_sys \
    [get_pins u_alu/icg_shift/GCLK]

# MAC accumulator gated clock
create_generated_clock \
    -name    clk_acc \
    -source  [get_ports clk] \
    -divide_by 1 \
    -master_clock clk_sys \
    [get_pins u_mac/icg_acc/GCLK]

# ============================================================
# STEP 4: CLOCK GROUPS
# Gated clocks are not independent of master
# Tell STA they share the same source - no false paths
# between domains clocked by same master
# ============================================================
set_clock_groups \
    -name          cg_alu_units \
    -physically_exclusive \
    -group         {clk_adder} \
    -group         {clk_mult} \
    -group         {clk_logic} \
    -group         {clk_shift}

# MAC clock is logically exclusive with ALU clocks
# (different power domains, different voltage areas)
set_clock_groups \
    -name          cg_domains \
    -logically_exclusive \
    -group         {clk_sys} \
    -group         {clk_acc}

# ============================================================
# STEP 5: INPUT DELAYS
# Delay from external source to input port
# Assumes upstream logic has 40% of clock period delay
# ============================================================
set input_delay_val  4.0   ;# 40% of 10ns period

# Data inputs
set_input_delay \
    -clock clk_sys \
    -max   $input_delay_val \
    [get_ports {op_a op_b opcode valid accumulate clear_acc}]

set_input_delay \
    -clock clk_sys \
    -min   0.5 \
    [get_ports {op_a op_b opcode valid accumulate clear_acc}]

# Power control inputs
# These are quasi-static signals - relaxed timing
set_input_delay \
    -clock clk_sys \
    -max   6.0 \
    [get_ports {sleep_alu sleep_mac wake_alu wake_mac}]

set_input_delay \
    -clock clk_sys \
    -min   0.5 \
    [get_ports {sleep_alu sleep_mac wake_alu wake_mac}]

# Reset - asynchronous, constrain recovery/removal
set_input_delay \
    -clock clk_sys \
    -max   1.0 \
    [get_ports rst_n]

# ============================================================
# STEP 6: OUTPUT DELAYS
# Delay budget for downstream logic after output port
# Assumes downstream needs 40% of period
# ============================================================
set output_delay_val 4.0

# ALU outputs
set_output_delay \
    -clock clk_sys \
    -max   $output_delay_val \
    [get_ports {alu_out alu_valid}]

set_output_delay \
    -clock clk_sys \
    -min   0.5 \
    [get_ports {alu_out alu_valid}]

# MAC outputs
set_output_delay \
    -clock clk_sys \
    -max   $output_delay_val \
    [get_ports {mac_out mac_valid}]

set_output_delay \
    -clock clk_sys \
    -min   0.5 \
    [get_ports {mac_out mac_valid}]

# Status outputs - relaxed, quasi-static
set_output_delay \
    -clock clk_sys \
    -max   6.0 \
    [get_ports {alu_active mac_active}]

# ============================================================
# STEP 7: INPUT/OUTPUT DRIVE AND LOAD
# Model external driver strength and output load
# ============================================================

# Input drive strength
# Model as driving strength of X4 buffer
set_driving_cell \
    -lib_cell  BUFX4_HVT \
    -pin       Y \
    [get_ports {op_a op_b opcode valid accumulate clear_acc}]

set_driving_cell \
    -lib_cell  BUFX2_HVT \
    -pin       Y \
    [get_ports {sleep_alu sleep_mac wake_alu wake_mac rst_n}]

# Output load
# Model as 4 standard inputs + 50fF interconnect
set_load \
    -pin_load 0.05 \
    [get_ports {alu_out alu_valid mac_out mac_valid alu_active mac_active}]

# ============================================================
# STEP 8: TIMING EXCEPTIONS
# False paths and multicycle paths
# ============================================================

# --- FALSE PATHS ---

# Power control signals are quasi-static
# No meaningful timing path through them during normal operation
set_false_path \
    -from [get_ports {sleep_alu sleep_mac wake_alu wake_mac}]

# Asynchronous reset - false path for setup
# Recovery/removal checked separately
set_false_path \
    -from [get_ports rst_n]

# False path from always-on domain to powered-down domain outputs
# When domain is off, isolation clamps outputs - no real timing path
set_false_path \
    -from [get_cells u_ctrl/*] \
    -to   [get_ports {alu_out alu_valid}] \
    -through [get_cells iso_alu*]

set_false_path \
    -from [get_cells u_ctrl/*] \
    -to   [get_ports {mac_out mac_valid}] \
    -through [get_cells iso_mac*]

# Cross-domain paths through isolation cells
# Isolation output is clamped - not a real functional path
set_false_path \
    -from [get_cells u_alu/*] \
    -to   [get_cells u_mac/*]

set_false_path \
    -from [get_cells u_mac/*] \
    -to   [get_cells u_alu/*]

# Retention control path - nretain is asynchronous pulse
# Not clocked - no setup/hold applies
set_false_path \
    -from [get_pins u_ctrl/nretain_mac] \
    -to   [get_pins u_mac/shadow_accumulator*]

# --- MULTICYCLE PATHS ---

# Multiplier is 4-stage pipelined
# Result valid after 4 cycles - 4-cycle multicycle path
set_multicycle_path 4 \
    -setup \
    -from [get_cells u_alu/mult_pipe*] \
    -to   [get_cells u_alu/mult_result*]

set_multicycle_path 3 \
    -hold \
    -from [get_cells u_alu/mult_pipe*] \
    -to   [get_cells u_alu/mult_result*]

# Power controller state machine
# State transitions are quasi-static (many cycles between transitions)
# Allow 2 cycles for state decode logic
set_multicycle_path 2 \
    -setup \
    -from [get_cells u_ctrl/alu_state*] \
    -to   [get_cells u_ctrl/pg_req_alu*]

set_multicycle_path 1 \
    -hold \
    -from [get_cells u_ctrl/alu_state*] \
    -to   [get_cells u_ctrl/pg_req_alu*]

set_multicycle_path 2 \
    -setup \
    -from [get_cells u_ctrl/mac_state*] \
    -to   [get_cells u_ctrl/pg_req_mac*]

set_multicycle_path 1 \
    -hold \
    -from [get_cells u_ctrl/mac_state*] \
    -to   [get_cells u_ctrl/pg_req_mac*]

# ============================================================
# STEP 9: MULTI-VOLTAGE TIMING DERATING
# Accounts for IR drop across header switch network
# Cells in power-gated domains see slightly lower VDD
# Derate their timing by 5-10% (book Chapter 12)
# ============================================================

# Domain B (ALU) - 5% IR drop derating on cell delays
set_timing_derate \
    -cell_delay \
    -data \
    -late  1.05 \
    -early 0.95 \
    [get_cells u_alu/*]

# Domain C (MAC) - 5% IR drop derating
set_timing_derate \
    -cell_delay \
    -data \
    -late  1.05 \
    -early 0.95 \
    [get_cells u_mac/*]

# Level shifter derating
# Low-to-high shifters add significant delay
# Derate more aggressively at domain boundaries
set_timing_derate \
    -cell_delay \
    -late  1.10 \
    [get_cells *ls_alu* *ls_mac*]

# ============================================================
# STEP 10: CLOCK GATING CHECK CONSTRAINTS
# ICG cell enable must be stable before clock rises
# and held after clock falls
# ============================================================
set_clock_gating_check \
    -setup 0.3 \
    -hold  0.1 \
    [get_cells u_alu/icg_*]

set_clock_gating_check \
    -setup 0.3 \
    -hold  0.1 \
    [get_cells u_mac/icg_*]

# ============================================================
# STEP 11: CASE ANALYSIS FOR POWER STATES
# Tell STA which signals are constant in each mode
# Matches PST states defined in UPF
# Run separate analyses per power state
# ============================================================

# --- Mode 1: All ON (normal operation) ---
# No case analysis needed - all paths active

# --- Mode 2: ALU power gated (alu_off state) ---
# pg_req_alu is constant 1 - iso_alu is constant 1
# All paths through ALU are inactive
# Use this when running STA for mac_off PST state

# Uncomment for per-mode STA run:
# set_case_analysis 1 [get_pins u_ctrl/pg_req_alu]
# set_case_analysis 1 [get_pins u_ctrl/iso_alu]
# set_case_analysis 0 [get_pins u_ctrl/alu_adder_en]
# set_case_analysis 0 [get_pins u_ctrl/alu_mult_en]
# set_case_analysis 0 [get_pins u_ctrl/alu_logic_en]
# set_case_analysis 0 [get_pins u_ctrl/alu_shift_en]

# --- Mode 3: MAC power gated ---
# set_case_analysis 1 [get_pins u_ctrl/pg_req_mac]
# set_case_analysis 1 [get_pins u_ctrl/iso_mac]

# ============================================================
# STEP 12: RESET RECOVERY AND REMOVAL
# Asynchronous reset timing constraints
# Recovery = like setup for async signals
# Removal  = like hold for async signals
# ============================================================
set_max_delay \
    -datapath_only 2.0 \
    -from [get_ports rst_n] \
    -to   [get_pins u_ctrl/rst_n]

set_min_delay 0.3 \
    -from [get_ports rst_n] \
    -to   [get_pins u_ctrl/rst_n]

# ============================================================
# STEP 13: DESIGN RULE CONSTRAINTS
# Maximum transition and capacitance limits
# ============================================================

# Maximum transition time on all nets
set_max_transition \
    0.3 \
    [current_design]

# Tighter transition on clock nets
set_max_transition \
    0.15 \
    [get_clocks *]

# Maximum capacitance per net
set_max_capacitance \
    0.2 \
    [current_design]

# Maximum fanout
set_max_fanout \
    32 \
    [current_design]

# Tighter fanout on always-on control nets
# (isolation, retention, power gate control)
set_max_fanout \
    16 \
    [get_nets {*iso* *pg_req* *nretain*}]

# ============================================================
# STEP 14: OPERATING CONDITIONS
# Worst case for setup, best case for hold
# ============================================================
set_operating_conditions \
    -max slow_125c_0p81v \
    -min fast_m40c_0p88v

# ============================================================
# STEP 15: REPORT SDC SUMMARY
# ============================================================
puts "\n=== SDC Summary ==="
puts "Primary Clock  : clk_sys 100MHz (10ns period)"
puts "Gated Clocks   : clk_adder clk_mult clk_logic clk_shift clk_acc"
puts "Input Delay    : 4.0ns (40% of period)"
puts "Output Delay   : 4.0ns (40% of period)"
puts "IR Derating    : 5% on PDalu PDmac, 10% on level shifters"
puts "Multicycle     : 4-cycle on multiplier pipeline"
puts "False Paths    : power control, cross-domain, retention signals"
puts "=== SDC Load Complete ==="
