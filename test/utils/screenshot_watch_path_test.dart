import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/utils/screenshot_watch_path.dart';

void main() {
  test('normalize strips storage root', () {
    expect(
      ScreenshotWatchPath.normalize('/storage/emulated/0/Pictures/Screenshots/'),
      'Pictures/Screenshots',
    );
    expect(
      ScreenshotWatchPath.normalize('/sdcard/DCIM/Screenshots'),
      'DCIM/Screenshots',
    );
  });

  test('normalize rejects content uri', () {
    expect(
      ScreenshotWatchPath.normalize(
        'content://com.android.externalstorage.documents/tree/primary%3APictures',
      ),
      isNull,
    );
  });

  test('displayAbsolute joins storage root and relative key', () {
    expect(
      ScreenshotWatchPath.displayAbsolute(
        'Pictures/Screenshots',
        '/storage/emulated/0/',
      ),
      '/storage/emulated/0/Pictures/Screenshots',
    );
    expect(
      ScreenshotWatchPath.displayAbsolute(
        '/DCIM/Screenshots/',
        '/storage/emulated/0',
      ),
      '/storage/emulated/0/DCIM/Screenshots',
    );
  });
}
