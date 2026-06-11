# Vendored from the BSC Development Workstation (BDW).
# Copyright (c) 2020 Bluespec, Inc. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause
# See BDW-BSD-3-Clause.txt for the complete license terms.

package provide VisitorPattern 1.1

namespace eval ::VisitorPattern  {}

itcl::class ::VisitorPattern::Acceptor {
    method accept {visitor args} {
        foreach h [$this info heritage] {
            set mname [format "visit_%s" [namespace tail $h]]
            if { ![catch [list $visitor info function $mname]] } {
                return [eval $visitor $mname $this $args]
            }
        }
        eval $visitor visit_Default $this $args
    }
}

itcl::class ::VisitorPattern::Visitor {
    method visit_Default {obj args} {
        error "undeclared visitor for [$this info class] with object [$obj info class]"
    }
}
