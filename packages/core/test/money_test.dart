import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:test/test.dart';

void main() {
  group('Money.format', () {
    test('whole dollars drop the cents', () {
      expect(Money.format(485000), r'$4,850');
      expect(Money.format(0), r'$0');
      expect(Money.format(123456789), r'$1,234,567.89');
    });

    test('cents when present or forced', () {
      expect(Money.format(1050), r'$10.50');
      expect(Money.format(1000, cents: true), r'$10.00');
      expect(Money.format(-2500), r'-$25');
    });
  });

  group('Money.parse', () {
    test('accepts the ways people type money', () {
      expect(Money.parse(r'$1,234.50'), 123450);
      expect(Money.parse('1234'), 123400);
      expect(Money.parse(' 2.5 '), 250);
      expect(Money.parse('.99'), 99);
    });

    test('rejects everything else', () {
      expect(Money.parse(''), isNull);
      expect(Money.parse('abc'), isNull);
      expect(Money.parse('-5'), isNull);
      expect(Money.parse('1.2.3'), isNull);
    });
  });

  test('roundNice rounds like a contractor writes prices', () {
    expect(Money.roundNice(5410), 5400); // $54.10 -> $54
    expect(Money.roundNice(9960), 10000); // $99.60 -> $100
    expect(Money.roundNice(16200), 16000); // $162 -> $160
    expect(Money.roundNice(16300), 16500); // $163 -> $165
    expect(Money.roundNice(247763), 248000); // $2,477.63 -> $2,480
    expect(Money.roundNice(30), 100); // never rounds a charge to zero
    expect(Money.roundNice(0), 0);
    expect(Money.roundNice(-500), 0);
  });

  test('roundDollars', () {
    expect(Money.roundDollars(31125), 31100);
    expect(Money.roundDollars(31150), 31200);
  });

  group('quantities', () {
    test('formatQuantity', () {
      expect(formatQuantity(1240), '1,240');
      expect(formatQuantity(2.5), '2.5');
      expect(formatQuantity(0.75), '0.75');
      expect(formatQuantity(1240.25), '1,240.25');
      expect(formatQuantity(3.999), '4');
    });

    test('describeQuantity hides lump sums and pluralizes', () {
      expect(describeQuantity(1240, Unit.sqFt), '1,240 sq ft');
      expect(describeQuantity(1, Unit.hour), '1 hr');
      expect(describeQuantity(3, Unit.hour), '3 hrs');
      expect(describeQuantity(1, Unit.lot), '');
      expect(describeQuantity(1, Unit.each), '');
      expect(describeQuantity(3, Unit.each), '3 ea');
    });

    test('unknown unit ids fall back to each', () {
      expect(Unit.fromId('furlong'), Unit.each);
      expect(Unit.fromId('sq_ft'), Unit.sqFt);
    });
  });
}
