// Pipeline health alerting.
//
// The failure mode this exists for is not a crash — a crash is visible. It is a scheduled job that
// stops producing correct data while everything downstream keeps serving the last good numbers.
// Nobody looks at a dashboard that still renders, so the pipeline has to be the thing that speaks.
//
// Two alerts, because one cannot cover both shapes:
//
//   * A job that runs and gives up.       Loud, immediate, tells you which job and which project.
//   * A job that stops running at all.    Silent — no pod, no failure event, nothing to alert on.
//     A suspended CronJob, an unschedulable pod or a cluster outage produces no signal whatsoever,
//     and silence is indistinguishable from success until someone reads a date on a chart.

locals {
  enabled = var.alert_email == null ? 0 : 1
}

// Separate from the budget channel on purpose. That one is named for cost and is something you
// might reasonably mute for a month while running an experiment; muting it should not also switch
// off the alert that tells you the data stopped arriving.
resource "google_monitoring_notification_channel" "pipeline_email" {
  count = local.enabled

  project      = var.project_id
  display_name = "Platform pipeline alerts"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}

// -- a job ran and gave up --------------------------------------------------------------------

// BackoffLimitExceeded is the Job controller announcing it has stopped retrying; DeadlineExceeded
// is activeDeadlineSeconds cutting a run off. Both mean the run is over and did not finish.
//
// Deliberately not alerting on individual pod failures. A pod that fails and is retried
// successfully is the backoff limit doing its job — p03-elt has already survived a transient
// source truncation exactly that way — and paging on it would train you to ignore the alert.
resource "google_logging_metric" "job_gave_up" {
  count = local.enabled

  project = var.project_id
  name    = "platform/job_gave_up"

  description = "Kubernetes Jobs that exhausted their retries or ran past their deadline."

  filter = <<-EOT
    resource.type="k8s_cluster"
    resource.labels.cluster_name="${var.cluster_name}"
    jsonPayload.involvedObject.kind="Job"
    jsonPayload.reason=("BackoffLimitExceeded" OR "DeadlineExceeded")
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"

    labels {
      key         = "namespace"
      description = "Namespace the job ran in, which identifies the project."
    }
    labels {
      key         = "job_name"
      description = "Name of the failed job."
    }
  }

  label_extractors = {
    "namespace" = "EXTRACT(jsonPayload.involvedObject.namespace)"
    "job_name"  = "EXTRACT(jsonPayload.involvedObject.name)"
  }
}

resource "google_monitoring_alert_policy" "job_gave_up" {
  count = local.enabled

  project      = var.project_id
  display_name = "Pipeline job failed"
  combiner     = "OR"

  conditions {
    display_name = "A Kubernetes Job exhausted its retries"

    condition_threshold {
      filter          = "resource.type=\"k8s_cluster\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.job_gave_up[0].name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["metric.label.namespace", "metric.label.job_name"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.pipeline_email[0].id]

  documentation {
    mime_type = "text/markdown"
    subject   = "A data pipeline job failed"
    content   = <<-EOT
      A Kubernetes Job stopped retrying without finishing. The data it produces is now stale, and
      anything reading its marts is serving the previous run's numbers.

      Logs, substituting the namespace from this alert:

      ```
      kubectl get jobs -n NAMESPACE
      kubectl logs -n NAMESPACE -l job-name=JOB_NAME --tail=200
      ```

      The pipeline runs extract, then `dbt build`, then publishes docs, and stops at the first
      failure. A dbt test failure therefore leaves the warehouse partially updated: models built
      before the failing test are current, everything downstream of it was skipped. Read the dbt
      summary line in the logs before rerunning, because a rerun will not tell you what broke.
    EOT
  }

  // An alert nobody can silence is an alert everybody ignores.
  alert_strategy {
    auto_close = "604800s"
  }
}

// -- a job stopped running at all --------------------------------------------------------------

resource "google_logging_metric" "pipeline_success" {
  for_each = local.enabled == 0 ? {} : var.heartbeats

  project = var.project_id
  name    = "platform/pipeline_success/${each.key}"

  description = "Successful completions of the ${each.key} pipeline, counted from its entrypoint's final log line."

  // Anchored on the marker the entrypoint prints after every step has succeeded, rather than on
  // pod exit status. Exit status says the container stopped cleanly; the marker says the work
  // actually finished, which is the thing worth measuring.
  filter = <<-EOT
    resource.type="k8s_container"
    resource.labels.cluster_name="${var.cluster_name}"
    resource.labels.namespace_name="${each.value.namespace}"
    textPayload:"${each.value.marker}"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

resource "google_monitoring_alert_policy" "pipeline_stale" {
  for_each = local.enabled == 0 ? {} : var.heartbeats

  project      = var.project_id
  display_name = "Pipeline stale — ${each.key}"
  combiner     = "OR"

  conditions {
    display_name = "No successful ${each.key} run recorded"

    // Counted over a trailing window rather than expressed as an absence condition. Absence is the
    // obvious primitive and it cannot be used here: the API caps its duration at 23h30m, so against
    // a daily schedule the last success ages out every morning shortly before the next run and the
    // alert fires every day forever.
    //
    // Summing over a window the schedule is guaranteed to fill inverts that. The window empties
    // only when a run is genuinely missing, and `grace` then decides how long a late run has to
    // arrive before this becomes an alert.
    condition_threshold {
      filter          = "resource.type=\"k8s_container\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.pipeline_success[each.key].name}\""
      comparison      = "COMPARISON_LT"
      threshold_value = 1
      duration        = each.value.grace

      aggregations {
        alignment_period     = each.value.window
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }

      // A pipeline that stops running stops writing this metric altogether, and a condition that
      // treats "no data" as "nothing to see" would go quiet at exactly the moment it matters.
      evaluation_missing_data = "EVALUATION_MISSING_DATA_ACTIVE"
    }
  }

  notification_channels = [google_monitoring_notification_channel.pipeline_email[0].id]

  documentation {
    mime_type = "text/markdown"
    subject   = "A data pipeline has stopped running"
    content   = <<-EOT
      No successful run of `${each.key}` has been recorded for longer than its schedule allows, and
      no job failed either — so the workload is not running at all rather than running and breaking.

      This is the failure the other alert cannot see. Usual causes, cheapest to check first:

      ```
      kubectl get cronjob -n ${each.value.namespace}        # SUSPEND stuck at True?
      kubectl get jobs -n ${each.value.namespace}           # anything scheduled at all?
      kubectl describe node -l pool=base                    # pod unschedulable on CPU or memory?
      ```

      A CronJob also stops scheduling permanently once it misses one hundred windows, which is what
      `startingDeadlineSeconds` on the manifest exists to prevent. If nothing has run for days, check
      that it recovered rather than assuming it will.
    EOT
  }

  alert_strategy {
    auto_close = "604800s"
  }
}
