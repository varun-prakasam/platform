variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "location" {
  description = "Dataset location. Must match the GCS bucket location for BigLake external tables to work."
  type        = string
}

variable "labels" {
  description = "Labels applied to every dataset."
  type        = map(string)
  default     = {}
}

variable "datasets" {
  description = <<-EOT
    Datasets to create, keyed by dataset ID.

    `project_ref` and `layer` become labels, which is what makes per-project cost attribution
    possible in the billing export.
  EOT

  type = map(object({
    description                   = string
    project_ref                   = string
    layer                         = optional(string, "none")
    default_table_expiration_days = optional(number)
    max_time_travel_hours         = optional(number, 48)
    delete_contents_on_destroy    = optional(bool, false)
  }))

  default = {
    # --- Platform -------------------------------------------------------------------------------
    platform_billing = {
      description = "Cloud Billing export and derived cost summaries"
      project_ref = "platform"
      layer       = "ops"
    }
    platform_ops = {
      description = "Pipeline run metadata, health snapshots and lineage events"
      project_ref = "platform"
      layer       = "ops"
    }

    # --- 1. Streaming ---------------------------------------------------------------------------
    p01_streaming_raw = {
      description                   = "Raw Bluesky firehose events landed by Flink"
      project_ref                   = "p01-streaming"
      layer                         = "raw"
      default_table_expiration_days = 14
      delete_contents_on_destroy    = true
    }
    p01_streaming_curated = {
      description = "Windowed aggregates and enriched event streams"
      project_ref = "p01-streaming"
      layer       = "curated"
    }

    # --- 2. Lakehouse ---------------------------------------------------------------------------
    p02_lakehouse = {
      description = "BigLake external tables over the Iceberg warehouse on GCS"
      project_ref = "p02-lakehouse"
      layer       = "curated"
    }

    # --- 3. ELT and dimensional modelling -------------------------------------------------------
    p03_raw = {
      description                = "dlt landing tables, loaded verbatim from source APIs"
      project_ref                = "p03-elt"
      layer                      = "raw"
      delete_contents_on_destroy = true
    }
    p03_staging = {
      description                = "dbt staging models: renamed, recast, lightly cleaned"
      project_ref                = "p03-elt"
      layer                      = "staging"
      delete_contents_on_destroy = true
    }
    p03_marts = {
      description = "dbt marts: conformed dimensions and fact tables"
      project_ref = "p03-elt"
      layer       = "marts"
    }

    # --- 4. Orchestration -----------------------------------------------------------------------
    p04_orchestration = {
      description = "Flight and weather pipeline outputs, plus DAG run telemetry"
      project_ref = "p04-orchestration"
      layer       = "curated"
    }

    # --- 5. CDC ---------------------------------------------------------------------------------
    p05_cdc_bronze = {
      description                   = "Raw Debezium change events, append-only"
      project_ref                   = "p05-cdc"
      layer                         = "bronze"
      default_table_expiration_days = 14
      delete_contents_on_destroy    = true
    }
    p05_cdc_silver = {
      description = "Deduplicated current state and SCD2 history"
      project_ref = "p05-cdc"
      layer       = "silver"
    }

    # --- 6. Data quality ------------------------------------------------------------------------
    p06_quality = {
      description = "Check results, freshness SLOs, anomaly scores and incident history"
      project_ref = "p06-quality"
      layer       = "ops"
    }

    # --- 7. Vector ------------------------------------------------------------------------------
    p07_vector = {
      description = "Document chunks, embeddings and vector search indexes"
      project_ref = "p07-vector"
      layer       = "curated"
    }

    # --- 8. OLAP --------------------------------------------------------------------------------
    p08_olap_bench = {
      description = "Mirror of the StarRocks dataset, used for the latency comparison"
      project_ref = "p08-olap"
      layer       = "curated"
    }

    # --- 9. Feature store -----------------------------------------------------------------------
    p09_features = {
      description = "Feast offline store: point-in-time correct feature values"
      project_ref = "p09-features"
      layer       = "curated"
    }

    # --- 10. Governance -------------------------------------------------------------------------
    p10_governance = {
      description = "Catalog snapshots, PII classification results and access audit"
      project_ref = "p10-governance"
      layer       = "ops"
    }
  }
}
