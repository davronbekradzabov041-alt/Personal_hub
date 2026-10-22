import 'package:flutter/material.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/modules/module_manager_scope.dart';
import '../../account_repository.dart';

class AccountsHomeSection extends StatefulWidget {
  const AccountsHomeSection({super.key, required this.moduleId});

  final String moduleId;

  @override
  State<AccountsHomeSection> createState() => _AccountsHomeSectionState();
}

class _AccountsHomeSectionState extends State<AccountsHomeSection> {
  bool _loading = true;
  int _count = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ModuleManagerScope.of(context).apiFor(widget.moduleId);
      final repo = AccountRepository(api.storage);
      final items = await repo.getAll();
      if (!mounted) return;
      setState(() {
        _count = items.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Ошибка загрузки аккаунтов: $_error'),
      );
    }
    if (_count == 0) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Нет аккаунтов'),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text('Аккаунтов: $_count'),
    );
  }
}


