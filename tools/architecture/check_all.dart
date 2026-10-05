import 'cli.dart';
import 'model.dart';
import 'rules/business_rendering_types.dart' as rendering;
import 'rules/business_view_dependencies.dart' as business;
import 'rules/domain_dependencies.dart' as domain;
import 'rules/library_cycles.dart' as cycles;
import 'rules/role_inventory.dart' as inventory;
import 'rules/view_lowlevel_dependencies.dart' as views;
import 'rules/view_draft_write.dart' as draft;
import 'dead_code/retired_declarations.dart' as retired;
import 'rules/image_codec_confinement.dart' as codec;
import 'rules/image_codec_provenance.dart' as codec_provenance;
import 'rules/task_view_protocol.dart' as task_protocol;

final allRules = <String, Rule>{
  domain.id: domain.check,
  business.id: business.check,
  rendering.id: rendering.check,
  cycles.id: cycles.check,
  inventory.id: inventory.check,
  views.id: views.check,
  draft.id: (snapshot) => draft.check(snapshot, snapshot.root),
  retired.id: retired.check,
  codec.id: codec.check,
  codec_provenance.id: codec_provenance.check,
  task_protocol.id: (snapshot) => task_protocol.check(snapshot, snapshot.root),
};
Future<void> main(List<String> args) => run(args, allRules);
