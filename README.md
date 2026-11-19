# Snowflake UDxF Warehouse Parallelism

Author: Garrett Frere (garrett.frere@snowflake.com)

Hands-on enablement for Python **UDFs** and **UDTFs** (UDxFs) running in Snowflake warehouses. It is written for people coming from Spark `pandas_udf` / `groupBy().applyInPandas()` and shows how the same patterns map to Snowflake, when to use a UDF vs a UDTF, and how the same code scales from a Small to a Large warehouse with no code changes.

## Spark to Snowflake at a glance

| Spark | Snowflake warehouse | Use it for |
|---|---|---|
| `pandas_udf` (Series -> Series) | Vectorized UDF | Row-wise transforms, features, scoring |
| `groupBy(k).applyInPandas(fn)` | Vectorized UDTF with `end_partition` + `PARTITION BY k` | Per-group model fits, logic that needs all rows for a key |
| Broadcast / `mapPartitions` setup | `@udf_init_once` | Loading a large model or lookup table once per query |

## Files

| File | What it is |
|---|---|
| `udxf_setup.sql` | One-time setup: `UDXF_S_WH` / `UDXF_M_WH` / `UDXF_L_WH` warehouses, the synthetic `STORE_SALES` table (100M rows, 1,000 stores, 2 years), and the `UDXF_STAGE` stage for function code |
| `udxf_enablement.ipynb` | Main notebook: inline and permanent vectorized UDFs, calling them from Python and SQL, `@udf_init_once`, a per-store price elasticity UDTF, and the Small / Medium / Large scaling benchmark (runtime, `wh_dop`, credits) |
| `udtf_init_once_test.ipynb` | Functional test showing `@udf_init_once` also works in a Python UDTF: the init runs once in a parent process instead of once per worker |
| `udxf_diagrams.html` | Visual guide: ways to create and call UDxFs, UDF vs UDTF, warehouse parallelism (nodes x 8 lanes), and a railroad analogy |

## Prerequisites

- A role that can create warehouses, tables, stages and functions. The scripts use `ML_PERF_ROLE` and the `ML_PERF.PUBLIC` schema; replace these with your own names.
- An existing warehouse for setup and non-benchmark cells. The notebooks use `ML_MODEL_WH`; replace it with any warehouse you have.
- A Snowflake Workspace (or any Snowpark Python environment) to run the notebooks.

## How to run

1. Run `udxf_setup.sql` in a Snowflake worksheet to create the warehouses, data and stage.
2. Open `udxf_enablement.ipynb` and **Run all**. Section 6 benchmarks the UDF and UDTF on all 100M rows on each of the three warehouses, so it is the longest part.
3. Optionally run `udtf_init_once_test.ipynb` to see `@udf_init_once` in a UDTF.
4. Open `udxf_diagrams.html` in a browser for the diagrams.

## The data

`STORE_SALES` is fully synthetic. Each store is generated with a known price elasticity, `0.5 + MOD(store_id * 37, 100) / 100`, so the elasticity the UDTF fits for each store can be checked against the true value.

## Cost note

The benchmark warehouses are created suspended, with `AUTO_SUSPEND = 60`. Each size up doubles both the nodes and the credits per hour, and billing is per second, so if a run takes half as long on the next size up, it costs about the same. Drop the `UDXF_*_WH` warehouses and the `STORE_SALES` table when you're done.
