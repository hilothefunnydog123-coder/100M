import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/models.dart';
import 'session.dart';

/// Card deposit setup, fetched when settings open.
final paymentsProvider = FutureProvider.autoDispose<Payments>((ref) async {
  final server = ref.watch(serverProvider);
  if (server == null) return const Payments();
  return server.payments();
});

/// Everyone on the business.
final teamProvider = FutureProvider.autoDispose<List<TeamMember>>((ref) async {
  final server = ref.watch(serverProvider);
  if (server == null) return const [];
  return server.team();
});
