import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/search/search_history_store.dart';

final searchHistoryStoreProvider = Provider((_) => SearchHistoryStore());

final searchHistoryProvider = StateNotifierProvider.autoDispose<
    SearchHistoryNotifier, List<SearchHistoryEntry>>(
  (ref) => SearchHistoryNotifier(ref.watch(searchHistoryStoreProvider)),
);

class SearchHistoryNotifier extends StateNotifier<List<SearchHistoryEntry>> {
  SearchHistoryNotifier(this._store) : super(const []) {
    _load();
  }

  final SearchHistoryStore _store;

  Future<void> _load() async {
    state = await _store.load();
  }

  Future<void> add(String keyword) async {
    state = await _store.add(keyword);
  }

  Future<void> clear() async {
    await _store.clear();
    state = const [];
  }
}
