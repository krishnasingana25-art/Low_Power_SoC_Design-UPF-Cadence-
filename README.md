Low Power SoC Design and Power Analysis using Cadence Genus & Voltus
Overview

This project demonstrates the implementation and analysis of low-power techniques in a small SoC design using Cadence EDA tools. The design includes multiple power domains, clock gating, power gating, isolation, retention registers, and UPF-based power intent modeling. Power consumption is analyzed across multiple operating scenarios using Voltus with VCD-based switching activity.

The goal of the project is to study and compare dynamic and leakage power reduction techniques at the RTL and gate-level implementation stages.

Features Implemented
Multi-power-domain SoC architecture
Clock gating for dynamic power reduction
Power gating using UPF power switches
Isolation cells for powered-down domains
Retention register modeling
UPF-based power intent integration
Gate-level synthesis using Cadence Genus
Vector-based power analysis using Cadence Voltus
VCD-driven switching activity analysis
Comparative power analysis across different low-power modes
SoC Architecture

The SoC contains the following major blocks:

ALU Core
MAC Unit
Power Controller
Top-Level SoC Integration

Power domains:

PDsoc → Always-on domain
PDalu → Power-gated ALU domain
PDmac → Power-gated MAC domain with retention
Low Power Techniques Used
1. Clock Gating

Clock gating is applied to reduce unnecessary switching activity in sequential logic by disabling clock propagation when computation is inactive.

Implemented using:

Gated clock generation
Activity-based enable control
2. Power Gating

Power gating is implemented using UPF power switches to completely shut down inactive domains and reduce leakage power.

Features:

Independent ALU power gating
MAC deep-sleep mode
Sleep/Wake control signals
3. Isolation Cells

Isolation logic clamps outputs of powered-down domains to prevent invalid signal propagation into active domains.

Clamp strategy:

Clamp-to-zero
4. Retention Registers

Retention logic preserves critical register values during power collapse for faster wake-up operation.

Implemented for:

MAC accumulator registers
Tool Flow
RTL Design
Verilog HDL
Synthesis
Cadence Genus
Power Intent
IEEE 1801 UPF
Simulation
Cadence Xcelium
Power Analysis
Cadence Voltus


low_power/
│
├── rtl/
│   ├── alu_core.v
│   ├── mac_unit.v
│   ├── power_controller.v
│   ├── top_soc.v
│   └── icg_stub.v
│
├── tb/
│   └── tb_top_soc.v
│
├── scripts/
│   ├── genus_run.tcl
│   ├── voltus_run.tcl
│   └── netlists/
│
├── vcd/
│   ├── baseline.vcd
│   ├── clock.vcd
│   └── power.vcd
│
├── reports/
│
└── voltus_results/
