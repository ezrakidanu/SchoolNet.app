import 'package:flutter/material.dart';

class AnnouncementSearchDelegate extends SearchDelegate<String> {
  AnnouncementSearchDelegate(this.posts);
  final List<dynamic> posts;

  @override
  String get searchFieldLabel => 'Search school announcements';

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
              tooltip: 'Clear search',
              onPressed: () => query = '',
              icon: const Icon(Icons.clear_rounded)),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        tooltip: 'Close search',
        onPressed: () => close(context, ''),
        icon: const Icon(Icons.arrow_back_rounded),
      );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final term = query.trim().toLowerCase();
    final filtered = posts.where((raw) {
      final item = Map<String, dynamic>.from(raw as Map);
      final haystack =
          '${item['title'] ?? ''} ${item['content'] ?? ''}'.toLowerCase();
      return term.isEmpty || haystack.contains(term);
    }).toList();
    if (filtered.isEmpty) {
      return const Center(child: Text('No matching school updates.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final post = Map<String, dynamic>.from(filtered[index] as Map);
        return Card(
          child: ListTile(
            leading: const CircleAvatar(
                backgroundColor: Color(0xFFE4F8F5),
                child: Icon(Icons.campaign_rounded, color: Color(0xFF11B6A5))),
            title: Text(post['title']?.toString() ?? 'School update'),
            subtitle: Text(post['content']?.toString() ?? '',
                maxLines: 3, overflow: TextOverflow.ellipsis),
            trailing: Text(post['scope']?.toString() ?? 'GLOBAL',
                style:
                    const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
            onTap: () => close(context, post['id']?.toString() ?? ''),
          ),
        );
      },
    );
  }
}
