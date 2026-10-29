const bool schoolnetDemoMode = bool.fromEnvironment(
  'SCHOOLNET_DEMO_MODE',
  defaultValue: false,
);

/// In-memory responses used only when the app is built with
/// --dart-define=SCHOOLNET_DEMO_MODE=true. This service never contacts a server.
class DemoApi {
  static const String institutionId = 'demo-institution';
  static int _nextMessageId = 10;

  static const List<Map<String, dynamic>> _posts = [
    {
      'id': 'demo-post-1',
      'scope': 'GLOBAL',
      'title': 'Welcome to the SchoolNet demo',
      'content':
          'This sample announcement is stored in the demo build. It is not a live school notice.',
      'created_at': '2026-10-29T08:00:00Z',
    },
    {
      'id': 'demo-post-2',
      'scope': 'GRADE',
      'title': 'Mid-term study support',
      'content':
          'Use this sample post to preview the announcement feed and search screen.',
      'created_at': '2026-10-28T09:30:00Z',
    },
    {
      'id': 'demo-post-3',
      'scope': 'SECTION',
      'title': 'Science club meeting',
      'content':
          'A sample section announcement demonstrates how scoped posts appear in the app.',
      'created_at': '2026-10-27T12:15:00Z',
    },
  ];

  static final List<Map<String, dynamic>> _adminInbox = [
    {
      'id': 'demo-message-1',
      'category': 'Student support',
      'content': 'Demo: Please share the upcoming study-support schedule.',
      'created_at': '2026-10-29T07:40:00Z',
    },
    {
      'id': 'demo-message-2',
      'category': 'Community inquiry',
      'content': 'Demo: Could you share the next school community event date?',
      'created_at': '2026-10-28T14:20:00Z',
    },
  ];

  static final Map<String, List<Map<String, dynamic>>> _personalInboxes = {
    'ADMIN': [
      {
        'id': 'demo-private-1',
        'title': 'Demo administrator note',
        'content': 'This private message is sample data for the demo build.',
      },
    ],
    'TEACHER': [
      {
        'id': 'demo-private-2',
        'title': 'Demo class update',
        'content': 'Your sample class resources are ready to review.',
      },
    ],
    'STUDENT': [
      {
        'id': 'demo-private-3',
        'title': 'Demo support reply',
        'content': 'A sample reply shows how private support messages appear.',
      },
    ],
    'COUNSELOR': [
      {
        'id': 'demo-private-4',
        'title': 'Demo support request',
        'content': 'This is a sample student-support conversation.',
      },
    ],
    'COMMUNITY': [
      {
        'id': 'demo-private-5',
        'title': 'Demo school reply',
        'content': 'This is a sample response to a community inquiry.',
      },
    ],
  };

  static Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      Map<String, dynamic>.from(value);

  static String _roleFromToken(String? token) {
    if (token == null || !token.startsWith('schoolnet-demo-')) {
      return 'ADMIN';
    }
    return token.substring('schoolnet-demo-'.length).toUpperCase();
  }

  static Map<String, dynamic> userForRole(String role, {String? fullName}) {
    const names = {
      'ADMIN': 'Demo Administrator',
      'TEACHER': 'Demo Teacher',
      'STUDENT': 'Demo Student',
      'COUNSELOR': 'Demo Counselor',
      'COMMUNITY': 'Demo Community Member',
    };
    return {
      'id': 'demo-${role.toLowerCase()}',
      'institution_id': institutionId,
      'institution_slug': 'demo-school',
      'full_name': fullName ?? names[role] ?? 'Demo User',
      'email': 'demo-${role.toLowerCase()}@schoolnet.test',
      'role': role,
      'force_password_change': false,
      if (role == 'TEACHER') 'teacher_stars': 4.8,
    };
  }

  static Map<String, dynamic> login(String role) => {
        'access_token': 'schoolnet-demo-${role.toLowerCase()}',
        'user': userForRole(role),
        'demo': true,
      };

  static Map<String, dynamic> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) {
    if (path == '/auth/login') {
      final role = (body['role'] ?? 'ADMIN').toString().toUpperCase();
      return login(role);
    }
    if (path == '/auth/register-community') {
      return {
        'access_token': 'schoolnet-demo-community',
        'user': userForRole(
          'COMMUNITY',
          fullName: body['full_name']?.toString(),
        ),
        'demo': true,
      };
    }
    if (path == '/auth/change-password') {
      return {'ok': true, 'demo': true};
    }
    if (path.startsWith('/auth/recovery-request')) {
      return {
        'ok': true,
        'demo': true,
        'message': 'Demo recovery only; no email or school request was sent.',
      };
    }
    if (path.startsWith('/messages/')) {
      final role = _roleFromToken(token);
      final content = body['content']?.toString().trim() ?? '';
      final category = switch (path) {
        '/messages/difficulty' => 'Student support',
        '/messages/guidance' => 'Guidance & Counseling',
        '/messages/community-inquiry' => 'Community inquiry',
        _ => 'Demo message',
      };
      if (content.isNotEmpty) {
        final message = {
          'id': 'demo-message-${_nextMessageId++}',
          'category': category,
          'title': 'Demo message',
          'content': content,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        };
        _adminInbox.insert(0, _copy(message));
        (_personalInboxes[role] ??= []).insert(0, _copy(message));
      }
      return {
        'ok': true,
        'demo': true,
        'message': 'Saved in demo memory only.'
      };
    }
    throw UnsupportedError('No demo response is defined for $path.');
  }

  static List<dynamic> getList(String path, {String? token}) {
    if (path == '/posts') {
      return _posts.map(_copy).toList();
    }
    if (path == '/admin/inbox') {
      return _adminInbox.map(_copy).toList();
    }
    if (path == '/messages/inbox') {
      final role = _roleFromToken(token);
      return (_personalInboxes[role] ?? const <Map<String, dynamic>>[])
          .map(_copy)
          .toList();
    }
    throw UnsupportedError('No demo list is defined for $path.');
  }

  static Map<String, dynamic> getMap(String path, {String? token}) {
    if (path == '/performance/me') {
      final role = _roleFromToken(token);
      return {
        'role': role,
        'calculated_stars': 9.2,
        'average_percent': 92.0,
        'demo': true,
      };
    }
    throw UnsupportedError('No demo response is defined for $path.');
  }
}
