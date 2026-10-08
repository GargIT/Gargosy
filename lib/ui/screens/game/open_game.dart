import 'package:flutter/material.dart';

import '../../../core/romm/romm_models.dart';
import 'game_screen.dart';

Future<void> openGame(BuildContext context, Game game) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(game: game)));
