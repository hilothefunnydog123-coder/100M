/// Shared model for Jobwalk.
///
/// The split that keeps quotes accurate lives here: the model estimates
/// scope, quantities, hours, and material costs; [Pricing] turns those into
/// prices with the contractor's own rates, in integer cents.
library;

export 'src/ai_draft.dart';
export 'src/demo_drafts.dart';
export 'src/draft_request.dart';
export 'src/ids.dart';
export 'src/line_item.dart';
export 'src/money.dart';
export 'src/price_memory.dart';
export 'src/pricing.dart';
export 'src/profile.dart';
export 'src/public_quote.dart';
export 'src/quote.dart';
export 'src/quote_builder.dart';
export 'src/rates.dart';
export 'src/trade.dart';
export 'src/units.dart';
