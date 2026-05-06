# genus_run.tcl
# Cadence Genus Synthesis with Low Power Features
# Covers clock gating + multi-threshold + UPF integration

# ============================================================
# SETUP
# ============================================================
set_db init_lib_search_path  { ./lib/slow ./lib/fast ./lib/typical }
set_db init_hdl_search_path  { ./rtl }

# Use multi-VT library (book Section 2.4)
# HVT for non-critical paths, LVT only where timing demands
read_libs {
    slow/tcbn28hpcplusbwp30p140hvtssg0p81v125c.lib
    slow/tcbn28hpcplusbwp30p140lvtssg0p81v125c.lib
    slow/tcbn28hpcplusbwp30p140svtssg0p81v125c.lib
    fast/tcbn28hpcplusbwp30p140hvtff0p88v-40c.lib
    fast/tcbn28hpcplusbwp30p140lvtff0p88v-40c.lib
    typical/tcbn28hpcplusbwp30p140hvttt0p8v25c.lib
    typical/tcbn28hpcplusbwp30p140lvttt0p8v25c.lib
}

# ============================================================
# READ DESIGN
# ============================================================
read_hdl { 
    rtl/alu_core.v 
    rtl/mac_unit.v 
    rtl/power_controller.v 
    rtl/top_soc.v 
}

# Load UPF power intent
read_power_intent -1801 ./upf/top_soc.upf
apply_power_intent

elaborate top_soc
check_design -unresolved

# ============================================================
# CONSTRAINTS
# ============================================================
read_sdc ./constraints/top_soc.sdc

# ============================================================
# LOW POWER SETTINGS
# ============================================================

# Enable automatic clock gating (book Section 2.1)
# Genus identifies EN-controlled registers and inserts ICG cells
set_db lp_insert_clock_gating          true
set_db lp_clock_gating_prefix          "CG_"
set_db lp_clock_gating_min_flops       3     ;# book recommendation: >=3 bits
set_db lp_clock_gating_max_fanout      64
set_db lp_clock_gating_style           latch ;# latch-based ICG

# Multi-VT optimization (book Section 2.4)
# Start HVT, swap to LVT only on critical paths
set_db lp_multi_vt_optimization_effort high
set_db lp_insert_clock_gating_incremental true

# Power domain handling
set_db lp_power_unit  mW
set_db lp_voltage_unit V

# Isolation cell handling
set_db lp_isolation_cell_always_on_power_pin VDDG

# Retention register preference
# Genus will select from lib retention cells
set_db lp_retention_register_prefix "RET_"

# ============================================================
# SYNTHESIS FLOW
# ============================================================

# Step 1: Generic synthesis
syn_generic

# Step 2: Technology mapping with power optimization
# -effort high activates multi-VT swapping
syn_map -effort high

# Step 3: Insert isolation cells per UPF
# Genus reads set_isolation commands and inserts AND/OR clamp cells
commit_power_intent

# Step 4: Insert retention registers per UPF
# Genus replaces target flops with retention register library cells
# (cells have extra VDDG, VSSG, SAVE, RESTORE pins)

# Step 5: Incremental optimization
# Optimize power while maintaining timing
set_db optimize_power_effort high

syn_opt -effort high

# ============================================================
# REPORTS: Before vs After Low Power Techniques
# ============================================================

# Power report - Total
report_power -hierarchy -levels 3 \
    > ./reports/power_all_on.rpt

# Power report per domain
report_power -power_domain PDsoc > ./reports/power_domain_soc.rpt
report_power -power_domain PDalu > ./reports/power_domain_alu.rpt
report_power -power_domain PDmac > ./reports/power_domain_mac.rpt

# Clock gating effectiveness report
report_clock_gating                    > ./reports/clock_gating.rpt
report_clock_gating -summary           > ./reports/clock_gating_summary.rpt

# Multi-VT usage
report_cell -all -sort_by leakage_power > ./reports/cell_vt_usage.rpt
report_threshold_voltage_group          > ./reports/vt_groups.rpt

# Timing
report_timing -nworst 5                > ./reports/timing.rpt

# Area
report_area                            > ./reports/area.rpt

# ============================================================
# WRITE OUTPUTS
# ============================================================
write_hdl  > ./netlist/top_soc_netlist.v
write_sdf  > ./netlist/top_soc.sdf
write_sdc  > ./netlist/top_soc_synth.sdc

# Write UPF with committed power intent (for Voltus)
write_power_intent -1801 -out ./netlist/top_soc_pg.upf
