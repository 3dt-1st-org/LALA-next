import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

const _androidNamespace = 'http://schemas.android.com/apk/res/android';
const _secureStorageDomain = 'sharedpref';
const _secureStoragePath = 'FlutterSecureStorage';

void main() {
  test('manifest keeps legacy and Android 12+ backup policies', () {
    final manifest = _readXml('android/app/src/main/AndroidManifest.xml');
    final application = manifest.rootElement.getElement('application');

    expect(application, isNotNull);
    expect(
      application!.getAttribute(
        'fullBackupContent',
        namespace: _androidNamespace,
      ),
      '@xml/backup_rules',
    );
    expect(
      application.getAttribute(
        'dataExtractionRules',
        namespace: _androidNamespace,
      ),
      '@xml/data_extraction_rules',
    );
  });

  test('legacy backup excludes FlutterSecureStorage preferences', () {
    final rules = _readXml('android/app/src/main/res/xml/backup_rules.xml');

    expect(rules.rootElement.name.local, 'full-backup-content');
    _expectSecureStorageExcluded(rules.rootElement);
  });

  test(
    'Android 12+ cloud backup and device transfer exclude secure storage',
    () {
      final rules = _readXml(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      );

      expect(rules.rootElement.name.local, 'data-extraction-rules');
      _expectSecureStorageExcluded(
        rules.rootElement.getElement('cloud-backup'),
      );
      _expectSecureStorageExcluded(
        rules.rootElement.getElement('device-transfer'),
      );
    },
  );
}

XmlDocument _readXml(String path) =>
    XmlDocument.parse(File(path).readAsStringSync());

void _expectSecureStorageExcluded(XmlElement? parent) {
  expect(parent, isNotNull);
  expect(
    parent!
        .findElements('exclude')
        .where(
          (element) =>
              element.getAttribute('domain') == _secureStorageDomain &&
              element.getAttribute('path') == _secureStoragePath,
        ),
    hasLength(1),
  );
}
