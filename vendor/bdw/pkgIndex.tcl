# Derived from the BSC Development Workstation (BDW) package index.
# Copyright (c) 2020 Bluespec, Inc. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause
# See BDW-BSD-3-Clause.txt for the complete license terms.

package ifneeded MathSupport 1.0 [list source [file join $dir MathSupport.tcl]]
package ifneeded SignalTypes 1.0 [list source [file join $dir SignalTypes.tcl]]
package ifneeded TypeSupport 1.0 [list source [file join $dir TypeSupport.tcl]]
package ifneeded VisitorPattern 1.1 [list source [file join $dir VisitorPattern.tcl]]
package ifneeded Virtual 2.0 [list source [file join $dir virtual.tcl]]
package ifneeded Functional 1.0 [list source [file join $dir functional.tcl]]
