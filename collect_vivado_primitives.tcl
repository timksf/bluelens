#!/usr/bin/env vivado

# Copyright (c) 2026 Tim
# SPDX-License-Identifier: MIT
#
# Export leaf Vivado primitive cells as a small TSV file.  The companion
# report_bsv_utilization.tcl script folds these cells into BlueTcl hierarchy.

proc usage {} {
    puts stderr "usage: collect_vivado_primitives.tcl ?options?"
    puts stderr "  --dcp FILE       open this checkpoint before collecting cells"
    puts stderr "  --out FILE       output TSV (default: vivado_primitives.tsv)"
    puts stderr "  --root PATH      restrict cells to a Vivado hierarchy path"
    puts stderr "  --help           show this message"
    exit 2
}

array set opt [list \
    dcp {} \
    out vivado_primitives.tsv \
    root {}]

for {set i 0} {$i < [llength $argv]} {incr i} {
    set arg [lindex $argv $i]
    if {$arg eq "--help" || $arg eq "-h"} {
        usage
    }
    if {$i + 1 >= [llength $argv]} {
        usage
    }
    incr i
    set value [lindex $argv $i]
    switch -- $arg {
        --dcp  { set opt(dcp) [file normalize $value] }
        --out  { set opt(out) [file normalize $value] }
        --root { set opt(root) [string trim $value /] }
        default { usage }
    }
}

proc classify_ref {ref_name} {
    if {[regexp {^(FD|LD|RAMD|RAMS|SRL)} $ref_name]} {
        if {[regexp {^(FD|LD)} $ref_name]} {
            return "Flop & Latch"
        }
        return "Distributed Memory"
    }
    if {[string match {LUT*} $ref_name]} {
        return LUT
    }
    if {[string match {CARRY*} $ref_name]} {
        return CarryLogic
    }
    if {[string match {MUXF*} $ref_name]} {
        return MuxFx
    }
    if {[regexp {^(RAMB|FIFO[0-9])} $ref_name]} {
        return "Block Memory"
    }
    if {[string match {DSP*} $ref_name]} {
        return "Block Arithmetic"
    }
    if {[regexp {^(IBUF|OBUF|IOBUF|IDELAY|ODELAY|ILOGIC|OLOGIC)} $ref_name]} {
        return IO
    }
    if {[regexp {^(BUF|BUFG|BUFH|BUFIO|BUFR|MMCM|PLLE)} $ref_name]} {
        return Clock
    }
    return Others
}

proc skip_ref {ref_name} {
    if {$ref_name eq "GND" || $ref_name eq "VCC"} {
        return 1
    }
    if {[regexp {^RAM(16|32|64)} $ref_name]} {
        return 1
    }
    return 0
}

proc cell_ref_name {cell} {
    set ref [get_property REF_NAME $cell]
    if {$ref eq ""} {
        set ref [get_property PRIMITIVE_TYPE $cell]
    }
    if {$ref eq ""} {
        set ref UNKNOWN
    }
    return $ref
}

if {$opt(dcp) ne ""} {
    if {![file exists $opt(dcp)]} {
        error "checkpoint not found: $opt(dcp)"
    }
    open_checkpoint $opt(dcp)
}

set cells [get_cells -hierarchical -filter {IS_PRIMITIVE}]
file mkdir [file dirname $opt(out)]
set fd [open $opt(out) w]
fconfigure $fd -translation lf
puts $fd "# bluelens-vivado-primitives-v1"
if {$opt(dcp) ne ""} {
    puts $fd "# dcp\t$opt(dcp)"
}
if {$opt(root) ne ""} {
    puts $fd "# root\t$opt(root)"
}
puts $fd "cell_path\tref_name\tcategory"

set written 0
foreach cell [lsort $cells] {
    set path [string trim $cell /]
    if {$opt(root) ne "" &&
        $path ne $opt(root) &&
        ![string match "$opt(root)/*" $path]} {
        continue
    }
    set ref [cell_ref_name $cell]
    if {[skip_ref $ref]} {
        continue
    }
    puts $fd "$path\t$ref\t[classify_ref $ref]"
    incr written
}
close $fd

puts "Wrote $opt(out)"
puts "Exported $written primitive cells"
