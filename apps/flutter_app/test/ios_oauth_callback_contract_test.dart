import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

const _nativeOAuthCallbackScheme = 'cloud.lalanext.lala';

void main() {
  test('iOS plist registers the native OAuth callback scheme exactly once', () {
    final plist = XmlDocument.parse(
      File('ios/Runner/Info.plist').readAsStringSync(),
    );
    final rootDictionary = plist.rootElement.getElement('dict');

    expect(rootDictionary, isNotNull);
    final urlTypes = _plistValue(rootDictionary!, 'CFBundleURLTypes');
    expect(urlTypes.name.local, 'array');

    final schemes = urlTypes
        .findElements('dict')
        .map((urlType) => _plistValue(urlType, 'CFBundleURLSchemes'))
        .expand((schemeArray) => schemeArray.findElements('string'))
        .map((scheme) => scheme.innerText)
        .where((scheme) => scheme == _nativeOAuthCallbackScheme);

    expect(schemes, hasLength(1));
  });
}

XmlElement _plistValue(XmlElement dictionary, String key) {
  final entries = dictionary.childElements.toList();
  for (var index = 0; index < entries.length - 1; index += 2) {
    final candidateKey = entries[index];
    if (candidateKey.name.local == 'key' && candidateKey.innerText == key) {
      return entries[index + 1];
    }
  }
  throw StateError('Missing plist key: $key');
}
