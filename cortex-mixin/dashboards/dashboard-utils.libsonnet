local utils = import 'mixin-utils/utils.libsonnet';

(import 'grafana-builder/grafana.libsonnet') {

  _config:: error 'must provide _config',

  // Override the dashboard constructor to add:
  // - default tags,
  // - some links that propagate the selectred cluster.
  dashboard(title)::
    super.dashboard(title) + {
      addRowIf(condition, row)::
        if condition
        then self.addRow(row)
        else self,

      addClusterSelectorTemplates()::
        local d = self {
          tags: $._config.tags,
          links: [
            {
              asDropdown: true,
              icon: 'external link',
              includeVars: true,
              keepTime: true,
              tags: $._config.tags,
              targetBlank: false,
              title: 'Cortex Dashboards',
              type: 'dashboards',
            },
          ],
        };

        if $._config.singleBinary
        then d.addMultiTemplate('job', 'cortex_build_info', 'job')
        else d
             .addMultiTemplate('cluster', 'cortex_build_info', 'cluster')
             .addMultiTemplate('namespace', 'cortex_build_info', 'namespace'),
    },

  // The ,ixin allow specialism of the job selector depending on if its a single binary
  // deployment or a namespaced one.
  jobMatcher(job)::
    if $._config.singleBinary
    then 'job=~"$job"'
    else 'cluster=~"$cluster", job=~"($namespace)/%s"' % job,

  namespaceMatcher()::
    if $._config.singleBinary
    then 'job=~"$job"'
    else 'cluster=~"$cluster", namespace=~"$namespace"',

  jobSelector(job)::
    if $._config.singleBinary
    then [utils.selector.noop('cluster'), utils.selector.re('job', '$job')]
    else [utils.selector.re('cluster', '$cluster'), utils.selector.re('job', '($namespace)/%s' % job)],

  queryPanel(queries, legends, legendLink=null)::
    super.queryPanel(queries, legends, legendLink) + {
      targets: [
        target {
          interval: '1m',
        }
        for target in super.targets
      ],
    },

  qpsPanel(selector)::
    super.qpsPanel(selector) + {
      targets: [
        target {
          interval: '1m',
        }
        for target in super.targets
      ],
    },

  latencyPanel(metricName, selector, multiplier='1e3')::
    super.latencyPanel(metricName, selector, multiplier) + {
      targets: [
        target {
          interval: '1m',
        }
        for target in super.targets
      ],
    },

  successFailurePanel(title, successMetric, failureMetric)::
    $.panel(title) +
    $.queryPanel([successMetric, failureMetric], ['successful', 'failed']) +
    $.stack + {
      aliasColors: {
        successful: '#7EB26D',
        failed: '#E24D42',
      },
    },

  // Displays started, completed and failed rate.
  startedCompletedFailedPanel(title, startedMetric, completedMetric, failedMetric)::
    $.panel(title) +
    $.queryPanel([startedMetric, completedMetric, failedMetric], ['started', 'completed', 'failed']) +
    $.stack + {
      aliasColors: {
        started: '#34CCEB',
        completed: '#7EB26D',
        failed: '#E24D42',
      },
    },

  // Switches a panel from lines (default) to bars.
  bars:: {
    bars: true,
    lines: false,
  },

  textPanel(title, content, options={}):: {
    content: content,
    datasource: null,
    description: '',
    mode: 'markdown',
    title: title,
    transparent: true,
    type: 'text',
  } + options,

  objectStorePanels1(title, metricPrefix)::
    local opsTotal = '%s_thanos_objstore_bucket_operations_total' % [metricPrefix];
    local opsTotalFailures = '%s_thanos_objstore_bucket_operation_failures_total' % [metricPrefix];
    local operationDuration = '%s_thanos_objstore_bucket_operation_duration_seconds' % [metricPrefix];
    super.row(title)
    .addPanel(
      // We use 'up' to add 0 if there are no failed operations.
      self.successFailurePanel(
        'Operations/sec',
        'sum(rate(%s{%s}[$__interval])) - sum(rate(%s{%s}[$__interval]) or (up{%s}*0))' % [opsTotal, $.namespaceMatcher(), opsTotalFailures, $.namespaceMatcher(), $.namespaceMatcher()],
        'sum(rate(%s{%s}[$__interval]) or (up{%s}*0))' % [opsTotalFailures, $.namespaceMatcher(), $.namespaceMatcher()]
      )
    )
    .addPanel(
      $.panel('Op: ObjectSize') +
      $.latencyPanel(operationDuration, '{%s, operation="objectsize"}' % $.namespaceMatcher()),
    )
    .addPanel(
      // Cortex (Thanos) doesn't track timing for 'iter', so we use ops/sec instead.
      $.panel('Op: Iter') +
      $.queryPanel('sum(rate(%s{%s, operation="iter"}[$__interval]))' % [opsTotal, $.namespaceMatcher()], 'ops/sec')
    )
    .addPanel(
      $.panel('Op: Exists') +
      $.latencyPanel(operationDuration, '{%s, operation="exists"}' % $.namespaceMatcher()),
    ),

  // Second row of Object Store stats
  objectStorePanels2(title, metricPrefix)::
    local operationDuration = '%s_thanos_objstore_bucket_operation_duration_seconds' % [metricPrefix];
    super.row(title)
    .addPanel(
      $.panel('Op: Get') +
      $.latencyPanel(operationDuration, '{%s, operation="get"}' % $.namespaceMatcher()),
    )
    .addPanel(
      $.panel('Op: GetRange') +
      $.latencyPanel(operationDuration, '{%s, operation="get_range"}' % $.namespaceMatcher()),
    )
    .addPanel(
      $.panel('Op: Upload') +
      $.latencyPanel(operationDuration, '{%s, operation="upload"}' % $.namespaceMatcher()),
    )
    .addPanel(
      $.panel('Op: Delete') +
      $.latencyPanel(operationDuration, '{%s, operation="delete"}' % $.namespaceMatcher()),
    ),
}
