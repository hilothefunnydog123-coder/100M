/// A small Prometheus registry: counters, histograms, and gauges read at
/// scrape time, rendered in the text exposition format.
class Metrics {
  final _families = <String, _Family>{};

  Counter counter(String name, String help, {List<String> labels = const []}) =>
      _register(name, () => Counter._(name, help, labels)) as Counter;

  Histogram histogram(
    String name,
    String help, {
    List<String> labels = const [],
    List<double> buckets = const [
      0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, //
    ],
  }) =>
      _register(name, () => Histogram._(name, help, labels, buckets))
          as Histogram;

  void gauge(String name, String help, num Function() read) =>
      _register(name, () => _Gauge(name, help, read));

  _Family _register(String name, _Family Function() create) {
    final existing = _families[name];
    if (existing != null) return existing;
    return _families[name] = create();
  }

  String render() {
    final b = StringBuffer();
    for (final f in _families.values) {
      b
        ..writeln('# HELP ${f.name} ${f.help}')
        ..writeln('# TYPE ${f.name} ${f.type}');
      f.write(b);
    }
    return b.toString();
  }
}

abstract class _Family {
  _Family(this.name, this.help);

  final String name;
  final String help;
  String get type;
  void write(StringBuffer b);
}

String _labels(List<String> names, List<String> values, [String extra = '']) {
  final parts = [
    for (var i = 0; i < names.length; i++)
      '${names[i]}="${_escape(values[i])}"',
    if (extra.isNotEmpty) extra,
  ];
  return parts.isEmpty ? '' : '{${parts.join(',')}}';
}

String _escape(String v) =>
    v.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n');

String _number(num v) {
  if (v is int || v == v.roundToDouble() && v.abs() < 1e15) {
    return v.toInt().toString();
  }
  return v.toString();
}

class Counter extends _Family {
  Counter._(super.name, super.help, this.labelNames);

  final List<String> labelNames;
  final _values = <String, (List<String>, double)>{};

  @override
  String get type => 'counter';

  void inc([List<String> labels = const [], num by = 1]) {
    assert(labels.length == labelNames.length, 'Label count for $name');
    final key = labels.join('\u0000');
    final current = _values[key]?.$2 ?? 0;
    _values[key] = (labels, current + by);
  }

  double value([List<String> labels = const []]) =>
      _values[labels.join('\u0000')]?.$2 ?? 0;

  @override
  void write(StringBuffer b) {
    for (final (labels, v) in _values.values) {
      b.writeln('$name${_labels(labelNames, labels)} ${_number(v)}');
    }
  }
}

class Histogram extends _Family {
  Histogram._(super.name, super.help, this.labelNames, this.buckets);

  final List<String> labelNames;
  final List<double> buckets;
  final _series = <String, _Series>{};

  @override
  String get type => 'histogram';

  void observe(double value, [List<String> labels = const []]) {
    final s = _series.putIfAbsent(
      labels.join('\u0000'),
      () => _Series(labels, List.filled(buckets.length, 0)),
    );
    for (var i = 0; i < buckets.length; i++) {
      if (value <= buckets[i]) s.counts[i]++;
    }
    s.count++;
    s.sum += value;
  }

  int count([List<String> labels = const []]) =>
      _series[labels.join('\u0000')]?.count ?? 0;

  @override
  void write(StringBuffer b) {
    for (final s in _series.values) {
      for (var i = 0; i < buckets.length; i++) {
        b.writeln(
          '${name}_bucket'
          '${_labels(labelNames, s.labels, 'le="${_number(buckets[i])}"')} '
          '${s.counts[i]}',
        );
      }
      b
        ..writeln(
          '${name}_bucket${_labels(labelNames, s.labels, 'le="+Inf"')} '
          '${s.count}',
        )
        ..writeln('${name}_sum${_labels(labelNames, s.labels)} ${s.sum}')
        ..writeln('${name}_count${_labels(labelNames, s.labels)} ${s.count}');
    }
  }
}

class _Series {
  _Series(this.labels, this.counts);

  final List<String> labels;
  final List<int> counts;
  int count = 0;
  double sum = 0;
}

class _Gauge extends _Family {
  _Gauge(super.name, super.help, this.read);

  final num Function() read;

  @override
  String get type => 'gauge';

  @override
  void write(StringBuffer b) => b.writeln('$name ${_number(read())}');
}
