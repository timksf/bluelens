#!/usr/bin/env bluetcl

# Copyright (c) 2026 Tim
# SPDX-License-Identifier: MIT
#
# Add BSV type and hierarchy information to a VCD without changing the
# simulator output.  Aliases and derived fields live below a new top-level
# "bsv" scope; --hide-source removes their original declarations.

proc usage {} {
    puts stderr "usage: annotate_bsv_vcd.tcl ?options?"
    puts stderr "  --top MODULE          elaborated module (default: mkTest)"
    puts stderr "  --build DIR           BlueTcl .bo/.ba directory (default: hdl/build)"
    puts stderr "  --vcd FILE            input VCD (default: hdl/build/dump.vcd)"
    puts stderr "  --out FILE            enriched VCD (default: hdl/build/dump.typed.vcd)"
    puts stderr "  --include GLOB        BSV path glob; may be repeated (default: *)"
    puts stderr "  --hide-source         remove mapped declarations from the source hierarchy"
    exit 2
}

set script_dir [file dirname [file normalize [info script]]]
set project_dir [pwd]
array set opt [list \
    top mkTest \
    build [file join $project_dir hdl build] \
    vcd [file join $project_dir hdl build dump.vcd] \
    out [file join $project_dir hdl build dump.typed.vcd]]
set include_globs {}
set hide_source 0
lappend auto_path [file join $script_dir vendor bdw]

for {set i 0} {$i < [llength $argv]} {incr i} {
    set arg [lindex $argv $i]
    if {$arg eq "--help" || $arg eq "-h"} {
        usage
    }
    if {$arg eq "--hide-source"} {
        set hide_source 1
        continue
    }
    if {$i + 1 >= [llength $argv]} {
        usage
    }
    incr i
    set value [lindex $argv $i]
    switch -- $arg {
        --top      { set opt(top) $value }
        --build    { set opt(build) [file normalize $value] }
        --vcd      { set opt(vcd) [file normalize $value] }
        --out      { set opt(out) [file normalize $value] }
        --include  { lappend include_globs $value }
        default    { usage }
    }
}
if {[llength $include_globs] == 0} {
    set include_globs [list *]
}

if {![file exists $opt(vcd)]} {
    error "VCD not found: $opt(vcd)"
}

package require Bluetcl
package require Virtual
package require SignalTypes
namespace import ::Bluetcl::*

flags set -sim
flags set -p "+:$opt(build)"
module load $opt(top)

proc path_selected {path globs} {
    foreach glob $globs {
        if {[string match $glob $path]} {
            return 1
        }
    }
    return 0
}

proc path_parent {path} {
    set parts [split [string trim $path /] /]
    if {[llength $parts] <= 1} {
        return /
    }
    return /[join [lrange $parts 0 end-1] /]
}

proc parse_vcd_header {filename} {
    set fd [open $filename r]
    set scopes {}
    set header {}
    array set vars {}
    array set widths {}

    while {[gets $fd line] >= 0} {
        if {[regexp {^\$scope\s+\S+\s+(\S+)\s+\$end} $line -> name]} {
            lappend scopes $name
        } elseif {[regexp {^\$upscope\s+\$end} $line]} {
            set scopes [lrange $scopes 0 end-1]
        } elseif {[regexp {^\$var\s+\S+\s+([0-9]+)\s+(\S+)\s+(\S+)} \
                       $line -> width identifier reference]} {
            set path /[join [concat $scopes $reference] /]
            lappend vars($path) [list $identifier $width]
            set widths($identifier) $width
        }
        lappend header $line
        if {$line eq {$enddefinitions $end}} {
            break
        }
    }
    set body_offset [tell $fd]
    close $fd
    return [list $header $body_offset [array get vars] [array get widths]]
}

proc infer_vcd_prefix {typed_signals vars_name} {
    upvar $vars_name vars
    array set counts {}
    foreach record $typed_signals {
        lassign $record signal type synth_path
        set suffix /[string trim $synth_path /]
        foreach path [array names vars] {
            if {[string match "*$suffix" $path]} {
                set prefix [string range $path 0 end-[string length $suffix]]
                incr counts($prefix)
            }
        }
    }
    set best {}
    set best_count -1
    foreach prefix [array names counts] {
        if {$counts($prefix) > $best_count ||
            ($counts($prefix) == $best_count &&
             [string length $prefix] > [string length $best])} {
            set best $prefix
            set best_count $counts($prefix)
        }
    }
    return $best
}

proc find_vcd_signal {synth_path prefix vars_name} {
    upvar $vars_name vars
    set suffix /[string trim $synth_path /]
    set preferred "$prefix$suffix"
    if {[info exists vars($preferred)]} {
        return [list $preferred {*}[lindex $vars($preferred) 0]]
    }
    set matches {}
    foreach path [array names vars] {
        if {[string match "*$suffix" $path]} {
            foreach item $vars($path) {
                lappend matches [list [string length $path] $path {*}$item]
            }
        }
    }
    if {[llength $matches] == 0} {
        return {}
    }
    return [lrange [lindex [lsort -integer -index 0 $matches] 0] 1 end]
}

proc semantic_bsv_path {signal synth_path} {
    set bsv_path [$signal path bsv]
    set raw_synth [$signal path synth]
    set inst [$signal inst]
    if {[regexp {^CReg} [$inst modname]] && [$signal name] eq "Q_OUT_0"} {
        return [path_parent $bsv_path]
    }
    if {$synth_path ne $raw_synth} {
        return [path_parent $bsv_path]
    }
    return $bsv_path
}

proc is_path_below {path parent} {
    return [expr {$path eq $parent ||
                  [string match "[string trimright $parent /]/*" $path]}]
}

lassign [parse_vcd_header $opt(vcd)] header body_offset vars_list widths_list
array set vcd_vars $vars_list
array set source_widths $widths_list
array set metadata {}
set typed_signals {}

foreach signal [Virtual::signal filter *] {
    foreach typed_signal [$signal wave_format] {
        lassign $typed_signal type synth_path
        lappend typed_signals [list $signal $type $synth_path]
    }
}
set vcd_prefix [infer_vcd_prefix $typed_signals vcd_vars]

foreach record $typed_signals {
    lassign $record signal type synth_path
    set found [find_vcd_signal $synth_path $vcd_prefix vcd_vars]
    if {[llength $found] == 0} {
        continue
    }
    lassign $found vcd_path identifier width
    set bsv_path [semantic_bsv_path $signal $synth_path]
    if {![path_selected $bsv_path $include_globs]} {
        continue
    }

    # Repeated elaborated objects can share a BSV path.  Keep the first
    # exact semantic signal and disambiguate later collisions.
    set key $bsv_path
    if {[info exists metadata($key)] &&
        [lindex $metadata($key) 1] ne $identifier} {
        set key "[path_parent $bsv_path]/[file tail $synth_path]"
    }
    set metadata($key) [list $type $identifier $width $vcd_path]
}

if {[array size metadata] == 0} {
    error "no selected BlueTcl signals matched VCD declarations"
}
set selected_signal_count [array size metadata]

array set hidden_scopes {}
foreach inst [Virtual::inst filter -kind Prim *] {
    set bsv_path [$inst path bsv]
    set selected 0
    foreach path [array names metadata] {
        if {[is_path_below $path $bsv_path]} {
            set selected 1
            break
        }
    }
    if {!$selected} {
        continue
    }

    set synth_path [$inst path synth]
    set physical_scope "$vcd_prefix/[string trim $synth_path /]"
    set has_scope 0
    foreach vcd_path [array names vcd_vars] {
        if {[path_parent $vcd_path] eq $physical_scope} {
            set has_scope 1
            break
        }
    }
    if {!$has_scope} {
        continue
    }

    # A primitive with a scalar semantic value and a physical implementation
    # scope becomes instance/value plus the implementation ports.
    if {[info exists metadata($bsv_path)]} {
        set metadata($bsv_path/value) $metadata($bsv_path)
        unset metadata($bsv_path)
        if {[info exists display_paths($bsv_path)]} {
            unset display_paths($bsv_path)
            set display_paths($bsv_path/value) 1
        }
    }
    foreach vcd_path [array names vcd_vars] {
        if {[path_parent $vcd_path] ne $physical_scope} {
            continue
        }
        set local_name [file tail $vcd_path]
        lassign [lindex $vcd_vars($vcd_path) 0] identifier width
        set target "$bsv_path/$local_name"
        if {![info exists metadata($target)]} {
            set metadata($target) [list "Bit#($width)" \
                $identifier $width $vcd_path]
        }
    }
    set hidden_scopes($physical_scope) 1
}

set synthetic_counter 0
array set used_identifiers {}
foreach identifier [array names source_widths] {
    set used_identifiers($identifier) 1
}
proc new_identifier {} {
    global synthetic_counter used_identifiers
    while {1} {
        set id "bsv$synthetic_counter"
        incr synthetic_counter
        if {![info exists used_identifiers($id)]} {
            set used_identifiers($id) 1
            break
        }
    }
    return $id
}

array set derived {}
proc add_derived {source kind identifier lsb width members} {
    global derived
    lappend derived($source) [list $kind $identifier $lsb $width $members]
}

proc brief_type {type} {
    regsub -all {[^ ()#,]+::} $type {} type
    return $type
}

proc write_comment {fd text} {
    puts $fd "\$comment $text \$end"
}

proc display_field_name {field_name owner_name} {
    if {[regexp {^_\[([0-9]+)\]$} $field_name -> index]} {
        return "${owner_name}\[$index\]"
    }
    return $field_name
}

proc declare_fields {fd source source_width type base_lsb owner_name} {
    set details [type bitify $type]
    set flavor [lindex $details 0]
    set fields [lindex $details 4]

    if {$flavor ne "STRUCT" && $flavor ne "TAGGEDUNION"} {
        return
    }

    if {$flavor eq "TAGGEDUNION"} {
        set tag_lsb 0
        foreach field $fields {
            set field_msb [expr {[lindex $field 3] + [lindex $field 2]}]
            if {$field_msb > $tag_lsb} {
                set tag_lsb $field_msb
            }
        }
        set total_width [lindex $details 2]
        set tag_width [expr {$total_width - $tag_lsb}]
        if {$tag_width > 0} {
            set id [new_identifier]
            puts $fd "\$var reg $tag_width $id tag \$end"
            set members [lindex $details 3]
            set name_id [new_identifier]
            puts $fd "\$var string 1 $name_id tag__name \$end"
            add_derived $source bits $id \
                [expr {$base_lsb + $tag_lsb}] $tag_width {}
            add_derived $source enum $name_id \
                [expr {$base_lsb + $tag_lsb}] $tag_width $members
        }
    }

    foreach field $fields {
        lassign $field field_name field_type field_width field_lsb
        if {$field_width <= 0} {
            continue
        }
        set display_name [display_field_name $field_name $owner_name]
        set absolute_lsb [expr {$base_lsb + $field_lsb}]
        set field_details [type bitify $field_type]
        set field_flavor [lindex $field_details 0]
        set field_id [new_identifier]
        puts $fd "\$var reg $field_width $field_id $display_name \$end"
        write_comment $fd "BSV type: [brief_type $field_type]"
        add_derived $source bits $field_id $absolute_lsb $field_width {}

        if {$field_flavor eq "ENUM"} {
            set name_id [new_identifier]
            puts $fd "\$var string 1 $name_id ${display_name}__name \$end"
            add_derived $source enum $name_id $absolute_lsb $field_width \
                [lindex $field_details 3]
        } elseif {$field_flavor eq "STRUCT" ||
                  $field_flavor eq "TAGGEDUNION"} {
            puts $fd "\$scope module ${display_name}__fields \$end"
            declare_fields $fd $source $source_width $field_type \
                $absolute_lsb $display_name
            puts $fd {$upscope $end}
        }
    }
}

proc common_prefix_length {left right} {
    set limit [expr {min([llength $left], [llength $right])}]
    for {set i 0} {$i < $limit} {incr i} {
        if {[lindex $left $i] ne [lindex $right $i]} {
            return $i
        }
    }
    return $limit
}

proc write_bsv_declarations {fd metadata_name} {
    global opt
    upvar $metadata_name metadata
    set open_scopes {}
    puts $fd {$scope module bsv $end}
    puts $fd "\$scope module $opt(top) \$end"

    foreach path [lsort [array names metadata]] {
        lassign $metadata($path) type source width original_path
        set parts [split [string trim $path /] /]
        set signal_name [lindex $parts end]
        set scopes [lrange $parts 0 end-1]
        set common [common_prefix_length $open_scopes $scopes]

        for {set i [llength $open_scopes]} {$i > $common} {incr i -1} {
            puts $fd {$upscope $end}
        }
        for {set i $common} {$i < [llength $scopes]} {incr i} {
            puts $fd "\$scope module [lindex $scopes $i] \$end"
        }
        set open_scopes $scopes

        puts $fd "\$var reg $width $source $signal_name \$end"
        write_comment $fd "BSV type: [brief_type $type]; source: $original_path"
        set details [type bitify $type]
        set flavor [lindex $details 0]

        if {$flavor eq "ENUM" && $type ne "Bool"} {
            set name_id [new_identifier]
            puts $fd "\$var string 1 $name_id ${signal_name}__name \$end"
            add_derived $source enum $name_id 0 $width [lindex $details 3]
        } elseif {$flavor eq "STRUCT" || $flavor eq "TAGGEDUNION"} {
            puts $fd "\$scope module ${signal_name}__fields \$end"
            declare_fields $fd $source $width $type 0 $signal_name
            puts $fd {$upscope $end}
        }
    }

    for {set i [llength $open_scopes]} {$i > 0} {incr i -1} {
        puts $fd {$upscope $end}
    }
    puts $fd {$upscope $end}
    puts $fd {$upscope $end}
}

proc write_source_header {fd header metadata_name hidden_scopes_name hide_source} {
    upvar $metadata_name metadata
    upvar $hidden_scopes_name hidden_scopes
    array set hidden_paths {}
    if {$hide_source} {
        foreach path [array names metadata] {
            set hidden_paths([lindex $metadata($path) 3]) 1
        }
        foreach scope [array names hidden_scopes] {
            # Bluesim commonly declares a primitive's semantic value beside
            # a same-named scope containing its implementation ports.
            set hidden_paths($scope) 1
        }
    }

    set scopes {}
    set skip_depth 0
    foreach line [lrange $header 0 end-1] {
        if {[regexp {^\$scope\s+\S+\s+(\S+)\s+\$end} $line -> name]} {
            lappend scopes $name
            set scope_path /[join $scopes /]
            if {$skip_depth > 0} {
                incr skip_depth
                continue
            }
            if {$hide_source && [info exists hidden_scopes($scope_path)]} {
                set skip_depth 1
                continue
            }
        } elseif {[regexp {^\$upscope\s+\$end} $line]} {
            set scopes [lrange $scopes 0 end-1]
            if {$skip_depth > 0} {
                incr skip_depth -1
                continue
            }
        } elseif {$skip_depth > 0} {
            continue
        } elseif {[regexp {^\$var\s+\S+\s+\S+\s+\S+\s+(\S+)} \
                       $line -> reference]} {
            set path /[join [concat $scopes $reference] /]
            if {$hide_source && [info exists hidden_paths($path)]} {
                continue
            }
        }
        puts $fd $line
    }
}

proc normalize_bits {bits width} {
    set bits [string tolower $bits]
    if {[string length $bits] > $width} {
        return [string range $bits end-[expr {$width - 1}] end]
    }
    if {[string length $bits] == $width} {
        return $bits
    }
    set fill 0
    if {[regexp {[xz]} $bits match]} {
        set fill $match
    }
    return "[string repeat $fill [expr {$width - [string length $bits]}]]$bits"
}

proc slice_bits {bits source_width lsb width} {
    set bits [normalize_bits $bits $source_width]
    set first [expr {$source_width - $lsb - $width}]
    set last [expr {$source_width - $lsb - 1}]
    if {$first < 0 || $last >= $source_width} {
        return [string repeat x $width]
    }
    return [string range $bits $first $last]
}

proc bits_to_integer {bits} {
    if {[regexp {[xz]} $bits]} {
        return -1
    }
    set value 0
    foreach bit [split $bits {}] {
        set value [expr {$value * 2 + ($bit eq "1")}]
    }
    return $value
}

proc write_derived_changes {fd source bits} {
    global derived source_widths
    if {![info exists derived($source)] ||
        ![info exists source_widths($source)]} {
        return
    }
    set source_width $source_widths($source)
    foreach spec $derived($source) {
        lassign $spec kind identifier lsb width members
        set selected [slice_bits $bits $source_width $lsb $width]
        if {$kind eq "bits"} {
            if {$width == 1} {
                puts $fd "[string index $selected 0]$identifier"
            } else {
                puts $fd "b$selected $identifier"
            }
        } else {
            set index [bits_to_integer $selected]
            if {$index >= 0 && $index < [llength $members]} {
                set label [lindex $members $index]
            } else {
                set label UNKNOWN
            }
            puts $fd "s$label $identifier"
        }
    }
}

file mkdir [file dirname $opt(out)]
set input [open $opt(vcd) r]
set output [open $opt(out) w]
fconfigure $input -translation lf
fconfigure $output -translation lf

write_source_header $output $header metadata hidden_scopes $hide_source
write_bsv_declarations $output metadata
puts $output {$enddefinitions $end}

seek $input $body_offset start
while {[gets $input line] >= 0} {
    puts $output $line
    if {[regexp {^([01xXzZ])(\S+)$} $line -> value identifier]} {
        write_derived_changes $output $identifier $value
    } elseif {[regexp {^[bB]([01xXzZ]+)\s+(\S+)$} \
                   $line -> value identifier]} {
        write_derived_changes $output $identifier $value
    }
}
close $input
close $output

puts "Wrote $opt(out)"
puts "Selected $selected_signal_count typed signals"
puts "Declared [array size metadata] signals including primitive internals"
