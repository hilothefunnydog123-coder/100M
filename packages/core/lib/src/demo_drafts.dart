import 'ai_draft.dart';
import 'trade.dart';

/// Sample jobs for demo mode, with drafts written the way the model returns
/// them. They go through the same parser and pricing as real drafts.
enum SampleJob {
  livingRoom('living_room', 'Living room repaint', Trade.painting, 3),
  fence('fence', 'Backyard fence', Trade.fencing, 3),
  driveway('driveway', 'Driveway wash', Trade.pressureWashing, 2);

  const SampleJob(this.id, this.title, this.trade, this.photoCount);

  final String id;
  final String title;
  final Trade trade;
  final int photoCount;

  static SampleJob? fromId(Object? id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// The closest sample for a trade, for demo mode with real photos.
  static SampleJob forTrade(Trade trade) => switch (trade) {
    Trade.fencing ||
    Trade.decks ||
    Trade.landscaping ||
    Trade.treeService => SampleJob.fence,
    Trade.pressureWashing ||
    Trade.concrete ||
    Trade.cleaning ||
    Trade.gutters ||
    Trade.roofing ||
    Trade.junkRemoval => SampleJob.driveway,
    _ => SampleJob.livingRoom,
  };

  AiDraft get draft => AiDraft.fromJson(switch (this) {
    SampleJob.livingRoom => _livingRoom,
    SampleJob.fence => _fence,
    SampleJob.driveway => _driveway,
  });
}

const _livingRoom = <String, Object?>{
  'photos_usable': true,
  'retake_advice': '',
  'title': 'Living room repaint',
  'summary':
      'Repaint the living room: protect and prep, patch nail holes and '
      'dings, and two coats on the walls, with options to refresh the trim, '
      'door, and ceiling.',
  'observations': [
    'Walls are a flat beige with scuffs behind the sofa and a dozen or so '
        'nail holes from hangings.',
    'Baseboards and casing are white semi-gloss, yellowed, with dings '
        'along the floor.',
    'Two double-hung windows on the back wall and one panel door to the '
        'hall.',
    'Ceiling is flat white and looks sound; no water stains.',
  ],
  'measurements': [
    {
      'name': 'Wall area, less openings',
      'quantity': 400,
      'unit': 'sq_ft',
      'how':
          'Door (80 in) for scale: walls about 15 ft and 13 ft, 8 ft '
          'ceiling. 448 sq ft gross, less one door and two windows.',
      'confidence': 'medium',
    },
    {
      'name': 'Baseboard and casing',
      'quantity': 120,
      'unit': 'ln_ft',
      'how': '53 ft of baseboard plus casing on one door and two windows.',
      'confidence': 'medium',
    },
    {
      'name': 'Ceiling',
      'quantity': 195,
      'unit': 'sq_ft',
      'how': '15 ft by 13 ft.',
      'confidence': 'high',
    },
  ],
  'tiers': [
    {
      'id': 'walls',
      'name': 'Walls only',
      'summary': 'Two coats of standard paint on the walls.',
      'recommended': false,
    },
    {
      'id': 'walls_trim',
      'name': 'Walls + trim',
      'summary':
          'Premium, scrubbable paint on the walls, plus fresh baseboards, '
          'casing, and the door.',
      'recommended': true,
    },
    {
      'id': 'full_room',
      'name': 'Full room',
      'summary': 'Everything in Walls + trim, plus the ceiling.',
      'recommended': false,
    },
  ],
  'items': [
    {
      'section': 'Prep',
      'description': 'Move and cover furniture, mask floors and trim',
      'detail': '',
      'quantity': 1,
      'unit': 'lot',
      'price_list_id': '',
      'labor_hours': 2,
      'material_cost': 35,
      'other_cost': 0,
      'tiers': <String>[],
      'basis': 'Two people, one hour: drop cloths, plastic, and tape.',
    },
    {
      'section': 'Prep',
      'description': 'Fill nail holes and dings, sand, spot-prime',
      'detail': '',
      'quantity': 1,
      'unit': 'lot',
      'price_list_id': '',
      'labor_hours': 1.5,
      'material_cost': 20,
      'other_cost': 0,
      'tiers': <String>[],
      'basis':
          'About 15 small holes and a few dings; spackle, sanding sponges, '
          'and a quart of primer.',
    },
    {
      'section': 'Walls',
      'description': 'Paint walls, 2 coats',
      'detail': 'Standard acrylic, eggshell',
      'quantity': 400,
      'unit': 'sq_ft',
      'price_list_id': '',
      'labor_hours': 4.5,
      'material_cost': 114,
      'other_cost': 0,
      'tiers': ['walls'],
      'basis':
          '400 sq ft x 2 coats at ~175 sq ft/hr = 4.5 hr. 3 gal at \$38 '
          '(375 sq ft/gal per coat).',
    },
    {
      'section': 'Walls',
      'description': 'Paint walls, 2 coats',
      'detail': 'Premium scrubbable acrylic, eggshell',
      'quantity': 400,
      'unit': 'sq_ft',
      'price_list_id': '',
      'labor_hours': 4.5,
      'material_cost': 186,
      'other_cost': 0,
      'tiers': ['walls_trim', 'full_room'],
      'basis': 'Same labor as standard; 3 gal of premium at \$62.',
    },
    {
      'section': 'Trim',
      'description': 'Paint baseboards and window and door casing',
      'detail': '2 coats, semi-gloss',
      'quantity': 120,
      'unit': 'ln_ft',
      'price_list_id': '',
      'labor_hours': 4.5,
      'material_cost': 58,
      'other_cost': 0,
      'tiers': ['walls_trim', 'full_room'],
      'basis': '120 ln ft x 2 coats at ~55 ln ft/hr. 1 gal semi-gloss.',
    },
    {
      'section': 'Trim',
      'description': 'Paint door and frame, both sides',
      'detail': '',
      'quantity': 1,
      'unit': 'each',
      'price_list_id': '',
      'labor_hours': 1.5,
      'material_cost': 0,
      'other_cost': 0,
      'tiers': ['walls_trim', 'full_room'],
      'basis': 'Panel door, about 45 min a side; paint from the trim gallon.',
    },
    {
      'section': 'Ceiling',
      'description': 'Paint ceiling, 1 coat',
      'detail': 'Flat ceiling white',
      'quantity': 195,
      'unit': 'sq_ft',
      'price_list_id': '',
      'labor_hours': 2,
      'material_cost': 36,
      'other_cost': 0,
      'tiers': ['full_room'],
      'basis': '195 sq ft at ~120 sq ft/hr plus cut-in. 1 gal ceiling white.',
    },
    {
      'section': 'Cleanup',
      'description': 'Clean up, pull masking, haul off trash',
      'detail': '',
      'quantity': 1,
      'unit': 'lot',
      'price_list_id': '',
      'labor_hours': 0.75,
      'material_cost': 0,
      'other_cost': 0,
      'tiers': <String>[],
      'basis': '',
    },
  ],
  'assumptions': [
    {
      'text':
          'Staying in a similar color. A dark-to-light change can need a '
          'third coat.',
      'impact': 'high',
    },
    {
      'text': 'Ceiling is about 8 ft, judged against the 80 in door.',
      'impact': 'medium',
    },
    {
      'text': 'Only small patches: no drywall repair beyond nail holes.',
      'impact': 'medium',
    },
    {
      'text': 'Customer takes down pictures and small items before we start.',
      'impact': 'low',
    },
  ],
  'exclusions': [
    'Moving pianos, safes, or wall-mounted TVs',
    'Drywall repair beyond small patches',
    'Closet interiors',
  ],
  'crew': {'people': 2, 'days': 1},
  'customer_message':
      'Thanks for having us out. Here are three ways to do the living room; '
      "the middle one is what I'd pick: better paint on the walls and fresh "
      'trim. Happy to walk through any of it.',
  'confidence': 'medium',
  'confidence_note':
      'Clear photos of all four walls. Wall height is judged from the door, '
      'so confirm it on site.',
};

const _fence = <String, Object?>{
  'photos_usable': true,
  'retake_advice': '',
  'title': 'Backyard fence replacement',
  'summary':
      'Tear out the old 6 ft privacy fence and build a new one on the same '
      'line: new posts set in concrete, new rails and pickets, and a new '
      'walk gate.',
  'observations': [
    'Existing 6 ft dog-ear privacy fence, gray and weathered.',
    'Several posts lean and a few pickets are cracked or missing.',
    'One 4 ft walk gate that sags and drags on the ground.',
    'Level grass yard along the whole run; clear access for a wheelbarrow.',
  ],
  'measurements': [
    {
      'name': 'Fence run',
      'quantity': 96,
      'unit': 'ln_ft',
      'how': '12 sections between posts, about 8 ft each.',
      'confidence': 'medium',
    },
    {
      'name': 'Posts',
      'quantity': 14,
      'unit': 'each',
      'how': '13 line posts plus a second gate post.',
      'confidence': 'high',
    },
  ],
  'tiers': [
    {
      'id': 'pine',
      'name': 'Pressure-treated pine',
      'summary': 'Treated pine pickets and gate. Solid and budget-friendly.',
      'recommended': false,
    },
    {
      'id': 'cedar',
      'name': 'Cedar',
      'summary':
          'Western red cedar pickets and gate: straighter, and it weathers '
          'better.',
      'recommended': true,
    },
    {
      'id': 'cedar_cap',
      'name': 'Cedar + cap & trim',
      'summary': 'Cedar with a top cap and trim board for a finished look.',
      'recommended': false,
    },
  ],
  'items': [
    {
      'section': 'Removal',
      'description': 'Tear out old fence and haul it away',
      'detail': 'Includes dump fee',
      'quantity': 96,
      'unit': 'ln_ft',
      'price_list_id': '',
      'labor_hours': 7.5,
      'material_cost': 0,
      'other_cost': 95,
      'tiers': <String>[],
      'basis':
          'About 0.08 hr per ft for pickets, rails, and pulling posts. '
          'One trailer load at the transfer station, \$95.',
    },
    {
      'section': 'Posts',
      'description': 'Set new 4x4 pressure-treated posts in concrete',
      'detail': '8 ft posts, 2 bags of concrete each',
      'quantity': 14,
      'unit': 'each',
      'price_list_id': '',
      'labor_hours': 8.5,
      'material_cost': 406,
      'other_cost': 0,
      'tiers': <String>[],
      'basis': '14 posts at \$16 plus 28 bags of concrete at \$6.50.',
    },
    {
      'section': 'Fence',
      'description': 'Build 6 ft privacy fence',
      'detail': 'Pressure-treated pine rails and dog-ear pickets',
      'quantity': 96,
      'unit': 'ln_ft',
      'price_list_id': '',
      'labor_hours': 16,
      'material_cost': 1035,
      'other_cost': 0,
      'tiers': ['pine'],
      'basis':
          '36 rails at \$9, 210 pickets at \$3.10, \$60 of screws and nails. '
          'About 0.17 hr per ft for two people.',
    },
    {
      'section': 'Fence',
      'description': 'Build 6 ft privacy fence',
      'detail': 'Treated rails, western red cedar dog-ear pickets',
      'quantity': 96,
      'unit': 'ln_ft',
      'price_list_id': '',
      'labor_hours': 16,
      'material_cost': 1476,
      'other_cost': 0,
      'tiers': ['cedar', 'cedar_cap'],
      'basis': '36 rails at \$9, 210 cedar pickets at \$5.20, \$60 fasteners.',
    },
    {
      'section': 'Gate',
      'description': '4 ft walk gate with hinges and latch',
      'detail': 'Pressure-treated pine',
      'quantity': 1,
      'unit': 'each',
      'price_list_id': '',
      'labor_hours': 3,
      'material_cost': 120,
      'other_cost': 0,
      'tiers': ['pine'],
      'basis': 'Framed gate with anti-sag kit and a self-closing latch.',
    },
    {
      'section': 'Gate',
      'description': '4 ft walk gate with hinges and latch',
      'detail': 'Cedar',
      'quantity': 1,
      'unit': 'each',
      'price_list_id': '',
      'labor_hours': 3,
      'material_cost': 170,
      'other_cost': 0,
      'tiers': ['cedar', 'cedar_cap'],
      'basis': 'Same build with cedar pickets.',
    },
    {
      'section': 'Fence',
      'description': 'Add cedar top cap and trim board',
      'detail': '',
      'quantity': 96,
      'unit': 'ln_ft',
      'price_list_id': '',
      'labor_hours': 5,
      'material_cost': 250,
      'other_cost': 0,
      'tiers': ['cedar_cap'],
      'basis': '2x6 cap and 1x4 trim, about \$2.60 per ft.',
    },
  ],
  'assumptions': [
    {
      'text': 'The run is about 96 ft: 12 sections at roughly 8 ft.',
      'impact': 'high',
    },
    {
      'text': 'Normal digging: no rock, big roots, or old concrete to break.',
      'impact': 'medium',
    },
    {
      'text': 'Same fence line, and the property line is not in question.',
      'impact': 'medium',
    },
    {'text': 'Utilities get marked (811) before we dig.', 'impact': 'low'},
  ],
  'exclusions': [
    'Permit, if your city requires one',
    'Breaking out old concrete footings that do not pull',
    'Stain or sealer',
  ],
  'crew': {'people': 2, 'days': 2},
  'customer_message':
      'Thanks for showing me the fence. Most folks go with cedar since it '
      'stays straighter and looks better longer, but the pine is a solid '
      'fence too. Let me know which way you want to go.',
  'confidence': 'medium',
  'confidence_note':
      'The run is counted by sections; a tape measure on site will confirm '
      'the footage.',
};

const _driveway = <String, Object?>{
  'photos_usable': true,
  'retake_advice': '',
  'title': 'Driveway and walkway wash',
  'summary':
      'Pre-treat stains, surface-clean the driveway, wash the front walk, and '
      'rinse, with the option to seal the driveway afterward.',
  'observations': [
    'Two-car concrete driveway with dark traffic lanes and an oil spot near '
        'the garage.',
    'Green algae along the edges and in the control joints.',
    'Front walkway and two steps, same condition.',
  ],
  'measurements': [
    {
      'name': 'Driveway',
      'quantity': 720,
      'unit': 'sq_ft',
      'how': 'Two-car garage door (16 ft) for scale: about 18 ft by 40 ft.',
      'confidence': 'medium',
    },
    {
      'name': 'Walkway and steps',
      'quantity': 110,
      'unit': 'sq_ft',
      'how': 'About 3.5 ft wide by 28 ft, plus two steps.',
      'confidence': 'medium',
    },
  ],
  'tiers': [
    {
      'id': 'wash',
      'name': 'Wash',
      'summary': 'Deep clean the driveway and walkway.',
      'recommended': false,
    },
    {
      'id': 'wash_seal',
      'name': 'Wash + seal',
      'summary':
          'Wash, then a penetrating sealer so stains and algae come back '
          'slower.',
      'recommended': true,
    },
  ],
  'items': [
    {
      'section': 'Cleaning',
      'description': 'Pre-treat oil and algae stains',
      'detail': '',
      'quantity': 1,
      'unit': 'lot',
      'price_list_id': '',
      'labor_hours': 0.5,
      'material_cost': 18,
      'other_cost': 0,
      'tiers': <String>[],
      'basis': 'Degreaser on the oil spot; mild bleach mix on the edges.',
    },
    {
      'section': 'Cleaning',
      'description': 'Surface-clean driveway',
      'detail': '',
      'quantity': 720,
      'unit': 'sq_ft',
      'price_list_id': '',
      'labor_hours': 1.25,
      'material_cost': 12,
      'other_cost': 0,
      'tiers': <String>[],
      'basis': '720 sq ft at about 600 sq ft/hr with a surface cleaner.',
    },
    {
      'section': 'Cleaning',
      'description': 'Wash front walkway and steps',
      'detail': '',
      'quantity': 110,
      'unit': 'sq_ft',
      'price_list_id': '',
      'labor_hours': 0.5,
      'material_cost': 0,
      'other_cost': 0,
      'tiers': <String>[],
      'basis': '',
    },
    {
      'section': 'Cleaning',
      'description': 'Post-treat and rinse',
      'detail': '',
      'quantity': 1,
      'unit': 'lot',
      'price_list_id': '',
      'labor_hours': 0.4,
      'material_cost': 0,
      'other_cost': 0,
      'tiers': <String>[],
      'basis': '',
    },
    {
      'section': 'Sealing',
      'description': 'Apply penetrating concrete sealer',
      'detail': 'After a full day of drying',
      'quantity': 720,
      'unit': 'sq_ft',
      'price_list_id': '',
      'labor_hours': 1.5,
      'material_cost': 128,
      'other_cost': 0,
      'tiers': ['wash_seal'],
      'basis': '4 gal at \$32, about 200 sq ft/gal on broom-finish concrete.',
    },
  ],
  'assumptions': [
    {'text': 'Driveway is about 720 sq ft (18 ft by 40 ft).', 'impact': 'high'},
    {'text': 'Outdoor water spigot works at the house.', 'impact': 'medium'},
    {
      'text': 'The oil spot will lighten a lot but may not fully disappear.',
      'impact': 'low',
    },
  ],
  'exclusions': ['Garage floor', 'House siding and windows'],
  'crew': {'people': 1, 'days': 0.5},
  'customer_message':
      'Thanks for reaching out. The driveway will come up a lot brighter; '
      "sealing it after is worth it if you'd like it to stay that way. Let "
      'me know which option works.',
  'confidence': 'medium',
  'confidence_note': 'Size is judged from the garage door; confirm on site.',
};
