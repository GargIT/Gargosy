import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/library/continue_elsewhere.dart';

Map<String, dynamic> _save(List<Map<String, dynamic>> syncs) => {'id': 1, 'device_syncs': syncs};

Map<String, dynamic> _sync(String id, String at, {bool current = false, String? name}) => {
  'device_id': id,
  'device_name': ?name,
  'last_synced_at': at,
  'is_current': current,
};

void main() {
  final now = DateTime.utc(2026, 10, 31);

  test('another PC synced a save this one is not current with: its name and when', () {
    final hint = newestElsewhere(
      [
        _save([_sync('me', '2026-10-20T10:00:00Z'), _sync('tv', '2026-10-30T20:00:00Z', name: 'Gargosy on TV')]),
      ],
      'me',
      now: now,
    );
    expect(hint?.deviceName, 'Gargosy on TV');
    expect(hint?.at, DateTime.utc(2026, 10, 30, 20));
  });

  test('nothing when this PC has the newest, the other sync is old, or RomM says nothing of devices', () {
    expect(
      newestElsewhere(
        [
          _save([_sync('me', '2026-10-30T10:00:00Z', current: true), _sync('tv', '2026-10-30T20:00:00Z')]),
        ],
        'me',
        now: now,
      ),
      isNull,
    );
    expect(
      newestElsewhere(
        [
          _save([_sync('tv', '2026-09-01T00:00:00Z')]),
        ],
        'me',
        now: now,
      ),
      isNull,
    );
    expect(
      newestElsewhere(
        [
          {'id': 1},
        ],
        'me',
        now: now,
      ),
      isNull,
    );
  });

  test('a device without a name is another PC (null)', () {
    expect(
      newestElsewhere(
        [
          _save([_sync('tv', '2026-10-30T20:00:00Z')]),
        ],
        'me',
        now: now,
      )?.deviceName,
      isNull,
    );
  });

  test("only each slot's newest save counts: an old version this PC skipped says nothing", () {
    final hint = newestElsewhere(
      [
        {
          ..._save([_sync('me', '2026-10-30T12:00:00Z', current: true)]),
          'id': 11,
          'slot': 'main',
          'updated_at': '2026-10-30T12:00:00Z',
        },
        {
          ..._save([_sync('tv', '2026-10-29T12:00:00Z', name: 'TV')]),
          'id': 10,
          'slot': 'main',
          'updated_at': '2026-10-29T12:00:00Z',
        },
      ],
      'me',
      now: now,
    );
    expect(hint, isNull);
  });
}
