import 'package:flutter/material.dart';
import '../../services/administration_repository.dart';
import 'admin_settings_page.dart';
import 'admin_widgets.dart';

class AdminMemoryPage extends StatefulWidget {
  final ProfileAdministration profile;
  const AdminMemoryPage({super.key, required this.profile});
  @override
  State<AdminMemoryPage> createState() => _AdminMemoryPageState();
}

class _AdminMemoryPageState extends State<AdminMemoryPage> {
  late final _profile = widget.profile;
  String _query = '';
  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Memory',
    scope: _profile.label,
    actions: [
      IconButton(
        tooltip: 'Memory settings',
        icon: const Icon(Icons.tune),
        onPressed: () => adminPush(
          context,
          AdminSettingsPage(
            profile: _profile,
            title: 'Memory settings',
            fields: memoryFields,
          ),
        ),
      ),
    ],
    child: AdminLoad(
      load: () => _profile.read('learning/graph'),
      builder: (context, data, refresh) {
        final rows = administrationRows(data['memory']);
        final indexed = rows.indexed.where(
          (r) => '${r.$2['title']} ${r.$2['body']}'.toLowerCase().contains(
            _query.toLowerCase(),
          ),
        );
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search memories',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Read only'),
              subtitle: const Text('Browse what this profile remembers'),
              children: const [
                Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Editing and deleting need server support for safe concurrent changes. Memory budgets are configured in characters; actual retained-file sizes are not reported for this profile.',
                  ),
                ),
              ],
            ),
            TextButton(onPressed: refresh, child: const Text('Refresh')),
            if (rows.isEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nothing remembered yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const AdminNotice('No retained memories in this profile.'),
                  TextButton(
                    onPressed: () => adminPush(
                      context,
                      AdminSettingsPage(
                        profile: _profile,
                        title: 'Memory settings',
                        fields: memoryFields,
                      ),
                    ),
                    child: const Text('Memory settings'),
                  ),
                ],
              ),
            if (rows.isNotEmpty && indexed.isEmpty)
              const AdminNotice('No matching memories.'),
            for (final entry in indexed)
              ListTile(
                title: Text('${entry.$2['title'] ?? 'Memory'}'),
                subtitle: Text(
                  '${entry.$2['body'] ?? ''}${entry.$2['source'] is String ? '\nSource: ${entry.$2['source']}' : ''}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => adminPush(
                  context,
                  AdminMemoryDetail(
                    profile: _profile,
                    id: 'memory:${entry.$2['source']}:${entry.$1}',
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class AdminMemoryDetail extends StatelessWidget {
  final ProfileAdministration profile;
  final String id;
  const AdminMemoryDetail({super.key, required this.profile, required this.id});
  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Retained memory',
    scope: profile.label,
    child: AdminLoad(
      load: () => profile.read('learning/node', {'id': id}),
      builder: (context, data, refresh) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SelectableText('${data['content'] ?? ''}'),
          const SizedBox(height: 24),
          const AdminNotice(
            'Read only. Editing and deleting are unavailable on the current server contract.',
          ),
          TextButton(onPressed: refresh, child: const Text('Refresh')),
        ],
      ),
    ),
  );
}
