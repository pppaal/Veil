import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/veil_app.dart';

void main() {
  runApp(const ProviderScope(child: VeilApp()));
}
