# GiftHub Data Pipeline

An end-to-end data engineering project that turns raw UK online retail sales data into a trusted reporting dashboard.

**Dataset:** Online Retail II, UCI Machine Learning Repository
**Stack:** Python, PostgreSQL, dbt, Apache Airflow, Docker, Power BI / Metabase, Git

## Project status

- [x] Phase 1: Environment setup
- [ ] Phase 2: Ingestion (Bronze)
- [ ] Phase 3: Cleaning (Silver)
- [ ] Phase 4: Modelling (Gold)
- [ ] Phase 5: Data quality
- [ ] Phase 6: Orchestration
- [ ] Phase 7: Dashboard
- [ ] Phase 8: Documentation

## Folder structure

```
gifthub-pipeline/
├── airflow/
│   ├── dags/          # Airflow workflow files
│   ├── logs/          # Airflow run logs (not in Git)
│   └── plugins/       # Custom Airflow code (if needed)
├── data/raw/          # Downloaded source files (not in Git)
├── dbt/               # dbt project (from Phase 3)
├── docs/              # ERD, screenshots, cleaning log
├── ingestion/         # Python ingestion scripts
├── sql/init/          # SQL run once when the database is first created
├── .env.example       # Template for secrets
├── docker-compose.yml # Starts PostgreSQL and Airflow
└── requirements.txt   # Python packages
```

## How to run

```bash
cp .env.example .env              # then edit the passwords
docker compose up -d              # start everything
python ingestion/test_connection.py   # check the database
```

Airflow: http://localhost:8080 (login from `.env`)
PostgreSQL: `localhost:5433`, database `gifthub_dw`

## Stop and reset

```bash
docker compose down        # stop, keep data
docker compose down -v     # stop and delete all database data (full reset)
```
