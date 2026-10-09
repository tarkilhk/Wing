import 'bots_repository.dart';
import 'bots_session.dart';
import 'connection_manager.dart';
import 'profile_workspace_registry.dart';

/// App composition: resolve secure saved authority through the existing registry,
/// sharing its OAuth owner and administration clients instead of creating logins.
BotsSession savedBotsSession(
  ConnectionManager manager,
  ProfileWorkspaceRegistry registry,
) => BotsSession((canUse) async {
  final connections = await manager.loadConnectionsWithSecrets();
  final sources = <BotsRepository>[];
  for (final connection in connections) {
    if (!canUse()) return const [];
    final controller = await registry.forSavedConnection(
      manager,
      connection.id,
      canUse: canUse,
    );
    if (!canUse()) return const [];
    sources.add(
      BotsRepository.forServer(
        controller.healthSession().server,
        isCurrent: () {
          try {
            manager.accessFor(controller.connection);
            return true;
          } catch (_) {
            return false;
          }
        },
      ),
    );
  }
  return sources;
});
