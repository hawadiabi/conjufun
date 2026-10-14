import 'package:flutter/material.dart';
import '../main.dart' show brandBlue;
import '../viewmodels/exercise_vm.dart' as vm;

class VerbListPage extends StatefulWidget {
  const VerbListPage({super.key});

  @override
  State<VerbListPage> createState() => _VerbListPageState();
}

class _VerbListPageState extends State<VerbListPage> {
  final vm.ExerciseViewModel _viewModel = vm.ExerciseViewModel();

  bool _loading = true;
  String _search = '';
  String _groupFilter = 'all';

  List<_VerbItem> _allVerbs = [];
  List<_VerbItem> _filtered = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _viewModel.initForVerbList();

    final verbs = _viewModel.getAllVerbs();

    _allVerbs = verbs
        .map(
          (v) =>
              _VerbItem(verb: v, groupLabel: _viewModel.groupLabelForVerb(v)),
        )
        .toList();

    _filtered = List.of(_allVerbs);
    setState(() => _loading = false);
  }

  void _applyFilters() {
    final lowerSearch = _search.toLowerCase();
    setState(() {
      _filtered = _allVerbs.where((item) {
        if (lowerSearch.isNotEmpty &&
            !item.verb.toLowerCase().contains(lowerSearch)) {
          return false;
        }

        if (_groupFilter == 'all') return true;

        final g = item.groupLabel.toLowerCase();
        if (_groupFilter == 'g1') return g.contains('1er');
        if (_groupFilter == 'g2') return g.contains('2e') || g.contains('2ème');
        if (_groupFilter == 'g3') return g.contains('3e') || g.contains('3ème');
        if (_groupFilter == 'other') {
          return !(g.contains('1er') ||
              g.contains('2e') ||
              g.contains('2ème') ||
              g.contains('3e') ||
              g.contains('3ème'));
        }
        return true;
      }).toList();
    });
  }

  Future<void> _showVerbDetails(String verb) async {
    final allConj = _viewModel.getAllConjugationsForVerb(verb);

    await showDialog(
      context: context,
      builder: (_) {
        if (allConj.isEmpty) {
          return AlertDialog(
            title: Text('Conjugaison de "$verb"'),
            content: const Text(
              'Aucune conjugaison détaillée disponible pour ce verbe (dans les temps supportés).',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fermer'),
              ),
            ],
          );
        }

        return AlertDialog(
          title: Text('Conjugaison de "$verb"'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: allConj.entries.map((entry) {
                final tense = entry.key;
                final forms = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tense,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      ...forms.entries.map(
                        (f) => Text('${f.key} → ${f.value}'),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        centerTitle: true,
        shadowColor: Colors.black.withValues(alpha: .15),
        elevation: 3,
        title: const Text(
          'Liste des verbes',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              // Barre de recherche
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Rechercher un verbe...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  onChanged: (value) {
                    _search = value;
                    _applyFilters();
                  },
                ),
              ),

              // Filtres de groupe
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    _buildFilterChip('Tous', 'all'),
                    _buildFilterChip('1er groupe', 'g1'),
                    _buildFilterChip('2e groupe', 'g2'),
                    _buildFilterChip('3e groupe', 'g3'),
                    _buildFilterChip('Autres', 'other'),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Liste
              Expanded(
                child: _filtered.isEmpty
                    ? const Center(child: Text('Aucun verbe trouvé.'))
                    : ListView.separated(
                        itemCount: _filtered.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, thickness: 0.4),
                        itemBuilder: (context, index) {
                          final item = _filtered[index];
                          return ListTile(
                            title: Text(
                              item.verb,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: item.groupLabel.isNotEmpty
                                ? Text(item.groupLabel)
                                : null,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _showVerbDetails(item.verb),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final selected = _groupFilter == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: brandBlue.withValues(alpha: 0.15),
        onSelected: (_) {
          setState(() {
            _groupFilter = value;
          });
          _applyFilters();
        },
      ),
    );
  }
}

class _VerbItem {
  final String verb;
  final String groupLabel;

  _VerbItem({required this.verb, required this.groupLabel});
}
