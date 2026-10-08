import 'package:flutter_test/flutter_test.dart';
import 'package:gargosy/core/storage/gargosy_path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Previous extends PathProviderPlatform {
  @override
  Future<String?> getDownloadsPath() async => r'C:\Users\x\Downloads';
}

void main() {
  test('app folders live in userdata\\app; Downloads still comes from Windows', () async {
    final provider = GargosyPathProvider(appDataDir: r'D:\Gargosy\userdata\app', previous: _Previous());
    expect(await provider.getApplicationSupportPath(), p.join(r'D:\Gargosy\userdata\app', 'support'));
    expect(await provider.getApplicationDocumentsPath(), p.join(r'D:\Gargosy\userdata\app', 'documents'));
    expect(await provider.getTemporaryPath(), p.join(r'D:\Gargosy\userdata\app', 'temp'));
    expect(await provider.getApplicationCachePath(), p.join(r'D:\Gargosy\userdata\app', 'cache'));
    expect(await provider.getDownloadsPath(), r'C:\Users\x\Downloads');
  });
}
