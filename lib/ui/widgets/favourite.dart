import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/romm/romm_models.dart';
import '../../providers/library_providers.dart';
import 'toast.dart';

/// [toggleFavourite], telling the user when RomM refused it.
Future<void> favourite(BuildContext context, WidgetRef ref, Game g) async {
  final error = await toggleFavourite(ref, g);
  if (error != null && context.mounted) showToast(context, error);
}
