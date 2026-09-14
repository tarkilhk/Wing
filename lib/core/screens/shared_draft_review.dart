import 'package:flutter/material.dart';
import '../theme/hermes_theme.dart';

import '../services/android_share_intent_service.dart';
import '../services/attachment_draft_service.dart';
import '../services/composer_draft_store.dart';
import '../services/profile_workspace_controller.dart';

Future<bool> reviewSharedDraft(
  BuildContext context,
  ProfileWorkspaceController controller,
  AndroidSharePayload payload, {
  ProfileChat? initialChat,
  ({ProfileSessionKey key, ComposerDraftSnapshot draft})? recoverableDraft,
  String? destinationNotice,
}) async =>
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _SharedDraftReview(
          controller: controller,
          payload: payload,
          initialChat: initialChat,
          recoverableDraft: recoverableDraft,
          destinationNotice: destinationNotice,
        ),
      ),
    ) ??
    false;

class _SharedDraftReview extends StatefulWidget {
  final ProfileWorkspaceController controller;
  final AndroidSharePayload payload;
  final ProfileChat? initialChat;
  final ({ProfileSessionKey key, ComposerDraftSnapshot draft})?
  recoverableDraft;
  final String? destinationNotice;

  const _SharedDraftReview({
    required this.controller,
    required this.payload,
    this.initialChat,
    this.recoverableDraft,
    this.destinationNotice,
  });

  @override
  State<_SharedDraftReview> createState() => _SharedDraftReviewState();
}

class _SharedDraftReviewState extends State<_SharedDraftReview> {
  static const _newChat = '__new_chat__';
  static const _recoverDraft = '__recover_draft__';

  ProfileWorkspaceController get controller => widget.controller;
  late String _profileName;
  String _destination = _newChat;
  ProfileChat? _createdTarget;
  ProfileChat? _recoveryTarget;
  bool _recoveryApplied = false;
  bool _initialChatValid = false;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _profileName = controller.current!.scope.profileName;
    final initial = widget.initialChat;
    _initialChatValid =
        initial != null &&
        controller.owns(initial.key) &&
        controller.current?.scope == initial.key.workspace &&
        identical(controller.current?.chats[initial.key.sessionId], initial);
    if (_initialChatValid && initial != null) {
      _destination = initial.key.sessionId;
    } else if (widget.recoverableDraft?.key.workspace ==
        controller.current?.scope) {
      _destination = _recoverDraft;
    }
    controller.addListener(_controllerChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_controllerChanged);
    super.dispose();
  }

  void _controllerChanged() {
    if (mounted) setState(() {});
  }

  String _message(Object error) => error is StateError
      ? error.message.toString()
      : error is AttachmentDraftException
      ? error.message
      : 'The shared content could not be added. Try again.';

  Future<void> _selectProfile(String? name) async {
    if (name == null || name == _profileName || _working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await controller.navigateProfile(name);
      if (controller.current?.scope.profileName != name) {
        throw StateError('That profile could not be opened.');
      }
      if (!mounted) return;
      setState(() {
        _profileName = name;
        _destination = _newChat;
        _initialChatValid = false;
        _createdTarget = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _loadMore() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      if (controller.current?.selectedProject != null) {
        await controller.selectProject(null);
      }
      await controller.loadMoreSessions();
      final pageError = controller.current?.sessionsPageError;
      if (mounted && pageError != null) {
        setState(() => _error = pageError);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _commit() async {
    if (_working) return;
    final resource = controller.current;
    if (resource == null || resource.scope.profileName != _profileName) {
      setState(() => _error = 'The selected profile is no longer open.');
      return;
    }
    final owner = resource.scope;
    final destination = _destination;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final ProfileChat chat;
      if (destination == _recoverDraft) {
        final recovery = widget.recoverableDraft;
        if (recovery == null || recovery.key.workspace != owner) {
          throw StateError(
            'Return to the original profile to recover this draft.',
          );
        }
        if (resource.selectedProject != null) {
          await controller.selectProject(null);
        }
        chat = _recoveryTarget ?? await controller.createChat(owner: owner);
        _recoveryTarget = chat;
        if (!_recoveryApplied) {
          await controller.recoverDraft(recovery.key, chat);
          _recoveryApplied = true;
        }
      } else if (destination == _newChat) {
        if (_createdTarget == null && resource.selectedProject != null) {
          await controller.selectProject(null);
          if (controller.current != resource) {
            throw StateError('The selected profile is no longer open.');
          }
        }
        chat = _createdTarget ?? await controller.createChat(owner: owner);
        _createdTarget = chat;
      } else {
        await controller.openSession(ProfileSessionKey(owner, destination));
        final opened = resource.chats[destination];
        if (controller.current != resource ||
            resource.selectedSession != destination ||
            opened == null) {
          throw StateError('The selected chat could not be opened.');
        }
        chat = opened;
      }
      await controller.stageSharedDraft(chat, widget.payload);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _working = false;
          _error = _message(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final resource = controller.current;
    final profiles = controller.discovery?.profiles ?? const [];
    final sessions = resource?.scope.profileName == _profileName
        ? resource!.sessions
        : const <Map<String, dynamic>>[];
    final initial = _initialChatValid ? widget.initialChat : null;
    final visibleSessions =
        initial != null &&
            initial.key.workspace.profileName == _profileName &&
            !sessions.any((session) => session['id'] == initial.key.sessionId)
        ? [
            ...sessions,
            {'id': initial.key.sessionId, 'title': initial.title},
          ]
        : sessions;
    return PopScope(
      canPop: !_working,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Add shared content',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_working) const LinearProgressIndicator(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Review',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.payload.text case final String text
                                when text.isNotEmpty) ...[
                              SelectableText(text),
                              if (widget.payload.files.isNotEmpty)
                                const Divider(height: 24),
                            ],
                            for (final file in widget.payload.files)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  file.isImage
                                      ? Icons.image_outlined
                                      : Icons.insert_drive_file_outlined,
                                ),
                                title: Text(
                                  file.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(_size(file.byteLength)),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (widget.destinationNotice case final notice?) ...[
                      Text(notice),
                      const SizedBox(height: 12),
                    ],
                    if (widget.recoverableDraft case final recovery?) ...[
                      Text(
                        'Choose “New chat with recovered draft” in the ${recovery.key.workspace.profileName} profile to keep your saved text and attachments with this content. Review before sending. Queued messages will stay paused.',
                      ),
                      if (recovery.draft.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            recovery.draft.text,
                            maxLines: 6,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      Text(
                        '${recovery.draft.attachments.length} attachments · ${recovery.draft.queuedPrompts.length} queued messages',
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      'Destination',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('Connection: ${controller.connection.label}'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey('share-profile-$_profileName'),
                      initialValue: _profileName,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Profile',
                        border: OutlineInputBorder(
                          borderRadius: HermesRadius.control,
                        ),
                      ),
                      items: [
                        for (final profile in profiles)
                          DropdownMenuItem(
                            value: profile.name,
                            child: Text(
                              profile.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _working ? null : _selectProfile,
                    ),
                    const SizedBox(height: 12),
                    RadioGroup<String>(
                      groupValue: _destination,
                      onChanged: (value) {
                        if (!_working && value != null) {
                          setState(() {
                            if (value != _destination) _createdTarget = null;
                            _destination = value;
                          });
                        }
                      },
                      child: Column(
                        children: [
                          if (widget
                                  .recoverableDraft
                                  ?.key
                                  .workspace
                                  .profileName ==
                              _profileName)
                            RadioListTile<String>(
                              minTileHeight: 48,
                              minVerticalPadding: 8,
                              key: const Key('share-destination-recover'),
                              value: _recoverDraft,
                              enabled: !_working,
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'New chat with recovered draft',
                              ),
                            ),
                          RadioListTile<String>(
                            minTileHeight: 48,
                            minVerticalPadding: 8,
                            key: Key('share-destination-new'),
                            value: _newChat,
                            enabled: !_working,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              _createdTarget == null
                                  ? 'New chat'
                                  : 'New chat (ready)',
                            ),
                          ),
                          for (final session in visibleSessions)
                            RadioListTile<String>(
                              minTileHeight: 48,
                              minVerticalPadding: 8,
                              key: ValueKey(
                                'share-destination-${session['id']}',
                              ),
                              value: session['id'] as String,
                              enabled: !_working,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                (session['title'] as String?)
                                            ?.trim()
                                            .isNotEmpty ==
                                        true
                                    ? session['title'] as String
                                    : 'Untitled chat',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (resource?.nextSessionOffset != null) ...[
                      const SizedBox(height: 4),
                      TextButton.icon(
                        key: const Key('share-load-more'),
                        onPressed:
                            _working || resource?.sessionsLoadingMore == true
                            ? null
                            : _loadMore,
                        icon: const Icon(Icons.expand_more),
                        label: Text(
                          resource?.sessionsPageError == null
                              ? 'Load more chats'
                              : 'Retry more chats',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    _error!,
                    key: const Key('share-review-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('share-add-to-draft'),
                    onPressed: _working ? null : _commit,
                    child: Text(
                      _destination == _recoverDraft
                          ? 'Recover draft and add content'
                          : 'Add to draft',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KiB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
}
