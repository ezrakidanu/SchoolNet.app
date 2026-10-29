import 'package:flutter_test/flutter_test.dart';
import 'package:schoolnet/demo_api.dart';

void main() {
  group('SchoolNet DemoApi', () {
    test('creates a credential-free Administrator demo session', () {
      final session = DemoApi.post('/auth/login', {'role': 'ADMIN'});
      final user = Map<String, dynamic>.from(session['user'] as Map);

      expect(session['demo'], isTrue);
      expect(session['access_token'], 'schoolnet-demo-admin');
      expect(user['role'], 'ADMIN');
      expect(user['force_password_change'], isFalse);
      expect(user['institution_id'], DemoApi.institutionId);
    });

    test('provides sample school posts and role-specific inbox data', () {
      final posts = DemoApi.getList('/posts');
      final adminInbox = DemoApi.getList('/admin/inbox');
      final studentInbox = DemoApi.getList(
        '/messages/inbox',
        token: 'schoolnet-demo-student',
      );

      expect(posts, isNotEmpty);
      expect((posts.first as Map)['title'], contains('demo'));
      expect(adminInbox, isNotEmpty);
      expect(studentInbox, isNotEmpty);
      expect(
          DemoApi.getMap(
            '/performance/me',
            token: 'schoolnet-demo-student',
          )['calculated_stars'],
          9.2);
    });

    test('stores submitted demo messages in memory for the admin inbox', () {
      const message = 'Test message from the offline demo';
      final result = DemoApi.post(
        '/messages/difficulty',
        {'content': message},
        token: 'schoolnet-demo-student',
      );
      final adminInbox = DemoApi.getList('/admin/inbox');

      expect(result['demo'], isTrue);
      expect(adminInbox.any((item) => (item as Map)['content'] == message),
          isTrue);
    });

    test('unsupported mock routes fail closed', () {
      expect(
        () => DemoApi.getList('/unimplemented'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
