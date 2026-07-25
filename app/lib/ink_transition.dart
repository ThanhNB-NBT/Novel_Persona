import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Chuyển màn dùng chung: fade ngắn, không che nội dung và không vẽ lại cả màn.
CustomTransitionPage<T> inkPage<T>({required Widget child, LocalKey? key}) =>
    CustomTransitionPage<T>(
      key: key,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut), child: child),
      child: child,
    );
