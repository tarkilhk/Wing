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
            Text('Read only', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
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
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry.$2['body'] ?? ''}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (entry.$2['source'] case final String source)
                      Text(
                        'Source: $source',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
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
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: refresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh memories'),
                ),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Why read only?'),
                      content: const Text(
                        'You can read and copy these memories. This server does not support safely editing or deleting them from Wing. Retention and character budgets are available in Memory settings.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('Why read only?'),
                ),
              ],
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
