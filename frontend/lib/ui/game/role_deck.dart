import 'dart:math';

/// Balanced role multiset for local demo / quick play (matches RandomRoleScreen).
List<String> buildBalancedRoleDeck(int playerCount) {
  final count = playerCount.clamp(2, 16);
  final evilCount = switch (count) {
    <= 4 => 1,
    <= 7 => 2,
    <= 10 => 3,
    <= 13 => 4,
    _ => 5,
  };
  final neutralCount = count >= 11 ? 2 : (count >= 6 ? 1 : 0);
  final goodCount = (count - evilCount - neutralCount).clamp(1, count);

  const goodCycle = <String>[
    'ชาวบ้าน',
    'ร่างทรง',
    'แพทย์',
    'ทหาร',
    'ตำรวจ',
    'พระธุดงค์',
    'หมอผีคุณไสย',
    'สัปเหร่อ',
  ];
  const evilCycle = <String>[
    'ผีปอบ',
    'ผีกระสือใหญ่',
    'ผีตายโหง',
    'ผีเปรต',
    'หมอผีดำ',
    'ฆาตกรต่อเนื่อง',
  ];
  const neutralCycle = <String>[
    'คนดวงซวย',
    'เจ้ากรรมนายเวร',
  ];

  final roles = <String>[
    for (var i = 0; i < goodCount; i++) goodCycle[i % goodCycle.length],
    for (var i = 0; i < evilCount; i++) evilCycle[i % evilCycle.length],
    for (var i = 0; i < neutralCount; i++) neutralCycle[i % neutralCycle.length],
  ];

  roles.shuffle(Random());
  return roles;
}
