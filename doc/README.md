

# Exometer - Erlang instrumentation package #

Copyright (c) 2014 Basho Technologies, Inc.  All Rights Reserved.

__Version:__ Jan 29 2015 20:56:36

__Authors:__ Ulf Wiger ([`ulf.wiger@feuerlabs.com`](mailto:ulf.wiger@feuerlabs.com)), Magnus Feuer ([`magnus.feuer@feuerlabs.com`](mailto:magnus.feuer@feuerlabs.com)).

[![Build Status](https://travis-ci.org/Feuerlabs/exometer.png?branch=master)](https://travis-ci.org/Feuerlabs/exometer)

__NOTE: Exometer has been split into [exometer_core](https://github.com/Feuerlabs/exometer_core), and exometer (as well as separate reporter applications). The latest monolithic version of Exometer is 1.1.__

The Exometer package allows for easy and efficient instrumentation of
Erlang code, allowing crucial data on system performance to be
exported to a wide variety of monitoring systems.

Exometer comes with a set of pre-defined monitor components, and can
be expanded with custom components to handle new types of Metrics, as
well as integration with additional external systems such as
databases, load balancers, etc.

This document gives a high level overview of the Exometer system. For
details, please see the documentation for individual modules, starting
with `exometer`.

Note the section on [Dependency Management](#Dependency_Management) for how to deal with
optional packages, both users and developers.


### <a name="Table_of_Content">Table of Content</a> ###


1. [Concept and definitions](#Concept_and_definitions)
    1. [Metric](#Metric)
    2. [Data Point](#Data_Point)
    3. [Metric Type](#Metric_Type)
    4. [Entry Callback](#Entry_Callback)
    5. [Probe](#Probe)
    6. [Caching](#Caching)
    7. [Subscriptions and Reporters](#Subscriptions_and_Reporters)
2. [Built-in entries and probes](#Built-in_entries_and_probes)
    1. [counter (exometer native)](#counter_(exometer_native))
    2. [fast_counter (exometer native)](#fast_counter_(exometer_native))
    3. [gauge (exometer native)](#gauge_(exometer_native))
    4. [exometer_histogram (probe)](#exometer_histogram_(probe))
    5. [exometer_uniform (probe)](#exometer_uniform_(probe))
    6. [exometer_spiral (probe)](#exometer_spiral_(probe))
    7. [exometer_folsom [entry]](#exometer_folsom_[entry])
    8. [exometer_function [entry]](#exometer_function_[entry])
3. [Built in Reporters](#Built_in_Reporters)
    1. [exometer_report_graphite](#exometer_report_graphite)
    2. [exometer_report_opentsdb](#exometer_report_opentsdb)
    3. [exometer_report_amqp](#exometer_report_amqp)
    4. [exometer_report_snmp](#exometer_report_snmp)
4. [Instrumenting Erlang code](#Instrumenting_Erlang_code)
    1. [Exometer Start](#Exometer_Start)
    2. [Creating metrics](#Creating_metrics)
    3. [Deleting metrics](#Deleting_metrics)
    4. [Setting metric values](#Setting_metric_values)
    5. [Retrieving metric values](#Retrieving_metric_values)
    6. [Setting up subscriptions](#Setting_up_subscriptions)
    7. [Set metric options](#Set_metric_options)
5. [Configuring Exometer](#Configuring_Exometer)
    1. [Configuring type - entry maps](#Configuring_type_-_entry_maps)
    2. [Configuring statically defined entries](#Configuring_statically_defined_entries)
    3. [Configuring static subscriptions](#Configuring_static_subscriptions)
    4. [Configuring reporter plugins](#Configuring_reporter_plugins)
    5. [Configuring opentsdb reporter](#Configuring_opentsdb_reporter)
    6. [Configuring amqp reporter](#Configuring_amqp_reporter)
    7. [Configuring graphite reporter](#Configuring_graphite_reporter)
    8. [Configuring snmp reporter](#Configuring_snmp_reporter)
6. [Creating custom exometer entries](#Creating_custom_exometer_entries)
7. [Creating custom probes](#Creating_custom_probes)
8. [Creating custom reporter plugins](#Creating_custom_reporter_plugins)
9. [Dependency management](#Dependency_management)


### <a name="Concepts_and_Definitions">Concepts and Definitions</a> ###

Exometer introduces a number of concepts and definitions used
throughout the documentation and the code.

![Overview](/doc/exometer_overview.png?raw=true)


#### <a name="Metric">Metric</a> ####

A metric is a specific measurement sampled inside an Erlang system and
then reported to the Exometer system. An example metric would be
"transactions_per_second", or "memory_usage".

Metrics are identified by a list of terms, such as given below:

`[ xml_front_end, parser, file_size ]`

A metric is created through a call by the code to be instrumented to
`exometer:new()`. Once created, the metric can be updated through
`exometer:update()`, or on its own initiative through the
`exometer_probe:sample` behavior implementation.


#### <a name="Data_Point">Data Point</a> ####

Each metric can consist of multiple data points, where each point has
a specific value.

A typical example of data points would be a
`transactions_per_second` (tps) metric, usually stored as a
histogram covering the last couple of minutes of tps samples. Such a
histogram would host multiple values, such as `min`, `max`,
`median`, `mean`, `50_percentile`, `75_percentile`,
etc.

It is up to the type of the metric, and the data probe backing that
type (see below), to specify which data points are available under the
given metric.


#### <a name="Metric_Type">Metric Type</a> ####

The type of a metric, specified when the metric is created through
`exometer:new()`, determines which `exometer_entry`
callback to use.

The link between the type and the entry to use is configured
through the `exometer_admin` module, and its associated exometer
defaults configuration data.

The metric type, in other words, is mainly used to map a metric to a
configurable `exometer_entry` callback, but it can also be referenced
in queries using `exometer:select/1`. An entry callback can also support
multiple types (the type is provided as an argument in the callback functions).

Exometer provides default mappings for a number of metric types. It is
possible to select different callbacks for each metric instance, as well
as modify metrics using callback-specific options. Please see
[Configuring type - entry maps](#Configuring_type_-_entry_maps) for details on how to do this.


#### <a name="Entry_Callback">Entry Callback</a> ####

An exometer entry callback will receive values reported to a metric through the
`exometer:update()` call and compile it into one or more data points.
The entry callback can either be a counter (implemented natively
in `exometer`), or a more complex statistical analysis such
as a uniform distribution or a regular histogram.

The various outputs from these entries are reported as data points
under the given metric.

An entry can also interface external analytics packages.
`exometer_folsom`, for example, integrates with the
`folsom_metrics` package found at [`https://github.com/boundary/folsom`](https://github.com/boundary/folsom).


#### <a name="Probe">Probe</a> ####

Probes are a further specialization of exometer entries that run in
their own Erlang processes and have their own state (like a
gen_server). A probe is implemented through the `exometer_probe`
behavior.

A probe can be used if independent monitoring is needed of,
for example, `/proc` trees, network interfaces, and other subsystems
that need periodic sampling. In these cases, the
`exometer_probe:probe_sample()` call is invoked regularly by exometer,
in the probe's own process, in order to extract data from
the given subsystem and add it to the metric's data points.


#### <a name="Caching">Caching</a> ####

Metric and data point values are read with the `exometer:get_value()`
function. In the case of counters, this operation is very fast. With probes,
the call results in a synchronous dialog with the probe process, and the
cost of serving the request depends on the probe implementation and the
nature of the metric being served.

If the cost of reading the value is so high that calling the function often
would result in prohibitive load, it is possible to cache the value. This is
done either explicitly from the probe itself (by calling
`exometer_cache:write()`), or by specifying the option `{cache, Lifetime}`
for the entry. If an entry has a non-zero cache lifetime specified, the
`get_value()` call will try fetching the cached value before calling the
actual entry and automatically caching the result.

Note that if `{cache, Lifetime}` is not specified, `exometer:get_value()`
will neither read nor write to the cache. It is possible for the probe
to periodically cache a value regardless of how the cache lifetime is set,
and the probe may also explicitly read from the cache if it isn't done
automatically.


#### <a name="Subscriptions_and_Reporters">Subscriptions and Reporters</a> ####

The subscription concept, managed by `exometer_report` allows metrics
and their data points to be sampled at given intervals and delivered
to one or more recipients, which can be either an arbitrary process
or a Reporter plugin.

Each subscription ties a specific metric-datapoint pair to a reporter
and an interval (given in milliseconds). The reporter system will, at
the given interval, send the current value of the data point to the
subscribing reporter. The subscription, with all its parameters,
is setup through a call to `exometer_report:subscribe()`.

In the case of processes, subscribed-to values will be delivered as a
message. Modules, which implement the `exometer_report` callback
behavior, will receive the plugins as a callbacks within the
`exometer_report` process.

Subscriptions can either be setup at runtime, through
`exometer_report:subscribe()` calls, or statically through the
`exometer_report` configuration data.


### <a name="Built-in_entries_and_probes">Built-in entries and probes</a> ###


There are a number of built-in entries and probes shipped
with the Exometer package, as described below:


#### <a name="counter_(exometer_native)">counter (exometer native)</a> ####


The counter is implemented directly in `exometer` to provide simple
counters.  A call to `exometer:update()` will add the provided value
to the counter.

The counter can be reset to zero through `exometer:reset()`.

The available data points under a metric using the counter entry
are `value` and `ms_since_reset`.


#### <a name="fast_counter_(exometer_native)">fast_counter (exometer native)</a> ####

A fast counter implements the counter functionality, through the
`trace_info` system, yielding a speed increase of about 3.5 in
comparison to the regular counter.

The tradeoff is that running tracing and/or debugging may interfere
with the counter functionality.

A call to `exometer:update()` will add the provided value to the
counter.

The counter can be reset to zero through `exometer:reset()`.

The available data points under a metric using the fast_counter
entry are `value` and `ms_since_reset`.


#### <a name="gauge_(exometer_native)">gauge (exometer native)</a> ####

The gauge is implemented directly in `exometer` to provide simple
gauges.  A call to `exometer:update()` will set the gauge's value
to the provided value. That is, the value of the gauge entry is
always the most recently provided value.

The gauge can be reset to zero through `exometer:reset()`.

The available data points under a metric using the gauge entry
are `value` and `ms_since_reset`.


#### <a name="histogram_(probe)">histogram (probe)</a> ####

The histogram probe stores a given number of updates, provided through
`exometer:update()`, in a histogram. The histogram maintains a log
derived from all values received during a configurable time span and
provides min, max, median, mean, and percentile analysis data points
for the stored data.

Exometer supports a number of different histogram implementations, each
with different performance and accuracy trade-offs. 

In order to save memory, the histogram is divided into equal-sized
time slots, where each slot spans a settable interval. All values
received during a time slot will be averaged into a single value to be
stored in the histogram once the time slot expires. The averaging
function (which can be replaced by the caller), allows for
high-frequency update metrics to have their resolution traded against
resource consumption.


#### <a name="exometer_uniform_(probe)">exometer_uniform (probe)</a> ####

The uniform probe provides a uniform sample over a pool of values
provided through `exometer:update()`. When the pool reaches its configurable
max size, existing values will be replaced at random to make space for
new values. Much like `exometer_histogram`, the uniform probe
provides min, max, median, mean, and percentile analysis data points
for the stored data.


#### <a name="exometer_spiral_(probe)">exometer_spiral (probe)</a> ####

The spiral probe maintains the total sum of all values stored in its
histogram. The histogram has a configurable time span, all values
provided to the probe, through `exometer:update()`, within that time
span will be summed up and reported. If, for example, the histogram
covers 60 seconds, the spiral probe will report the sum of all
values reported during the last minute.

The grand total of all values received during the lifetime of the
probe is also available.


#### <a name="exometer_folsom_[entry]">exometer_folsom [entry]</a> ####

`exometer_folsom` is an entry behavior which implements most metric types
supported by the [folsom](https://github.com/boundary/folsom)
metrics package: Specifically, the metric types `counter`, `spiral`,
`histogram`, `meter`, `meter_reader`, `gauge`, `duration` and `history`.

The folsom entry integrates with the folsom metrics package provided
by the boundary repo at github. Updated values sent to the folsom entry
can be forwarded to folsom's counter, histogram, duration, meter,
and spiral.

Folsom integration is provided as a backup. New code using Exometer
should use the native probes that duplicate folsom.


#### <a name="exometer_function_[entry]">exometer_function [entry]</a> ####

The function entry allows for an existing erlang function to be wrapped
as an exometer entry. The [`exometer_function`](/Users/uwiger/b4/exometer/deps/exometer_core/doc/exometer_function.md) module supports a number
of options for passing arguments and matching out data points from the
result.

The function entry provides an easy way of integrating an external
system without having to write a complete entry.


### <a name="Built_in_Reporters">Built in Reporters</a> ###

Exometer ships with some built-in reporters which can be used to forward updated
metrics and their data points to external systems. They can also
serve as templates for custom-developed reporters.


#### <a name="exometer_report_graphite">exometer_report_graphite</a> ####

The graphite reporter uses the TCP/IP protocol to forward
subscribed-to metrics and data points to a graphite server, such as
the one provided by [`http://hostedgraphite.com`](http://hostedgraphite.com). When the graphite
reporter receives a metric-datapoint value (subscribed to through
`exometer_report:subscriber()`), the reporter will immediately
forward the key-value pair to the graphite server.


#### <a name="exometer_report_opentsdb">exometer_report_opentsdb</a> ####

The OpenTSDB reporter sends metrics to an OpenTSDB server using
the telnet API. All subscribed-to metric-datapoint values received
by the reporter are immediately forwarded to OpenTSDB.

If the OpenTSDB connection is lost, the reporter will attempt to reconnect to it
at a configurable interval.

The data sent to OpenTSDB will be formatted as follows:

```
put metric timestamp value host=host type=datapoint
```

Where the value for the host tag will be the configured host in the reporter
configuration (defaults to the value returned by `netadm:localhost`), and
datapoint tags as specified by the subscriber.

Please see [Configuring opentsdb reporter](#Configuring_opentsdb_reporter) for details on the
application environment parameters listed above.


#### <a name="exometer_report_amqp">exometer_report_amqp</a> ####

The AMQP reporter sends metrics to an AMQP broker as a json-encoded payload. All
subscribed-to metric-datapoint values received by the reporter are forwarded to AMQP.

If the AMQP connection is lost, the reporter will attempt to reconnect to it
at a configurable interval.

The data sent to AMQP will be formatted as follows:

```
{
  "type":"exometer_metric",
  "body":
    {"name":"messages_per_second",
     "value":0,"timestamp":1414006826,
     "host":"testhost",
     "instance":"max"}
}
```

Where the value for the host tag will be the configured host in the reporter
configuration (defaults to the value returned by `netadm:localhost`), the
instance tag represents the datapoint for the metric.

Please see [Configuring amqp reporter](#Configuring_amqp_reporter) for details on the
application environment parameters listed above.


#### <a name="exometer_report_snmp">exometer_report_snmp</a> ####

The SNMP reporter enables the export of metrics and their datapoints to SNMP managers.
The export needs to be enabled for each metric through their options.
Moreover, SNMP notifications can be created using the options to send periodic reports
on datapoints to SNMP managers. All SNMP protocol handling is done by the snmp application
shipped with Erlang/OTP. Thus, the snmp application needs to be started and
the local SNMP master agent needs to be configured correctly for SNMP export to work
properly.

To configure SNMP export for a single metric use these options:

+ `{snmp, disabled}` (default)<br />Disables SNMP export for the metric. Same as not specifying the option at all.

+ `{snmp, []}`<br />Enables SNMP export for the metric. No subscriptions are setup.

+ `{snmp, [{Datapint, Interval}]}`<br />Enables SNMP export for the metric.<br />Subscriptions are setup for the given Datapoint/Interval pairs.<br />Each subscription report will be forwarded to SNMP mangers as notifications.

+ `{snmp, [{Datapint, Interval, Extra}]}`<br />Same as above, but using an addition extra identification for the subscriptions.<br />Allow the creation ofmultiple subscriptions for a single datapoint.

Please see [Configuring snmp reporter](#Configuring_snmp_reporter) for details on how to configure the
SNMP reporter.


### <a name="Instrumenting_Erlang_code">Instrumenting Erlang code</a> ###

The code using Exometer needs to be instrumented in order to setup and
use metrics reporting.


#### <a name="Exometer_Start">Exometer Start</a> ####

The system using Exometer must start the `exometer` application prior to using it:

```erlang

application:start(lager),
application:start(exometer).
```

Note that dependent applications need to be started first. On newer OTP versions
(R16B or later), you can use `application:ensure_all_started(exometer)`.

For testing, you can also use [`exometer:start/0`](/Users/uwiger/b4/exometer/deps/exometer_core/doc/exometer.md#start-0).

If you make use of e.g. folsom metrics, you also need to start `folsom`. Exometer
will not do that automatically, nor does it contain an application dependency for it.

See [Configuring Exometer](#Configuring_Exometer) for details on configuration data
format.


#### <a name="Creating_metrics">Creating metrics</a> ####

A metric, can be created throuh a call to

```erlang

exometer:new(Name, Type)
```

`Name` is a list of atoms, uniquely identifying the metric created.
The type of the metric, specified by `Type` will be mapped
to an exometer entry through the table maintained by
`exometer_admin` Please see the [Configuring type - entry
maps](#Configuring_type_-_entry_maps) for details.

The resolved entry to use will determine the data points available
under the given metric.


#### <a name="Deleting_metrics">Deleting metrics</a> ####

A metric previously created with `exometer:new()` can be deleted by
`exometer:delete()`.

All subscriptions to the deleted metrics will be cancelled.


#### <a name="Setting_metric_values">Setting metric values</a> ####

A created metric can have its value updated through the
`exometer:update()` function:

```erlang

exometer:update(Name, Value)
```

The `Name` parameter is the same atom list provided to a previous
`exometer:new()` call. The `Value` is an arbitrarty element that is
forwarded to the `exometer:update()` function of the entry/probe that the
metric is mapped to.

The receiving entry/probe will process the provided value and modify
its data points accordingly.


#### <a name="Retrieving_metric_values">Retrieving metric values</a> ####

Exometer-using code can at any time retrieve the data point values
associated with a previously created metric. In order to find out which
data points are available for a metric, the following call can be used:

```erlang

exometer:info(Name, datapoints)
```

The `Name` parameter is the same atom list provided to a previous
`exometer:new()` call. The call will return a list of data point
atoms that can then be provided to `exometer:get_value()` to
retrieve their actual value:

```erlang

exometer:get_value(Name, DataPoint)
```

The `Name` paramer identifies the metric, and `DataPoints`
identifies the data points (returned from the previous `info()` call)
to retrieve the value for.

If no DataPoints are provided, the values of a default list of data points,
determined by the backing entry / probe, will be returned.


#### <a name="Setting_up_subscriptions">Setting up subscriptions</a> ####

A subscription can either be statically configured, or dynamically
setup from within the code using Exometer. For details on statically
configured subscriptions, please see [Configuring static subscriptions](#Configuring_static_subscriptions).

A dynamic subscription can be setup with the following call:

```erlang

exometer_report:subscribe(Recipient, Metric, DataPoint, Inteval)
```

`Recipient` is the name of a reporter.


#### <a name="Set_metric_options">Set metric options</a> ####


Each created metric can have options setup for it through the following call:

```erlang

exometer:setopts(Name, Options)
```

The `Name` paramer identifies the metric to set the options for, and
Options is a proplist (`[{ Key, Value },...]`) with the options to be
set.

Exometer looks up the the backing entry that hosts the metric with the given Name, and will
invoke the entry\'s `setopts/4` function to set the actual options. Please see the
`setopts/4` function for the various entries for details.


### <a name="Configuring_Exometer">Configuring Exometer</a> ###

Exometer defaults can be changed either through OTP application environment
variables or through the use of Basho's `cuttlefish`
([`https://github.com/basho/cuttlefish`](https://github.com/basho/cuttlefish)).


#### <a name="Configuring_type_-_entry_maps">Configuring type - entry maps</a> ####

The dynamic method of configuring defaults for `exometer` entries is:

```erlang

exometer_admin:set_default(NamePattern, Type, Default)
```

Where `NamePattern` is a list of terms describing what is essentially
a name prefix with optional wildcards (`'_'`). A pattern that
matches any legal name is `['_']`.

`Type` is an atom defining a type of metric. The types already known to
`exometer`, `counter`, `fast_counter`, `ticker`, `uniform`, `histogram`,
`spiral`, `netlink`, and `probe` may be redefined, but other types can be
described as well.

`Default` is either an `#exometer_entry{}` record (unlikely), or a list of
`{Key, Value}` options, where the keys correspond to `#exometer_entry` record
attribute names. The following attributes make sense to preset:

```erlang

{module, atom()}              % the callback module
{status, enabled | disabled}  % operational status of the entry
{cache, non_neg_integer()}    % cache lifetime (ms)
{options, [{atom(), any()}]}  % entry-specific options
```

Below is an example, from `exometer/priv/app.config`:

```erlang

{exometer, [
    {defaults, [
        {['_'], function , [{module, exometer_function}]},
        {['_'], counter  , [{module, exometer}]},
        {['_'], histogram, [{module, exometer_histogram}]},
        {['_'], spiral   , [{module, exometer_spiral}]},
        {['_'], duration , [{module, exometer_folsom}]},
        {['_'], meter    , [{module, exometer_folsom}]},
        {['_'], gauge    , [{module, exometer_folsom}]}
    ]}
]}
```

In systems that use CuttleFish, the file `exometer/priv/exometer.schema`
contains a schema for default settings. The setup corresponding to the above
defaults would be as follows:

```ini

exometer.template.function.module  = exometer_function
exometer.template.counter.module   = exometer
exometer.template.histogram.module = exometer_histogram
exometer.template.spiral.module    = exometer_spiral
exometer.template.duration.module  = exometer_folsom
exometer.template.meter.module     = exometer_folsom
exometer.template.gauge.module     = exometer_folsom
```


#### <a name="Configuring_statically_defined_entries">Configuring statically defined entries</a> ####

Using the `exometer` environment variable `predefined`, entries can be added
at application startup. The variable should have one of the following values:

* `{script, File}` - `File` will be processed using `file:script/2`. The return
  value (the result of the last expression in the script) should be a list of`{Name, Type, Options}` tuples.

* `{apply, M, F, A}` - The result of `apply(M, F, A)` should be `{ok, L}` where`L` is a list of `{Name, Type, Options}` tuples.

* `L`, where L is a list of `{Name, Type, Options}` tuples or extended
instructions (see below).

The list of instructions may include:

* `{delete, Name}` - deletes `Name` from the exometer registry.

* `{select_delete, Pattern}` - applies a select pattern and
deletes all matching entries.

* `{re_register, {Name, Type, Options}}` - redefines an entry if present,
otherwise creates it.

Exometer will also scan all loaded applications for the environment
variables `exometer_defaults` and `exometer_predefined`, and process
as above. If an application is loaded and started after exometer has started,
it may call the function `exometer:register_application()` or
`exometer:register_application(App)`. This function will do nothing if
exometer isn't already running, and otherwise process the `exometer_defaults`
and `exometer_predefined` variables as above. The function can also be
called during upgrade, as it will re-apply the settings each time.


#### <a name="Configuring_static_subscriptions">Configuring static subscriptions</a> ####


Static subscriptions, which are automatically setup at exometer
startup without having to invoke `exometer_report:subscribe()`, are
configured through the report sub section under exometer.

Below is an example, from `exometer/priv/app.config`:

```erlang

{exometer, [
    {report, [
        {subscribers, [
            {exometer_report_collectd, [db, cache, hits], mean, 2000, true},
            {exometer_report_collectd, [db, cache, hits], max, 5000, false}
        ]}
    ]}
]}
```

The `report` section configures static subscriptions and reporter
plugins. See [Configuring reporter plugins](#Configuring_reporter_plugins) for details on
how to configure individual plugins.

The `subscribers` sub-section contains all static subscriptions to be
setup att exometer applications start. Each tuple in the prop list
should be of one of the following formats:

* `{Reporter, Metric, DataPoint, Interval}`

* `{Reporter, Metric, DataPoint, Interval, RetryFailedMetrics}`

* `{Reporter, Metric, DataPoint, Interval, RetryFailedMetrics, Extra}`

* `{apply, {M, F, A}}`

* `{select, {MatchPattern, DataPoint, Interval [, Retry [, Extra] ]}}`

In the case of `{apply, M, F, A}`, the result of `apply(M, F, A)` must
be a list of `subscribers` tuples.

In the case of `{select, Expr}`, a list of metrics is fetched using
`exometer:select(MatchPattern)`, where the result must be on the form
`{Key, Type, Status}` (i.e. what corresponds to `'$_'`).
The rest of the items will be applied to each of the matching entries.

The meaning of the above tuple elements is:

+ `Reporter :: module()`<br />Specifies the reporter plugin module, such as`exometer_report_collectd` that is to receive updated metric's data
points.

+ `Metric :: [atoms()]`<br />Specifies the path to a metric previously created with an`exometer:new()` call.

+ `DataPoint` ::  atom() | [atom()]'<br />Specifies the data point within the given metric to send to the
    receiver. The data point must match one of the data points returned by`exometer:info(Name, datapoints)` for the given metrics name.

+ `Interval` :: integer()' (milliseconds)<br />Specifies the interval, in milliseconds, between each update of the
given metric's data point. At the given interval, the data point will
be samples, and the result will be sent to the receiver.

+ `RetryFailedMetrics :: boolean()`<br />Specifies if the metric should be continued to be reported
    even if it is not found during a reporting cycle. This would be
    the case if a metric is not created by the time it is reported for
    the first time. If the metric will be created at a later time,
    this value should be set to true. Set this value to false if all
    attempts to report the metric should stop if when is not found.
    The default value is `true`.

+ `Extra :: any()`<br />Provides a means to pass along extra information for a given
   subscription. An example is the `syntax` option for the SNMP reporter,
   in which case `Extra` needs to be a property list.

Example configuration in sys.config, using the `{select, Expr}` pattern:

```erlang

[
 {exometer, [
             {predefined,
              [{[a,1], counter, []},
               {[a,2], counter, []},
               {[b,1], counter, []},
               {[c,1], counter, []}]},
             {report,
              [
               {reporters,
                [{exometer_report_tty, []}]},
               {subscribers,
                [{select, {[{ {[a,'_'],'_','_'}, [], ['$_']}],
                           exometer_report_tty, value, 1000}}]}
              ]}
            ]}
].

```

This will activate a subscription on `[a,1]` and `[a,2]` in the
`exometer_report_tty` reporter, firing once per second.


#### <a name="Configuring_reporter_plugins">Configuring reporter plugins</a> ####


The various reporter plugins to be loaded by exometer are configured
in the `report` section under `reporters`

Each reporter has an entry named after its module, and the content of
that entry is dependent on the reporter itself. The following chapters
specifies the configuration parameters for the reporters shipped with
exometer.


#### <a name="Configuring_opentsdb_reporter">Configuring opentsdb reporter</a> ####


Below is an example of the opentsdb reporter application environment, with
its correct location in the hierarchy:

```erlang

{exometer, [
    {report, [
        {reporters, [
            {exometer_report_opentsdb, [
                {reconnect_interval, 10},
                {connect_timeout, 8000},
                {hostname, "testhost"},
                {host, {"127.0.0.1", 4242}}
            ]}
        ]}
    ]}
]}
```

The following attributes are available for configuration:

+ `reconnect_interval` (seconds - default: 30)<br />Specifies the duration between each reconnect attempt to an opentsdb
server that is not available. Should the server either be unavailable
at exometer startup, or become unavailable during exometer's
operation, exometer will attempt to reconnect at the given number of
seconds.

+ `connect_timeout` (milliseconds - default: 5000)<br />Specifies how long the opentsdb reporter plugin shall wait for a
socket connection to complete before timing out. A timed out
connection attempt will be retried after the reconnect interval has
passed see item 1 above).

+ `hostname` (string - default: `net_adm:localhost()`)<br />Specifies the host name to use for the host tag in the OpenTSDB tags.
    Please see [Configuring opentsdb reporter](#Configuring_opentsdb_reporter) for details.

+ `host` (ip - default: {"127.0.0.1", 4242})<br />Specifies the host and port to connect to OpenTSDB.


#### <a name="Configuring_amqp_reporter">Configuring amqp reporter</a> ####


Below is an example of the amqp reporter application environment, with
its correct location in the hierarchy:

```erlang

{exometer, [
    {report, [
        {reporters, [
            {exometer_report_amqp, [
                {reconnect_interval, 10},
                {hostname, "testhost"},
                {amqp_url, "amqp://user:pass@host:5672/%2f"},
		{exchange, "metrics"},
		{routing_key, "metrics"},
		{buffer_size, 0}
            ]}
        ]}
    ]}
]}
```

The following attributes are available for configuration:

+ `reconnect_interval` (seconds - default: 30)<br />Specifies the duration between each reconnect attempt to an amqp
broker that is not available. Should the server either be unavailable
at exometer startup, or become unavailable during exometer's
operation, exometer will attempt to reconnect at the given number of
seconds.

+ `hostname` (string - default: `net_adm:localhost()`)<br />Specifies the host name to use for the host property in the JSON payload.
    Please see [Configuring amqp reporter](#Configuring_amqp_reporter) for details.

+ `amqp_url` (string - default: `amqp://guest:guest@localhost:5672/%2f`)<br />Specifies the amqp url to connect to.

+ `exchange` (string - default: `exometer`)<br />Specifies the exchange to publish messages to.

+ `routing_key` (string - default: `exometer`)<br />Specifies the routing key to use when publishing messages.

+ `buffer_size` (integer - default: `0`)<br />Specifies the size in bytes of payload to buffer before sending to AMQP.


#### <a name="Configuring_graphite_reporter">Configuring graphite reporter</a> ####


Below is an example of the a graphite reporter application environment, with
its correct location in the hierarchy:

```erlang

{exometer, [
    {report, [
        {reporters, [
            {exometer_report_graphite, [
                {connect_timeout, 5000},
                {prefix, "web_stats"},
                {host, "carbon.hostedgraphite.com"},
                {port, 2003},
                {api_key, "267d121c-8387-459a-9326-000000000000"}
            ]}
        ]}
    ]}
]}
```

The following attributes are available for configuration:

+ `connect_timeout` (milliseconds - default: 5000)<br />Specifies how long the graphie reporter plugin shall wait for a tcp
connection to complete before timing out. A timed out connection will
not be reconnected to automatically. (To be fixed.)

+ `prefix` (string - default: "")<br />Specifies an optional prefix to prepend all metric names with before
they are sent to the graphite server.

+ `host` (string - default: "carbon.hostedgraphite.com")<br />Specifies the name (or IP address) of the graphite server to report to.

+ `port` (integer - default: 2003)<br />Specifies the TCP port on the given graphite server to connect to.

+ `api_key` (string - default: n/a)<br />Specifies the api key to use when reporting to a hosted graphite server.

If `prefix` is not specified, but `api_key` is, each metrics will be reported as `ApiKey.Metric`.

If `prefix` is specified, but `api_key` is not, each metrics will be reported as `Prefix.Metric`.

if neither `prefix` or `api_key` is specified, each metric will be reported simply as `Metric`.


#### <a name="Configuring_snmp_reporter">Configuring snmp reporter</a> ####


Below is an example of the a snmp reporter application environment, with
its correct location in the hierarchy:

```erlang

{exometer, [
    {report, [
        {reporters, [
            {exometer_report_snmp, [
                {mib_template, "priv/MYORG-EXOMETER-METRICS.mib"},
                {mib_dir, "/tmp/exometer"}
            ]}
        ]}
    ]}
]}
```

The following attributes are available for configuration:

+ `mib_template` (string - default: "mibs/EXOMETER-METRICS-MIB.mib")<br />Specifies where to find the MIB template used for dynamically assembline an internal MIB. Take a look at the MIB template shipped with Exometer for reference in case you want to define your own template.

+ `mib_dir` (string - default: "tmp/exometer_report_snmp")<br />Specifies temporary direction which will be used by Exometer to store dymanically created MIB files.


### <a name="Creating_custom_exometer_entries">Creating custom exometer entries</a> ###


Please see @see exometer_entry documentation for details.


### <a name="Creating_custom_probes">Creating custom probes</a> ###


Please see @see exometer_probe documentation for details.


### <a name="Creating_custom_reporter_plugins">Creating custom reporter plugins</a> ###


Please see @see exometer_report documentation for details.


### <a name="Dependency_management">Dependency management</a> ###


Exometer dependencies can be controlled using the `EXOMETER_PACKAGES`
unix environment variable: a string listing packages or applications to
either keep or remove, separated using space, tab or comma.


#### <a name="Syntax">Syntax</a> ####

+ `(Package)` - use `Package` as a base. This will implicitly exclude all
  applications not included in `Package`. See below for supported packages.

+ `+(Package)` - add applications included in `Package`.

+ `-(Package)` - remove applications in `Package` (except mandatory deps).

+ `App` - keep application `App`.

+ `+App` - keep application `App`.

+ `-App` - exclude application `App`.


#### <a name="Supported_packages">Supported packages</a> ####

+ `minimal` - only the mandatory deps: `lager`, `parse_trans`, `setup`.

+ `basic` - (mandatory deps and) `folsom`.

+ `amqp` - (mandatory deps and) `amqp_client`, `jiffy`.

+ `full` - all of the above, plus `afunix` and `netlink`.

Example - use only basic deps plus `afunix`

```
   EXOMETER_PACKAGES="(basic), +afunix" make
```

Example - use all deps except the AMQP-related deps:

```
   export EXOMETER_PACKAGES="(full) -(amqp)"
```


#### <a name="Conditional_defines">Conditional defines</a> ####

For each optional dependency that is included, a macro is defined,
named `dep_App` - e.g. `dep_afunix`. Developers must not include
compile-time dependencies to optional applications, without checking
the corresponding macro and ensuring that the module compiles even
when the dependent application is not included. See `exometer_report_amqp.erl`
for an example.


#### <a name="Customizing_rebar.config">Customizing rebar.config</a> ####

The OS environment variables `EXOMETER_CONFIG_PREPROCESS` and
`EXOMETER_CONFIG_POSTPROCESS` can be used to insert a script, similar to
`rebar.config.script` in the processing flow of the exometer build.

As the names imply, the script given by `EXOMETER_CONFIG_PREPROCESS` (if any)
will be run before exometer does any processing of its own, and the
`EXOMETER_CONFIG_POSTPROCESS` script (if any) will be run after all other
processing is complete.
Things that could be done in preprocessing: re-targeting a dependency,
modifying the list of predefined packages, etc.

## Modules ##


<table width="100%" border="0" summary="list of modules">
<tr><td><a href="exometer_netlink.md" class="module">exometer_netlink</a></td></tr>
<tr><td><a href="exometer_report_amqp.md" class="module">exometer_report_amqp</a></td></tr>
<tr><td><a href="exometer_report_graphite.md" class="module">exometer_report_graphite</a></td></tr>
<tr><td><a href="exometer_report_opentsdb.md" class="module">exometer_report_opentsdb</a></td></tr>
<tr><td><a href="exometer_report_snmp.md" class="module">exometer_report_snmp</a></td></tr>
<tr><td><a href="exometer_report_statsd.md" class="module">exometer_report_statsd</a></td></tr></table>

