# Source data and local reproduction

Use **DataCo SMART SUPPLY CHAIN FOR BIG DATA ANALYSIS**, by Constante, Fabian; Silva, Fernando; Pereira, António (2019), Mendeley Data, V5, DOI: `10.17632/8gx2fvg2k6.5`.

[Download from Mendeley Data](https://data.mendeley.com/datasets/8gx2fvg2k6/5). The publisher lists **CC BY 4.0**. Retain attribution and review the source terms when reusing the data.

Download the structured file `DataCoSupplyChainDataset.csv` and place it in this directory locally. Expected repository-relative location: `data/DataCoSupplyChainDataset.csv`. The analyzed copy has 53 columns and 180,519 rows. `DescriptionDataCoSupplyChain.csv` is an optional source data dictionary; clickstream files are not needed.

Raw data is intentionally excluded from GitHub to keep the repository lightweight and avoid redistributing customer-level fields. This is a publication choice, not a claim that the source license prohibits redistribution. SQL and aggregate findings are published; CSVs and result exports stay local.

## Import into PostgreSQL

1. Create a dedicated database, then execute **section 0** of `sql/01_bronze_profiling.sql` to create `bronze.dataco_supply_chain_raw` with all 53 columns as TEXT in CSV order.
2. Start `psql` from the repository root and connect to that database.
3. Run this client-side import as a single line:

```sql
\copy bronze.dataco_supply_chain_raw FROM 'data/DataCoSupplyChainDataset.csv' WITH (FORMAT CSV, HEADER TRUE, ENCODING 'WIN1252');
```

The analyzed local copy uses Windows-1252 encoding. If your downloaded copy is UTF-8, use `ENCODING 'UTF8'` instead; inspect accented text after import. Unquoted empty CSV fields become SQL NULL. The CSV header is skipped, so column order must match the staging definition exactly.

4. Execute the complete Bronze profiling script and confirm 180,519 rows and distinct order-item IDs before proceeding through scripts 02–04.

Do not repeat the import into a populated staging table. For a new source copy, use a fresh project database and revalidate all assumptions. Supply connection details through your normal PostgreSQL authentication; never commit passwords or connection secrets.
