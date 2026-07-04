# BlueLens

BlueLens reads hierarchy and type information from elaborated Bluespec
SystemVerilog (BSV) designs.

The first utility, `annotate_bsv_vcd.tcl`, uses BlueTcl hierarchy and type
metadata to add a structured BSV view to an existing VCD. It does not analyze
waveform values.

The utilization flow joins routed Vivado primitive cells to the same BlueTcl
hierarchy.  It writes a compact Markdown collection with one primitive table
per selected BSV module.

## Requirements

- Bluespec Compiler tools, including `bluetcl`
- An elaborated Bluesim build containing the requested top module
- A VCD generated from that build
- Vivado, for utilization collection from a routed/synthesized checkpoint

## Usage

Run the utility from the root of the BSV project:

```sh
bluetcl /path/to/bluelens/annotate_bsv_vcd.tcl \
  --top mkTop \
  --build build \
  --vcd build/dump.vcd \
  --out build/dump.typed.vcd
```

Useful options:

```text
--include GLOB    Select BSV hierarchy paths; may be repeated
--hide-source     Remove mapped declarations from the physical VCD hierarchy
```

Without explicit paths, BlueLens looks under `hdl/build` relative to the
current working directory.

## Vivado Utilization by BSV Hierarchy

First export primitive cells from a Vivado checkpoint:

```sh
vivado -mode batch \
  -source /path/to/bluelens/collect_vivado_primitives.tcl \
  -tclargs \
    --dcp build/Top/Top_physopt.dcp \
    --root wrapper/top_bsv_inst \
    --out build/Top/vivado_primitives.tsv
```

Then fold those cells into the elaborated BSV hierarchy:

```sh
bluetcl /path/to/bluelens/report_bsv_utilization.tcl \
  --top mkTop \
  --build build \
  --vivado-root wrapper/top_bsv_inst \
  --vivado-cells build/Top/vivado_primitives.tsv \
  --max-depth 4 \
  --min-total 100 \
  --out build/Top/bsv_utilization.md
```

To use Vivado's own `report_utilization` tables for the selected BSV modules,
ask the BlueTcl step to also write a Vivado plan:

```sh
bluetcl /path/to/bluelens/report_bsv_utilization.tcl \
  --top mkTop \
  --build build \
  --vivado-root wrapper/top_bsv_inst \
  --vivado-cells build/Top/vivado_primitives.tsv \
  --max-depth 4 \
  --min-total 100 \
  --vivado-plan build/Top/bsv_vivado_plan.tsv \
  --out build/Top/bsv_utilization.md
```

Then render real Vivado utilization table sections for each selected BSV
module:

```sh
vivado -mode batch \
  -source /path/to/bluelens/report_vivado_bsv_tables.tcl \
  -tclargs \
    --dcp build/Top/Top_physopt.dcp \
    --plan build/Top/bsv_vivado_plan.tsv \
    --out build/Top/bsv_vivado_tables.md
```

Useful options:

```text
--vivado-root PATH  Vivado instance path corresponding to the BSV top
--include GLOB      Select BSV module paths; may be repeated
--max-depth N       Keep the report at module scale instead of register detail
--min-total N       Omit small modules from the collection
--show-direct       Add direct-only primitive tables under each module
--show-empty        Include selected modules with no matched primitives
--vivado-plan FILE  Write cell selections for report_vivado_bsv_tables.tcl
```

The Vivado exporter skips constant pseudo-cells and transformed RAM macro
parents so its primitive set matches Vivado's `report_utilization` primitive
table style more closely.

`report_vivado_bsv_tables.tcl` defaults to the `Slice Logic`, `Memory`, `DSP`,
and `Primitives` sections.  Use `--sections all` to keep the whole Vivado
report for each BSV module, or pass a comma-separated section list.
