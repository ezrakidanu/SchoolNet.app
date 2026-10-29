import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'announcement_search.dart';

const navy = Color(0xFF17345B);
const teal = Color(0xFF11B6A5);
const mint = Color(0xFFE4F8F5);
const apiBase = String.fromEnvironment('API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000');
const secureStore = FlutterSecureStorage();
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('schoolnet_cache');
  final isDark =
      Hive.box('schoolnet_cache').get('darkMode', defaultValue: false) as bool;
  runApp(ProviderScope(overrides: [
    themeModeProvider
        .overrideWith((ref) => isDark ? ThemeMode.dark : ThemeMode.light)
  ], child: const SchoolNetApp()));
}

class RoleInfo {
  final String label;
  final String api;
  final String subtitle;
  final IconData icon;
  const RoleInfo(this.label, this.api, this.subtitle, this.icon);
}

const roles = <RoleInfo>[
  RoleInfo('Student', 'STUDENT', 'Learning, grades and support',
      Icons.school_rounded),
  RoleInfo('Teacher', 'TEACHER', 'Classes, resources and marklists',
      Icons.co_present_rounded),
  RoleInfo('Administrator', 'ADMIN', 'School operations and people',
      Icons.admin_panel_settings_rounded),
  RoleInfo('Guidance & Counseling', 'COUNSELOR', 'Private student support',
      Icons.support_agent_rounded),
  RoleInfo('People', 'COMMUNITY', 'Connect with the school',
      Icons.people_alt_rounded),
];

class SchoolNetApp extends ConsumerWidget {
  const SchoolNetApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
        title: 'SchoolNet',
        debugShowCheckedModeBanner: false,
        themeMode: ref.watch(themeModeProvider),
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
              seedColor: teal,
              primary: navy,
              secondary: teal,
              surface: const Color(0xFFF7FAFC)),
          scaffoldBackgroundColor: const Color(0xFFF7FAFC),
          fontFamily: 'Roboto',
          appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFF7FAFC),
              foregroundColor: navy,
              centerTitle: false,
              elevation: 0),
          cardTheme: CardThemeData(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Color(0xFFE7EEF2)))),
          inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFFF2F6F8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 15)),
        ),
        darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
                seedColor: teal, brightness: Brightness.dark),
            fontFamily: 'Roboto'),
        home: const SignInPage(),
      );
}

class Api {
  static Uri uri(String path) => Uri.parse('$apiBase$path');
  static Future<Map<String, dynamic>> post(
      String path, Map<String, dynamic> body,
      {String? token}) async {
    final response = await http
        .post(uri(path),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token'
            },
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    final data = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          data['detail'] ?? 'Request failed (${response.statusCode})');
    }
    return data;
  }

  static Future<List<dynamic>> getList(String path, String token) async {
    final response = await http.get(uri(path), headers: {
      'Authorization': 'Bearer $token'
    }).timeout(const Duration(seconds: 15));
    final data = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data is Map ? data['detail'] : 'Request failed');
    }
    return data as List<dynamic>;
  }
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  RoleInfo selected = roles.first;
  bool communitySignup = false;
  bool busy = false;
  final school = TextEditingController();
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  String? error;

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = communitySignup
          ? await Api.post('/auth/register-community', {
              'institution_slug': school.text.trim(),
              'full_name': name.text.trim(),
              'email': email.text.trim(),
              'password': password.text
            })
          : await Api.post('/auth/login', {
              'institution_slug': school.text.trim(),
              'email': email.text.trim(),
              'password': password.text,
              'role': selected.api
            });
      final token = result['access_token'] as String;
      final user = Map<String, dynamic>.from(result['user'] as Map);
      await secureStore.write(key: 'token', value: token);
      if (!mounted) return;
      if (user['force_password_change'] == true) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => PasswordResetPage(token: token)));
      } else {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => PortalPage(token: token, user: user)));
      }
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    school.dispose();
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
            child: Center(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                  child: ClipRRect(
                                      borderRadius: BorderRadius.circular(22),
                                      child: Image.asset(
                                          'assets/schoolnet_logo.jpg',
                                          width: 132,
                                          height: 132,
                                          fit: BoxFit.cover))),
                              const SizedBox(height: 22),
                              const Text('A closer school community.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      color: navy,
                                      letterSpacing: -.4)),
                              const SizedBox(height: 8),
                              const Text(
                                  'Learning, support and school life — connected.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Color(0xFF65758A), fontSize: 14)),
                              const SizedBox(height: 26),
                              if (!communitySignup) ...[
                                const Text('Choose your portal',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: navy)),
                                const SizedBox(height: 10),
                                Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: roles
                                        .map((role) => ChoiceChip(
                                            label: Text(role.label),
                                            avatar: Icon(role.icon, size: 18),
                                            selected: selected.api == role.api,
                                            onSelected: (_) => setState(() {
                                                  selected = role;
                                                  error = null;
                                                })))
                                        .toList()),
                              ] else ...[
                                TextButton.icon(
                                    onPressed: () => setState(() {
                                          communitySignup = false;
                                          error = null;
                                        }),
                                    icon: const Icon(Icons.arrow_back),
                                    label: const Text('Back to sign in')),
                                const Text('Create a People account',
                                    style: TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w700,
                                        color: navy)),
                              ],
                              const SizedBox(height: 18),
                              _field(school, 'School code',
                                  Icons.apartment_rounded),
                              if (communitySignup) ...[
                                const SizedBox(height: 11),
                                _field(name, 'Full name',
                                    Icons.person_outline_rounded)
                              ],
                              const SizedBox(height: 11),
                              _field(email, 'Email address',
                                  Icons.alternate_email_rounded,
                                  keyboard: TextInputType.emailAddress),
                              const SizedBox(height: 11),
                              _field(
                                  password,
                                  communitySignup
                                      ? 'Create password (10+ characters)'
                                      : 'Password / temporary PIN',
                                  Icons.lock_outline_rounded,
                                  obscure: true),
                              if (error != null) ...[
                                const SizedBox(height: 12),
                                Text(error!,
                                    style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.w600))
                              ],
                              const SizedBox(height: 18),
                              FilledButton(
                                  onPressed: busy ? null : submit,
                                  style: FilledButton.styleFrom(
                                      backgroundColor: navy,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14))),
                                  child: busy
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white))
                                      : Text(communitySignup
                                          ? 'Create account'
                                          : 'Continue as ${selected.label}')),
                              if (!communitySignup) ...[
                                const SizedBox(height: 9),
                                TextButton(
                                    onPressed: () => setState(() {
                                          communitySignup = true;
                                          selected = roles.last;
                                          error = null;
                                        }),
                                    child: const Text(
                                        'New to the school community? Create a People account')),
                                TextButton(
                                    onPressed: () async {
                                      if (school.text.trim().isEmpty ||
                                          email.text.trim().isEmpty) {
                                        setState(() => error =
                                            'Enter your school code and email first.');
                                        return;
                                      }
                                      try {
                                        await Api.post(
                                            '/auth/recovery-request?institution_slug=${Uri.encodeQueryComponent(school.text.trim())}&email=${Uri.encodeQueryComponent(email.text.trim())}',
                                            {});
                                        if (mounted) {
                                          setState(() => error =
                                              'If the school exists, your request was routed to its administrator.');
                                        }
                                      } catch (_) {
                                        if (mounted) {
                                          setState(() => error =
                                              'Could not send the request. Check your connection.');
                                        }
                                      }
                                    },
                                    child:
                                        const Text('Request account recovery')),
                              ],
                              const SizedBox(height: 12),
                              const Text(
                                  'Institutional accounts are created by the school administrator. People accounts are self-registered.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Color(0xFF7A899A), fontSize: 12)),
                            ]))))),
      );

  Widget _field(TextEditingController controller, String label, IconData icon,
          {bool obscure = false, TextInputType? keyboard}) =>
      TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboard,
          decoration: InputDecoration(
              prefixIcon: Icon(icon, color: teal), labelText: label));
}

class PasswordResetPage extends StatefulWidget {
  final String token;
  const PasswordResetPage({super.key, required this.token});
  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  final pass = TextEditingController();
  bool busy = false;
  String? error;
  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await Api.post('/auth/change-password', {'new_password': pass.text},
          token: widget.token);
      await secureStore.delete(key: 'token');
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const SignInPage()),
            (_) => false);
      }
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Secure your account')),
      body: Padding(
          padding: const EdgeInsets.all(24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 28),
            const Icon(Icons.shield_moon_rounded, size: 54, color: teal),
            const SizedBox(height: 18),
            const Text('Create a private password',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 23, fontWeight: FontWeight.bold, color: navy)),
            const SizedBox(height: 10),
            const Text(
                'Your temporary school PIN has been used. Set a password with at least 10 characters to continue.',
                textAlign: TextAlign.center),
            const SizedBox(height: 22),
            TextField(
                controller: pass,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'New password',
                    prefixIcon: Icon(Icons.lock_outline))),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child:
                      Text(error!, style: const TextStyle(color: Colors.red))),
            const SizedBox(height: 18),
            FilledButton(
                onPressed: busy ? null : save,
                child: Text(busy ? 'Saving…' : 'Update password'))
          ])));
}

class PortalPage extends StatefulWidget {
  final String token;
  final Map<String, dynamic> user;
  const PortalPage({super.key, required this.token, required this.user});
  @override
  State<PortalPage> createState() => _PortalPageState();
}

class _PortalPageState extends State<PortalPage> {
  int tab = 0;
  bool online = true;
  List<dynamic> posts = [];
  String? error;
  String get role => widget.user['role'] as String? ?? 'STUDENT';
  String get name => widget.user['full_name'] as String? ?? 'SchoolNet user';
  String get feedCacheKey =>
      'posts_${widget.user['institution_id']}_${widget.user['id']}_$role';

  List<String> get navItems => switch (role) {
        'ADMIN' => ['Overview', 'Inbox', 'People', 'School'],
        'TEACHER' => ['Overview', 'Classes', 'Resources', 'School'],
        'STUDENT' => ['Overview', 'My section', 'Support', 'School'],
        'COUNSELOR' => ['Overview', 'Support inbox', 'School'],
        _ => ['Overview', 'Contact', 'School'],
      };

  @override
  void initState() {
    super.initState();
    refreshFeed();
  }

  Future<void> refreshFeed() async {
    try {
      final result = await Api.getList('/posts', widget.token);
      final box = Hive.box('schoolnet_cache');
      await box.put(feedCacheKey, jsonEncode(result));
      if (mounted) {
        setState(() {
          posts = result;
          online = true;
          error = null;
        });
      }
    } catch (_) {
      final cached = Hive.box('schoolnet_cache').get(feedCacheKey);
      if (mounted) {
        setState(() {
          online = false;
          posts = cached == null
              ? []
              : jsonDecode(cached as String) as List<dynamic>;
          error = cached == null
              ? 'Connect to the school network to load announcements.'
              : null;
        });
      }
    }
  }

  Future<void> messageDialog(String endpoint, String title) async {
    final controller = TextEditingController();
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(title),
                content: TextField(
                    controller: controller,
                    maxLines: 5,
                    decoration:
                        const InputDecoration(hintText: 'Write your message…')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () async {
                        try {
                          await Api.post(endpoint, {'content': controller.text},
                              token: widget.token);
                          if (context.mounted) Navigator.pop(context);
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(
                                    content: Text('Sent securely.')));
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                    content: Text(e
                                        .toString()
                                        .replaceFirst('Exception: ', ''))));
                          }
                        }
                      },
                      child: const Text('Send'))
                ]));
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = navItems[tab];
    return Scaffold(
      appBar: AppBar(
          titleSpacing: 18,
          title: Row(children: [
            ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.asset('assets/schoolnet_logo.jpg',
                    width: 34, height: 34, fit: BoxFit.cover)),
            const SizedBox(width: 10),
            const Text('SchoolNet',
                style: TextStyle(fontWeight: FontWeight.w800, color: navy))
          ]),
          actions: [
            IconButton(
                onPressed: () => showSearch<String>(
                    context: context,
                    delegate: AnnouncementSearchDelegate(posts)),
                icon: const Icon(Icons.search_rounded),
                tooltip: 'Search school updates'),
            IconButton(
                onPressed: () => _settings(context),
                icon: const Icon(Icons.settings_outlined))
          ]),
      body: RefreshIndicator(
          onRefresh: refreshFeed,
          child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
              children: [
                if (!online)
                  Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFFF3D5),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Row(children: [
                        Icon(Icons.cloud_off_rounded,
                            color: Color(0xFF9B6A00), size: 18),
                        SizedBox(width: 8),
                        Text('Offline — showing saved school information',
                            style: TextStyle(
                                color: Color(0xFF795600),
                                fontSize: 12,
                                fontWeight: FontWeight.w600))
                      ])),
                _greeting(),
                const SizedBox(height: 20),
                if (current == 'Overview') ..._overview(),
                if (current == 'Inbox' || current == 'Support inbox')
                  ..._inbox(),
                if (current == 'People' ||
                    current == 'Classes' ||
                    current == 'My section' ||
                    current == 'Support' ||
                    current == 'Contact')
                  ..._roleFeatures(current),
                if (current == 'Resources') ..._resources(),
                if (current == 'School') ..._schoolInfo(),
              ])),
      bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: [
            for (final item in navItems)
              NavigationDestination(icon: Icon(_icon(item)), label: item)
          ]),
    );
  }

  Widget _greeting() => Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [navy, Color(0xFF24628A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(22)),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Good day, ${name.split(' ').first}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 5),
          Text(_headline(),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 21)),
          if (role == 'TEACHER') ...[
            const SizedBox(height: 5),
            Text(
                'Administrator rating · ${widget.user['teacher_stars'] ?? 'Not rated'} / 5 stars',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
          const SizedBox(height: 9),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(role.replaceAll('_', ' '),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)))
        ])),
        const SizedBox(width: 12),
        Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
                color: teal.withValues(alpha: .25), shape: BoxShape.circle),
            child:
                const Icon(Icons.school_rounded, color: Colors.white, size: 28))
      ]));

  String _headline() => switch (role) {
        'ADMIN' => 'Your school, in sync.',
        'TEACHER' => 'Your classes at a glance.',
        'STUDENT' => 'Your learning, connected.',
        'COUNSELOR' => 'Support that stays private.',
        _ => 'Stay close to school life.'
      };

  List<Widget> _overview() => [
        Text('Your workspace', style: _sectionStyle),
        const SizedBox(height: 10),
        ..._quickCards(),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: Text('School announcements', style: _sectionStyle)),
          TextButton(onPressed: refreshFeed, child: const Text('Refresh'))
        ]),
        if (error != null)
          _empty(error!)
        else if (posts.isEmpty)
          _empty('New school updates will appear here.')
        else
          ...posts.map((p) => _postCard(Map<String, dynamic>.from(p as Map))),
      ];

  List<Widget> _quickCards() {
    if (role == 'ADMIN') {
      return [
        _quick(
            'Roster management',
            'Create school accounts and import a roster',
            Icons.group_add_rounded,
            onTap: () => _showInfo('Roster management',
                'Create users and upload CSV from the protected administrator API. Temporary credentials must be shared securely.')),
        _quick('Central inbox', 'Student, teacher, G&C and People requests',
            Icons.inbox_rounded,
            onTap: () => setState(() => tab = navItems.indexOf('Inbox'))),
        _quick('Term & archive', 'Plan academic-year changes',
            Icons.event_repeat_rounded,
            onTap: () => _showInfo('Seasonal administration',
                'Active-term changes, archival snapshots and cohort promotion are planned for the next release.'))
      ];
    }
    if (role == 'TEACHER') {
      return [
        _quick('Marklists', 'Enter scores for your assigned classes',
            Icons.table_chart_rounded,
            onTap: () => _showInfo('Marklists',
                'The backend validates points and computes student stars from published marks. The full mark-entry grid is part of the next UI increment.')),
        _quick('Upload resources', 'Share notes by grade and subject',
            Icons.upload_file_rounded,
            onTap: () => _showInfo('Resources',
                'Resource storage and upload endpoints are planned for the next release.')),
        _quick(
            'My students', 'View your assigned classes', Icons.groups_rounded,
            onTap: () => setState(() => tab = navItems.indexOf('Classes')))
      ];
    }
    if (role == 'STUDENT') {
      return [
        _quick('My academic badge', 'Calculated from published scores',
            Icons.stars_rounded,
            onTap: _loadPerformance),
        _quick(
            'Report a difficulty',
            'Send a private note to your Head Teacher',
            Icons.mark_unread_chat_alt_rounded,
            onTap: () => messageDialog(
                '/messages/difficulty', 'Message your Class Head Teacher')),
        _quick(
            'Guidance & Counseling',
            'Private support, when enabled by school',
            Icons.support_agent_rounded,
            onTap: () => messageDialog(
                '/messages/guidance', 'Contact Guidance & Counseling'))
      ];
    }
    if (role == 'COUNSELOR') {
      return [
        _quick('Private student support',
            'Handle student support conversations', Icons.forum_rounded,
            onTap: () =>
                setState(() => tab = navItems.indexOf('Support inbox'))),
        _quick(
            'School updates', 'Read-only global feed', Icons.campaign_rounded,
            onTap: () => setState(() => tab = navItems.indexOf('School')))
      ];
    }
    return [
      _quick('Contact the school', 'Send an inquiry to the administrator',
          Icons.mark_email_unread_rounded,
          onTap: () =>
              messageDialog('/messages/community-inquiry', 'Send an inquiry')),
      _quick('About the school', 'View public school information',
          Icons.info_outline_rounded,
          onTap: () => setState(() => tab = navItems.indexOf('School')))
    ];
  }

  Widget _quick(String title, String subtitle, IconData icon,
          {VoidCallback? onTap}) =>
      Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Container(
                        width: 43,
                        height: 43,
                        decoration: BoxDecoration(
                            color: mint,
                            borderRadius: BorderRadius.circular(14)),
                        child: Icon(icon, color: teal)),
                    const SizedBox(width: 13),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, color: navy)),
                          const SizedBox(height: 4),
                          Text(subtitle,
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF738196)))
                        ])),
                    const Icon(Icons.chevron_right_rounded,
                        color: Color(0xFF97A5B4))
                  ]))));

  Widget _postCard(Map<String, dynamic> post) => Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
          padding: const EdgeInsets.all(15),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.campaign_rounded, color: teal, size: 18),
              const SizedBox(width: 7),
              Text((post['scope'] ?? 'GLOBAL').toString(),
                  style: const TextStyle(
                      color: teal, fontSize: 11, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(_date(post['created_at']),
                  style:
                      const TextStyle(color: Color(0xFF8996A4), fontSize: 11))
            ]),
            if (post['title'] != null)
              Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Text(post['title'],
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: navy))),
            const SizedBox(height: 6),
            Text(post['content'] ?? '',
                style: const TextStyle(height: 1.4, color: Color(0xFF556579)))
          ])));

  String _date(dynamic value) {
    if (value == null) return '';
    try {
      return DateTime.parse(value.toString())
          .toLocal()
          .toString()
          .split('.')
          .first
          .substring(0, 16);
    } catch (_) {
      return '';
    }
  }

  List<Widget> _roleFeatures(String current) {
    if (role == 'STUDENT' && current == 'Support') {
      return [
        _quick(
            'Head Teacher difficulty form',
            'Your note is sent privately to the assigned Head Teacher.',
            Icons.edit_note_rounded,
            onTap: () =>
                messageDialog('/messages/difficulty', 'Report a difficulty')),
        _quick(
            'Guidance & Counseling',
            'Available only when your school enables this module.',
            Icons.support_agent_rounded,
            onTap: () => messageDialog(
                '/messages/guidance', 'Contact Guidance & Counseling'))
      ];
    }
    if (role == 'COMMUNITY' && current == 'Contact') {
      return [
        _quick(
            'Ask the school',
            'Only the school administrator receives your inquiry.',
            Icons.mail_outline_rounded,
            onTap: () =>
                messageDialog('/messages/community-inquiry', 'Send an inquiry'))
      ];
    }
    return [
      _empty(switch (role) {
        'STUDENT' =>
          'Your section is limited to your assigned grade and class.',
        'TEACHER' =>
          'Assigned classes and student edit access will appear here.',
        'ADMIN' => 'Manage teachers, students and school contacts.',
        'COUNSELOR' =>
          'Private student support threads belong to this profile.',
        _ => 'Public school information and announcements are available here.'
      })
    ];
  }

  List<Widget> _resources() => [
        _quick(
            'Study notes & assignments',
            'Resources are organized by grade and subject.',
            Icons.menu_book_rounded),
        _empty('No shared resources are available yet.')
      ];

  List<Widget> _schoolInfo() => [
        const Text('SchoolNet connects every part of school life.',
            style: TextStyle(
                fontSize: 20,
                height: 1.3,
                fontWeight: FontWeight.w800,
                color: navy)),
        const SizedBox(height: 12),
        const Text(
            'Official announcements, school information and community contact — with student privacy built in.',
            style: TextStyle(color: Color(0xFF64748B), height: 1.5)),
        const SizedBox(height: 18),
        _quick(
            'About the school',
            'History, contact information and community links',
            Icons.apartment_rounded),
        _quick('Your preferences', 'Notifications, theme and account security',
            Icons.tune_rounded,
            onTap: () => _settings(context))
      ];

  List<Widget> _inbox() => [
        const Text('Private inbox',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: navy)),
        const SizedBox(height: 8),
        _empty(role == 'ADMIN'
            ? 'Your routed messages are stored in the protected admin inbox API.'
            : 'Private support and school messages will appear here.'),
        _quick(
            role == 'ADMIN' ? 'Open admin inbox' : 'Load private messages',
            role == 'ADMIN'
                ? 'Messages are categorized by source role on the API.'
                : 'Only messages addressed to your account are shown.',
            Icons.inbox_rounded,
            onTap: role == 'ADMIN' ? _loadInbox : _loadPersonalInbox)
      ];

  Widget _empty(String text) => Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFFE7EEF2))),
      child: Text(text,
          style: const TextStyle(color: Color(0xFF738196), height: 1.4)));
  TextStyle get _sectionStyle =>
      const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: navy);
  IconData _icon(String label) => switch (label) {
        'Overview' => Icons.grid_view_rounded,
        'Inbox' || 'Support inbox' => Icons.inbox_rounded,
        'People' || 'Classes' || 'My section' => Icons.groups_rounded,
        'Resources' => Icons.menu_book_rounded,
        'Support' || 'Contact' => Icons.chat_bubble_outline_rounded,
        _ => Icons.apartment_rounded
      };

  Future<void> _loadPerformance() async {
    try {
      final response = await http.get(Api.uri('/performance/me'),
          headers: {'Authorization': 'Bearer ${widget.token}'});
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (mounted) {
        showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
                    title: const Text('Your academic badge'),
                    content: Text(data['calculated_stars'] == null
                        ? 'No published scores yet.'
                        : '${data['calculated_stars']} / 10 stars\n${data['average_percent']}% aggregate average'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'))
                    ]));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _loadInbox() async {
    try {
      final response = await http.get(Api.uri('/admin/inbox'),
          headers: {'Authorization': 'Bearer ${widget.token}'});
      final data = jsonDecode(response.body) as List<dynamic>;
      if (mounted) {
        showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
                    title: Text('Admin inbox · ${data.length}'),
                    content: SizedBox(
                        width: 420,
                        child: data.isEmpty
                            ? const Text('No messages yet.')
                            : ListView(
                                shrinkWrap: true,
                                children: data
                                    .map((m) => ListTile(
                                        title: Text(m['category'] ?? 'Message'),
                                        subtitle: Text(m['content'] ?? ''),
                                        dense: true))
                                    .toList())),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'))
                    ]));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _loadPersonalInbox() async {
    try {
      final response = await http.get(Api.uri('/messages/inbox'),
          headers: {'Authorization': 'Bearer ${widget.token}'});
      final data = jsonDecode(response.body) as List<dynamic>;
      if (mounted) {
        showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
                    title: Text('Private messages · ${data.length}'),
                    content: SizedBox(
                        width: 420,
                        child: data.isEmpty
                            ? const Text('No private messages yet.')
                            : ListView(
                                shrinkWrap: true,
                                children: data
                                    .map((message) =>
                                        ListTile(
                                            title: Text(message['title'] ??
                                                message['category'] ??
                                                'Message'),
                                            subtitle:
                                                Text(message['content'] ?? ''),
                                            dense: true))
                                    .toList())),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'))
                    ]));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _showInfo(String title, String body) => showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
              title: Text(title),
              content: Text(body),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'))
              ]));
  Future<void> _settings(BuildContext context) async {
    showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => Consumer(
            builder: (context, ref, child) => SafeArea(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const ListTile(
                      title: Text('Settings',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, color: navy))),
                  const ListTile(
                      leading: Icon(Icons.notifications_outlined),
                      title: Text('Notification preferences'),
                      subtitle: Text(
                          'Device notification controls are planned for the next release.')),
                  SwitchListTile(
                      secondary: const Icon(Icons.palette_outlined),
                      title: const Text('Dark theme'),
                      subtitle:
                          const Text('Choose a comfortable display theme.'),
                      value: ref.watch(themeModeProvider) == ThemeMode.dark,
                      onChanged: (isDark) async {
                        ref.read(themeModeProvider.notifier).state =
                            isDark ? ThemeMode.dark : ThemeMode.light;
                        await Hive.box('schoolnet_cache')
                            .put('darkMode', isDark);
                      }),
                  ListTile(
                      leading: const Icon(Icons.logout_rounded),
                      title: const Text('Sign out'),
                      onTap: () async {
                        await secureStore.delete(key: 'token');
                        final box = Hive.box('schoolnet_cache');
                        for (final key in box.keys
                            .where((key) => key.toString().startsWith('posts_'))
                            .toList()) {
                          await box.delete(key);
                        }
                        if (context.mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                  builder: (_) => const SignInPage()),
                              (_) => false);
                        }
                      })
                ]))));
  }
}
