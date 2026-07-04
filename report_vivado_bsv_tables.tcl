#!/usr/bin/env vivado

# Copyright (c) 2026 Tim
# SPDX-License-Identifier: MIT
#
# Render Vivado report_utilization tables for BSV hierarchy selections emitted
# by report_bsv_utilization.tcl --vivado-plan.

proc usage {} {
    puts stderr "usage: report_vivado_bsv_tables.tcl ?options?"
    puts stderr "  --dcp FILE          open this checkpoint before reporting"
    puts stderr "  --plan FILE         BSV/Vivado plan from report_bsv_utilization.tcl"
    puts stderr "  --out FILE          Markdown output (default: bsv_vivado_tables.md)"
    puts stderr "  --sections LIST     comma list of section names, or all"
    puts stderr "                      default: Slice Logic,Memory,DSP,Primitives"
    puts stderr "  --help              show this message"
    exit 2
}

array set opt [list \
    dcp {} \
    plan {} \
    out bsv_vivado_tables.md \
    sections {Slice Logic,Memory,DSP,Primitives}]

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
        --dcp      { set opt(dcp) [file normalize $value] }
        --plan     { set opt(plan) [file normalize $value] }
        --out      { set opt(out) [file normalize $value] }
        --sections { set opt(sections) $value }
        default    { usage }
    }
}

if {$opt(plan) eq "" || ![file exists $opt(plan)]} {
    error "plan file not found: $opt(plan)"
}
if {$opt(dcp) ne ""} {
    if {![file exists $opt(dcp)]} {
        error "checkpoint not found: $opt(dcp)"
    }
    open_checkpoint $opt(dcp)
}

proc parse_sections {sections} {
    if {[string tolower $sections] eq "all"} {
        return all
    }
    set selected {}
    foreach item [split $sections ,] {
        set item [string trim $item]
        if {$item ne ""} {
            lappend selected $item
        }
    }
    return $selected
}

proc section_selected {name selected} {
    if {$selected eq "all"} {
        return 1
    }
    foreach item $selected {
        if {[string equal -nocase $name $item]} {
            return 1
        }
    }
    return 0
}

proc extract_sections {report selected} {
    if {$selected eq "all"} {
        return [string trim $report]
    }
    set kept {}
    set keep 0
    set lines [split $report \n]
    for {set i 0} {$i < [llength $lines]} {incr i} {
        set line [lindex $lines $i]
        set next {}
        if {$i + 1 < [llength $lines]} {
            set next [lindex $lines [expr {$i + 1}]]
        }
        if {[regexp {^[0-9]+\. ([^-].*)$} $line -> title] &&
            [regexp {^-+$} $next]} {
            set keep [section_selected [string trim $title] $selected]
        }
        if {$keep} {
            lappend kept $line
        }
    }
    return [string trim [join $kept \n]]
}

proc markdown_escape {text} {
    regsub -all {`} $text {\\`} text
    return $text
}

proc read_plan {filename} {
    set fd [open $filename r]
    set rows {}
    set header_seen 0
    while {[gets $fd line] >= 0} {
        if {$line eq "" || [string match "#*" $line]} {
            continue
        }
        if {!$header_seen} {
            set header_seen 1
            continue
        }
        set fields [split $line \t]
        if {[llength $fields] < 4} {
            continue
        }
        lappend rows [list \
            [lindex $fields 0] \
            [lindex $fields 1] \
            [lindex $fields 2] \
            [lindex $fields 3]]
    }
    close $fd
    return $rows
}

set selected_sections [parse_sections $opt(sections)]
set rows [read_plan $opt(plan)]

file mkdir [file dirname $opt(out)]
set fd [open $opt(out) w]
fconfigure $fd -translation lf

puts $fd "# BSV Vivado Utilization Tables"
puts $fd ""
puts $fd "- Plan: `$opt(plan)`"
if {$opt(dcp) ne ""} {
    puts $fd "- Checkpoint: `$opt(dcp)`"
}
puts $fd "- Sections: `$opt(sections)`"
puts $fd "- Modules: [llength $rows]"

puts $fd ""
puts $fd "## Module Summary"
puts $fd ""
puts $fd "| BSV Path | Direct | Total | Cells |"
puts $fd "|---|---:|---:|---:|"
foreach row $rows {
    lassign $row path direct total cell_list
    puts $fd "| `[markdown_escape $path]` | $direct | $total | [llength $cell_list] |"
}

foreach row $rows {
    lassign $row path direct total cell_list
    set cells [get_cells -quiet $cell_list]
    puts $fd ""
    puts $fd "## `[markdown_escape $path]`"
    puts $fd ""
    puts $fd "- Direct primitives: $direct"
    puts $fd "- Total primitives including descendants: $total"
    puts $fd "- Vivado cells reported: [llength $cells]"
    if {[llength $cells] == 0} {
        puts $fd ""
        puts $fd "_No Vivado cells found for this selection._"
        continue
    }
    set report [report_utilization -cells $cells -return_string]
    set extracted [extract_sections $report $selected_sections]
    if {$extracted eq ""} {
        set extracted [string trim $report]
    }
    puts $fd ""
    puts $fd "```text"
    puts $fd $extracted
    puts $fd "```"
}

close $fd
puts "Wrote $opt(out)"
puts "Reported [llength $rows] BSV modules"
