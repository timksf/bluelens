#!/usr/bin/env bluetcl

# Copyright (c) 2026 Tim
# SPDX-License-Identifier: MIT
#
# Join a Vivado primitive-cell export with BlueTcl hierarchy and write a
# compact per-module utilization collection.

proc usage {} {
    puts stderr "usage: report_bsv_utilization.tcl ?options?"
    puts stderr "  --top MODULE          elaborated BSV top (default: mkTop)"
    puts stderr "  --build DIR           BlueTcl .bo/.ba directory (default: build)"
    puts stderr "  --vivado-cells FILE   TSV from collect_vivado_primitives.tcl"
    puts stderr "  --out FILE            Markdown report (default: bsv_utilization.md)"
    puts stderr "  --vivado-plan FILE    write BSV module to Vivado cell-list plan TSV"
    puts stderr "  --vivado-root PATH    Vivado instance matching the BSV top"
    puts stderr "  --include GLOB        BSV module path glob; may be repeated"
    puts stderr "  --min-total N         omit modules below total primitive count (default: 1)"
    puts stderr "  --max-depth N         omit modules deeper than this BSV path depth"
    puts stderr "  --show-direct         include direct-only primitive tables"
    puts stderr "  --show-empty          include selected modules with zero matched cells"
    puts stderr "  --mode MODE           BlueTcl mode: verilog or sim (default: verilog)"
    puts stderr "  --help                show this message"
    exit 2
}

set script_dir [file dirname [file normalize [info script]]]
set project_dir [pwd]
array set opt [list \
    top mkTop \
    build [file join $project_dir build] \
    vivado_cells {} \
    out [file join $project_dir bsv_utilization.md] \
    vivado_plan {} \
    vivado_root {} \
    min_total 1 \
    max_depth {} \
    show_direct 0 \
    show_empty 0 \
    mode verilog]
set include_globs {}
lappend auto_path [file join $script_dir vendor bdw]

for {set i 0} {$i < [llength $argv]} {incr i} {
    set arg [lindex $argv $i]
    if {$arg eq "--help" || $arg eq "-h"} {
        usage
    }
    if {$arg eq "--show-empty"} {
        set opt(show_empty) 1
        continue
    }
    if {$arg eq "--show-direct"} {
        set opt(show_direct) 1
        continue
    }
    if {$i + 1 >= [llength $argv]} {
        usage
    }
    incr i
    set value [lindex $argv $i]
    switch -- $arg {
        --top          { set opt(top) $value }
        --build        { set opt(build) [file normalize $value] }
        --vivado-cells { set opt(vivado_cells) [file normalize $value] }
        --out          { set opt(out) [file normalize $value] }
        --vivado-plan  { set opt(vivado_plan) [file normalize $value] }
        --vivado-root  { set opt(vivado_root) [string trim $value /] }
        --include      { lappend include_globs $value }
        --min-total    { set opt(min_total) $value }
        --max-depth    { set opt(max_depth) $value }
        --mode         { set opt(mode) $value }
        default        { usage }
    }
}
if {[llength $include_globs] == 0} {
    set include_globs [list *]
}
if {$opt(vivado_cells) eq ""} {
    usage
}
if {![file exists $opt(vivado_cells)]} {
    error "Vivado cell TSV not found: $opt(vivado_cells)"
}

package require Bluetcl
package require Virtual
namespace import ::Bluetcl::*

switch -- $opt(mode) {
    verilog { flags set -verilog }
    sim     { flags set -sim }
    default { error "unsupported --mode '$opt(mode)': expected verilog or sim" }
}
flags set -p "+:$opt(build)"
module load $opt(top)

proc trim_path {path} {
    set path [string trim $path /]
    if {$path eq ""} {
        return /
    }
    return /$path
}

proc join_vivado_path {root synth_path} {
    set root [string trim $root /]
    set synth [string trim $synth_path /]
    if {$root eq ""} {
        return $synth
    }
    if {$synth eq ""} {
        return $root
    }
    return "$root/$synth"
}

proc parent_path {path} {
    set path [trim_path $path]
    if {$path eq "/"} {
        return {}
    }
    set parts [split [string trim $path /] /]
    if {[llength $parts] <= 1} {
        return /
    }
    return /[join [lrange $parts 0 end-1] /]
}

proc path_selected {path globs} {
    foreach glob $globs {
        if {[string match $glob $path]} {
            return 1
        }
    }
    return 0
}

proc path_depth {path} {
    set path [string trim $path /]
    if {$path eq ""} {
        return 0
    }
    return [llength [split $path /]]
}

proc add_count {array_name path ref category amount} {
    upvar $array_name counts
    set key [list $path $ref $category]
    if {![info exists counts($key)]} {
        set counts($key) 0
    }
    incr counts($key) $amount
}

proc add_total {array_name path amount} {
    upvar $array_name totals
    if {![info exists totals($path)]} {
        set totals($path) 0
    }
    incr totals($path) $amount
}

proc csv_escape {text} {
    regsub -all {\|} $text {\\|} text
    return $text
}

proc read_vivado_cells {filename} {
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
        if {[llength $fields] < 3} {
            continue
        }
        lappend rows [list \
            [string trim [lindex $fields 0] /] \
            [lindex $fields 1] \
            [lindex $fields 2]]
    }
    close $fd
    return $rows
}

array set module_names {}
array set module_kinds {}
array set parent_of {}
array set synth_owner {}
set module_paths {}
set primitive_records {}

foreach inst [Virtual::inst filter *] {
    set kind [$inst kind]
    set bsv [trim_path [$inst path bsv]]
    set synth [trim_path [$inst path synth]]
    set name [$inst name]
    set mod [$inst modname]

    if {$kind eq "Synth" || $kind eq "Inst"} {
        if {![info exists module_names($bsv)]} {
            lappend module_paths $bsv
        }
        set module_names($bsv) $name
        set module_kinds($bsv) $kind
        set parent [parent_path $bsv]
        if {$parent ne ""} {
            set parent_of($bsv) $parent
        }
    } elseif {$kind eq "Prim"} {
        set parent [parent_path $bsv]
        lappend primitive_records [list $bsv $parent \
            [join_vivado_path $opt(vivado_root) $synth] \
            [string trim $synth /] $name $mod]
    }
}

array set primitive_by_vivado {}
array set primitive_by_synth {}
foreach record $primitive_records {
    lassign $record bsv parent vivado synth name mod
    if {$vivado eq "" || $vivado eq $opt(vivado_root)} {
        continue
    }
    if {![info exists primitive_by_vivado($vivado)] ||
        [string length $vivado] >
        [string length [lindex $primitive_by_vivado($vivado) 2]]} {
        set primitive_by_vivado($vivado) $record
    }
    if {$synth ne "" && [string length $synth] >= 4} {
        if {![info exists primitive_by_synth($synth)] ||
            [string length $synth] >
            [string length [lindex $primitive_by_synth($synth) 3]]} {
            set primitive_by_synth($synth) $record
        }
    }
}

array set direct_counts {}
array set total_counts {}
array set direct_totals {}
array set total_totals {}
array set total_cell_paths {}
array set unmatched_counts {}
set unmatched_total 0
set matched_total 0

foreach row [read_vivado_cells $opt(vivado_cells)] {
    lassign $row cell ref category
    set best_key {}
    foreach key [array names primitive_by_vivado] {
        if {$cell eq $key || [string match "$key/*" $cell]} {
            if {$best_key eq "" ||
                [string length $key] > [string length $best_key]} {
                set best_key $key
            }
        }
    }

    set matched_record {}
    if {$best_key eq ""} {
        set local_cell $cell
        if {$opt(vivado_root) ne "" &&
            [string match "$opt(vivado_root)/*" $cell]} {
            set local_cell [string range $cell \
                [expr {[string length $opt(vivado_root)] + 1}] end]
        }
        set best_synth {}
        foreach synth [array names primitive_by_synth] {
            if {[string match "*$synth*" $local_cell]} {
                if {$best_synth eq "" ||
                    [string length $synth] > [string length $best_synth]} {
                    set best_synth $synth
                }
            }
        }
        if {$best_synth ne ""} {
            set matched_record $primitive_by_synth($best_synth)
        } elseif {$opt(vivado_root) ne "" &&
                  ($cell eq $opt(vivado_root) ||
                   [string match "$opt(vivado_root)/*" $cell])} {
            set matched_record [list / / $opt(vivado_root) {} $opt(top) {}]
        } else {
            set key [list $ref $category]
            if {![info exists unmatched_counts($key)]} {
                set unmatched_counts($key) 0
            }
            incr unmatched_counts($key)
            incr unmatched_total
            continue
        }
    } else {
        set matched_record $primitive_by_vivado($best_key)
    }

    lassign $matched_record prim_bsv direct_module vivado synth name mod
    if {$direct_module eq ""} {
        set direct_module /
    }
    add_count direct_counts $direct_module $ref $category 1
    add_total direct_totals $direct_module 1

    set cursor $direct_module
    while {$cursor ne ""} {
        add_count total_counts $cursor $ref $category 1
        add_total total_totals $cursor 1
        lappend total_cell_paths($cursor) $cell
        if {![info exists parent_of($cursor)]} {
            break
        }
        set cursor $parent_of($cursor)
    }
    incr matched_total
}

proc count_rows_for_path {array_name path} {
    upvar $array_name counts
    set rows {}
    foreach key [array names counts] {
        lassign $key key_path ref category
        if {$key_path eq $path} {
            lappend rows [list $ref [set counts($key)] $category]
        }
    }
    return [lsort -integer -decreasing -index 1 $rows]
}

proc write_count_table {fd title rows} {
    puts $fd ""
    puts $fd "### $title"
    if {[llength $rows] == 0} {
        puts $fd ""
        puts $fd "_No matched Vivado primitives._"
        return
    }
    puts $fd ""
    puts $fd "| Ref Name | Used | Functional Category |"
    puts $fd "|---|---:|---|"
    foreach row $rows {
        lassign $row ref used category
        puts $fd "| [csv_escape $ref] | $used | [csv_escape $category] |"
    }
}

file mkdir [file dirname $opt(out)]
set fd [open $opt(out) w]
fconfigure $fd -translation lf

puts $fd "# BSV Vivado Primitive Utilization"
puts $fd ""
puts $fd "- BSV top: `$opt(top)`"
puts $fd "- BlueTcl build: `$opt(build)`"
puts $fd "- Vivado cells: `$opt(vivado_cells)`"
if {$opt(vivado_root) ne ""} {
    puts $fd "- Vivado root: `$opt(vivado_root)`"
}
puts $fd "- Matched primitive cells: $matched_total"
puts $fd "- Unmatched primitive cells: $unmatched_total"

set selected_modules {}
foreach path [lsort -command {apply {{a b} {
    set da [llength [split [string trim $a /] /]]
    set db [llength [split [string trim $b /] /]]
    if {$da != $db} {return [expr {$da - $db}]}
    return [string compare $a $b]
}}} $module_paths] {
    if {![path_selected $path $include_globs]} {
        continue
    }
    if {$opt(max_depth) ne "" && [path_depth $path] > $opt(max_depth)} {
        continue
    }
    set total 0
    if {[info exists total_totals($path)]} {
        set total $total_totals($path)
    }
    if {!$opt(show_empty) && $total < $opt(min_total)} {
        continue
    }
    lappend selected_modules $path
}

puts $fd ""
puts $fd "## Module Summary"
puts $fd ""
puts $fd "| BSV Path | Direct | Total | Kind |"
puts $fd "|---|---:|---:|---|"
foreach path $selected_modules {
    set direct 0
    set total 0
    if {[info exists direct_totals($path)]} {
        set direct $direct_totals($path)
    }
    if {[info exists total_totals($path)]} {
        set total $total_totals($path)
    }
    puts $fd "| `$path` | $direct | $total | $module_kinds($path) |"
}

if {$opt(vivado_plan) ne ""} {
    file mkdir [file dirname $opt(vivado_plan)]
    set plan_fd [open $opt(vivado_plan) w]
    fconfigure $plan_fd -translation lf
    puts $plan_fd "# bluelens-bsv-vivado-report-plan-v1"
    puts $plan_fd "# top\t$opt(top)"
    puts $plan_fd "# build\t$opt(build)"
    if {$opt(vivado_root) ne ""} {
        puts $plan_fd "# vivado_root\t$opt(vivado_root)"
    }
    puts $plan_fd "bsv_path\tdirect_primitives\ttotal_primitives\tcell_paths"
    foreach path $selected_modules {
        set direct 0
        set total 0
        set cells {}
        if {[info exists direct_totals($path)]} {
            set direct $direct_totals($path)
        }
        if {[info exists total_totals($path)]} {
            set total $total_totals($path)
        }
        if {[info exists total_cell_paths($path)]} {
            set cells $total_cell_paths($path)
        }
        puts $plan_fd "$path\t$direct\t$total\t[list {*}$cells]"
    }
    close $plan_fd
    puts "Wrote $opt(vivado_plan)"
}

foreach path $selected_modules {
    set direct 0
    set total 0
    if {[info exists direct_totals($path)]} {
        set direct $direct_totals($path)
    }
    if {[info exists total_totals($path)]} {
        set total $total_totals($path)
    }
    puts $fd ""
    puts $fd "## `$path`"
    puts $fd ""
    puts $fd "- Direct primitives: $direct"
    puts $fd "- Total primitives including descendants: $total"
    write_count_table $fd "Primitive Utilization" \
        [count_rows_for_path total_counts $path]
    if {$opt(show_direct)} {
        write_count_table $fd "Direct By Primitive" \
            [count_rows_for_path direct_counts $path]
    }
}

if {$unmatched_total > 0} {
    puts $fd ""
    puts $fd "## Unmatched Vivado Primitives"
    puts $fd ""
    puts $fd "These cells were outside the selected BSV top or did not match a BlueTcl primitive synthesized path."
    puts $fd ""
    puts $fd "| Ref Name | Used | Functional Category |"
    puts $fd "|---|---:|---|"
    set rows {}
    foreach key [array names unmatched_counts] {
        lassign $key ref category
        lappend rows [list $ref $unmatched_counts($key) $category]
    }
    foreach row [lsort -integer -decreasing -index 1 $rows] {
        lassign $row ref used category
        puts $fd "| [csv_escape $ref] | $used | [csv_escape $category] |"
    }
}

close $fd
puts "Wrote $opt(out)"
puts "Matched $matched_total primitive cells"
puts "Unmatched $unmatched_total primitive cells"
puts "Reported [llength $selected_modules] BSV modules"
