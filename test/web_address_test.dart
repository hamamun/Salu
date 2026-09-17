import 'package:flutter_test/flutter_test.dart';
import 'package:salu/core/web/web_address.dart';

/// The address-bar classification rules web.md locks to Edge/Chrome
/// behavior: URLs navigate, everything else is a Google query.

void main() {
  group('urlFrom — what reads as an address', () {
    test('bare hosts navigate over https', () {
      expect(WebAddress.urlFrom('example.com'), 'https://example.com');
      expect(WebAddress.urlFrom(' example.com/path '),
          'https://example.com/path');
      expect(WebAddress.urlFrom('localhost:8080/x'),
          'https://localhost:8080/x');
      expect(WebAddress.urlFrom('192.168.0.10'), 'https://192.168.0.10');
    });

    test('explicit http/https/ftp pass through untouched', () {
      const String url = 'http://a.test/x?y=1#z';
      expect(WebAddress.urlFrom(url), url);
      expect(WebAddress.urlFrom('ftp://files.test/pub'),
          'ftp://files.test/pub');
    });

    test('queries, junk and dead schemes fall to search (null)', () {
      expect(WebAddress.urlFrom(''), isNull);
      expect(WebAddress.urlFrom('hello world'), isNull);
      expect(WebAddress.urlFrom('foo'), isNull); // no TLD → a word
      expect(WebAddress.urlFrom('example.c'), isNull); // 1-letter TLD
      expect(WebAddress.urlFrom('example.'), isNull);
      expect(WebAddress.urlFrom('mailto:someone@x.test'), isNull);
      expect(WebAddress.urlFrom('http://'), isNull); // scheme, no host
      expect(WebAddress.urlFrom('user:pass@example.com'), isNull);
      expect(WebAddress.urlFrom('a.test:99999'), isNull); // bogus port
    });

    test('over-long input is a query, not a navigation', () {
      expect(WebAddress.urlFrom('https://a.test/${'x' * 3000}'), isNull);
    });
  });

  group('navigateTarget + searchUrl — Google is the only engine', () {
    test('typed URL wins over the search guess', () {
      expect(WebAddress.navigateTarget('example.com'),
          'https://example.com');
    });
    test('anything else becomes a Google results page', () {
      expect(WebAddress.navigateTarget('salu media player'),
          'https://www.google.com/search?q=salu%20media%20player');
    });
    test('query text is component-encoded', () {
      expect(WebAddress.searchUrl('a&b=c'),
          contains('a%26b%3Dc'));
    });
  });

  group('labels + identity', () {
    test('hostOf strips www and lowercases', () {
      expect(WebAddress.hostOf('https://www.Example.com/x'), 'example.com');
    });
    test('labelFor shows the query for Google result pages', () {
      expect(
          WebAddress.labelFor('https://www.google.com/search?q=kitchen+ideas'),
          'kitchen ideas');
      expect(WebAddress.labelFor('https://a.test/b/c'), 'a.test');
    });
    test('canonical compares schemeless host+path+query, no fragment', () {
      expect(WebAddress.canonical('https://Example.com/path/'),
          'example.com/path');
      expect(WebAddress.canonical('http://example.com/path#frag'),
          'example.com/path');
      expect(WebAddress.canonical('https://example.com/p?x=1'),
          'example.com/p?x=1');
    });
    test('samePage rides the canonical rules', () {
      expect(WebAddress.samePage(
          'https://a.test/x/', 'http://a.test/x'), isTrue);
      expect(WebAddress.samePage('https://a.test/x', 'https://a.test/y'),
          isFalse);
    });
  });
}
