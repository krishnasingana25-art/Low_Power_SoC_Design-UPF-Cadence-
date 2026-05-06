# voltus_run.tcl
# Cadence Voltus Power Analysis
# Compares power across all 5 scenarios

# ============================================================
# SETUP
# ============================================================
set design_name "top_soc"

read_netlist   ./netlist/top_soc_netlist.v  -top $design_name
read_power_intent -1801 ./netlist/top_soc_pg.upf
read_sdc       ./netlist/top_soc_synth.sdc
read_spef      ./netlist/top_soc.spef       ;# parasitics

# Supply voltages matching UPF
set_power_analysis_mode \
    -method      dynamic_vectorbased \
    -corner      slow

read_activity_file \
    -format saif \
    -scope  tb_top_soc/dut \
    ./saif/phase1_baseline.saif

# ============================================================
# ANALYSIS SCENARIOS
# ============================================================

proc run_voltus_scenario { phase_name saif_file } {
    global design_name

    puts "\n=== Voltus: $phase_name ==="

    # Load activity
    read_activity_file \
        -format saif \
        -scope  tb_top_soc/dut \
        $saif_file

    # Set power domain voltages
    # Domain A always on
    set_voltage 0.8  -object_list VDD_SOC
    set_voltage 0.0  -object_list VSS

    # Domains B and C: 0.8V when on, 0.0V when gated
    # Voltus reads PST + UPF to determine state per cycle
    set_voltage 0.8  -object_list VDD_ALU
    set_voltage 0.8  -object_list VDD_MAC

    # --------------------------------------------------------
    # RUN POWER ANALYSIS
    # --------------------------------------------------------
    run_power_analysis \
        -save_directory ./voltus_results/$phase_name

    # --------------------------------------------------------
    # REPORTS
    # --------------------------------------------------------
    set rpt_dir "./reports/voltus/$phase_name"
    exec mkdir -p $rpt_dir

    # Hierarchical power breakdown
    report_power \
        -hierarchy all \
        -levels 4 \
        -outfile ${rpt_dir}/power_hier.rpt

    # Per power-domain breakdown (key metric)
    report_power \
        -power_domain PDsoc \
        -outfile ${rpt_dir}/power_PDsoc.rpt

    report_power \
        -power_domain PDalu \
        -outfile ${rpt_dir}/power_PDalu.rpt

    report_power \
        -power_domain PDmac \
        -outfile ${rpt_dir}/power_PDmac.rpt

    # Component breakdown: internal/switching/leakage
    report_power \
        -by_power_type \
        -outfile ${rpt_dir}/power_by_type.rpt

    # Clock network power
    report_power \
        -clock_network \
        -outfile ${rpt_dir}/power_clock.rpt

    # Leakage only report (critical for gated domains)
    report_power \
        -leakage_only \
        -outfile ${rpt_dir}/leakage.rpt

    puts "Reports written to $rpt_dir"
}

# ============================================================
# RUN ALL 5 SCENARIOS
# ============================================================

run_voltus_scenario "phase1_baseline"      ./saif/phase1_baseline.saif
run_voltus_scenario "phase2_clock_gating"  ./saif/phase2_clock_gating.saif
run_voltus_scenario "phase3_power_gate"    ./saif/phase3_power_gate_alu.saif
run_voltus_scenario "phase4_deep_sleep"    ./saif/phase4_deep_sleep.saif
run_voltus_scenario "phase5_combined"      ./saif/phase5_combined.saif

# ============================================================
# SUMMARY COMPARISON TABLE
# ============================================================
set summary [open "./reports/POWER_SUMMARY.csv" w]
puts $summary "Phase,Scenario,Dynamic_mW,Leakage_uW,Clock_mW,Total_mW"

foreach {phase desc} {
    phase1_baseline      "No techniques"
    phase2_clock_gating  "Clock gating only"
    phase3_power_gate    "Power gating ALU"
    phase4_deep_sleep    "Both domains gated"
    phase5_combined      "All techniques"
} {
    # Parse power report (example - actual parsing depends on report format)
    set rpt [open "./reports/voltus/$phase/power_by_type.rpt" r]
    set content [read $rpt]; close $rpt

    # Extract values with regexp (adapt to actual Voltus output format)
    regexp {Total\s+Dynamic\s+([\d.]+)} $content -> dyn
    regexp {Total\s+Leakage\s+([\d.]+)} $content -> leak
    regexp {Clock\s+Network\s+([\d.]+)} $content -> clk

    puts $summary "$phase,$desc,$dyn,$leak,$clk,[expr {$dyn + $leak}]"
}
close $summary

puts "\n=== Power Summary written to ./reports/POWER_SUMMARY.csv ==="
