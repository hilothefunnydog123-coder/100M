import 'dart:math';

final _random = Random.secure();
const _alphabet = 'abcdefghijkmnpqrstuvwxyz23456789';

/// A random, URL-safe identifier such as `q_7k2mq9x4t8b3n6vw5rza`.
String newId(String prefix, {int length = 20}) {
  final chars = List.generate(
    length,
    (_) => _alphabet[_random.nextInt(_alphabet.length)],
  );
  return '${prefix}_${chars.join()}';
}
