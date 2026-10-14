import 'package:flutter/material.dart';

import '../data/app_db.dart';
import '../data/auth_repo.dart';
import '../models/custom_set.dart';
import '../viewmodels/exercise_vm.dart' as vm;
import '../main.dart' show brandBlue, brandYellow;

class EditCustomSetPage extends StatefulWidget {
  final CustomSet? existing;

  const EditCustomSetPage({super.key, this.existing});

  @override
  State<EditCustomSetPage> createState() => _EditCustomSetPageState();
}

class _EditCustomSetPageState extends State<EditCustomSetPage> {
  static const int _maxNameLength = 60;
  static const int _maxQuestionsLimit = 200;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _questionCountController = TextEditingController();

  String? _selectedSchoolLevel;
  final Set<String> _selectedTenses = {};
  final Set<String> _selectedVerbs = {};

  bool _loading = true;
  bool _saving = false;
  bool _loadFailed = false;

  // Temps et verbes que le jeu sait réellement utiliser (les mêmes que dans
  // les parties normales).
  List<String> _availableTenses = [];
  List<String> _availableVerbs = [];

  static const List<String> _schoolLevels = [
    'Cycle 1',
    'Cycle 2',
    'Cycle 3',
    'Sec 1',
    'Sec 2',
    'Expert',
  ];

  @override
  void initState() {
    super.initState();
    _initFromExisting();
    _loadData();
  }

  void _initFromExisting() {
    final existing = widget.existing;
    if (existing == null) return;

    _nameController.text = existing.name;
    _selectedSchoolLevel = _schoolLevels.contains(existing.schoolLevel)
        ? existing.schoolLevel
        : null;
    _selectedTenses.addAll(existing.tenses);
    _selectedVerbs.addAll(existing.verbs);

    if (existing.maxQuestions != null && existing.maxQuestions! > 0) {
      _questionCountController.text = existing.maxQuestions.toString();
    }
  }

  Future<void> _loadData() async {
    final tenses = vm.ExerciseViewModel.allTenseLabels();
    final verbs = await vm.ExerciseViewModel.allKnownVerbs();
    if (!mounted) return;

    setState(() {
      _availableTenses = tenses;
      _availableVerbs = verbs;
      _loadFailed = verbs.isEmpty;
      // Un temps ou un verbe inconnu du jeu ne servirait à rien : on l'enlève.
      _selectedTenses.retainAll(tenses);
      final known = verbs.toSet();
      _selectedVerbs.retainAll(known);
      _loading = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _questionCountController.dispose();
    super.dispose();
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickVerbs() async {
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return _VerbPickerSheet(
          allVerbs: _availableVerbs,
          initialSelection: _selectedVerbs,
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        _selectedVerbs
          ..clear()
          ..addAll(result);
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    if (_selectedTenses.isEmpty) {
      _toast('Choisis au moins un temps.');
      return;
    }
    if (_selectedVerbs.isEmpty) {
      _toast('Choisis au moins un verbe.');
      return;
    }

    int? maxQuestions;
    final countText = _questionCountController.text.trim();
    if (countText.isNotEmpty) {
      final parsed = int.tryParse(countText);
      if (parsed == null || parsed <= 0 || parsed > _maxQuestionsLimit) {
        _toast(
          'Le nombre de questions doit être un entier entre 1 et '
          '$_maxQuestionsLimit.',
        );
        return;
      }
      maxQuestions = parsed;
    }

    setState(() => _saving = true);

    try {
      final now = DateTime.now();
      final existing = widget.existing;
      final userId = await AuthRepo.instance.getCurrentUserId();

      final set = CustomSet(
        id: existing?.id,
        name: _nameController.text.trim(),
        schoolLevel: _selectedSchoolLevel,
        tenses: _selectedTenses.toList()..sort(),
        verbs: _selectedVerbs.toList()..sort(),
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        maxQuestions: maxQuestions,
        remoteId: existing?.remoteId,
        needsSync: true,
      );

      if (existing == null) {
        await AppDb.instance.insertCustomSet(set, userId: userId);
      } else {
        await AppDb.instance.updateCustomSet(set);
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) _toast('Impossible d’enregistrer. Réessaie.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        title: Text(isEditing ? 'Modifier l’ensemble' : 'Nouvel ensemble'),
        actions: [
          IconButton(
            onPressed: _saving ? null : _save,
            tooltip: 'Enregistrer',
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Card(
                        elevation: 3,
                        surfaceTintColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 20,
                          ),
                          child: Form(
                            key: _formKey,
                            child: _buildForm(isEditing),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildForm(bool isEditing) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: brandYellow.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.edit_note, color: brandBlue),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isEditing
                    ? 'Modifier l’ensemble personnalisé'
                    : 'Créer un nouvel ensemble',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        if (_loadFailed) ...[
          const Text(
            'La liste des verbes n’a pas pu être chargée. '
            'Ferme cet écran et réessaie.',
            style: TextStyle(color: Colors.red),
          ),
          const SizedBox(height: 12),
        ],

        // Nom
        TextFormField(
          controller: _nameController,
          maxLength: _maxNameLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nom de l’ensemble',
            hintText: 'Ex : Verbes de la cuisine – Présent',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Le nom est obligatoire.';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),

        // Niveau scolaire
        DropdownButtonFormField<String?>(
          initialValue: _selectedSchoolLevel,
          decoration: const InputDecoration(
            labelText: 'Niveau scolaire (optionnel)',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Aucun')),
            ..._schoolLevels.map(
              (lvl) => DropdownMenuItem<String?>(value: lvl, child: Text(lvl)),
            ),
          ],
          onChanged: (value) => setState(() => _selectedSchoolLevel = value),
        ),
        const SizedBox(height: 16),

        // Nombre de questions
        TextFormField(
          controller: _questionCountController,
          decoration: const InputDecoration(
            labelText: 'Nombre de questions par session (optionnel)',
            hintText: 'Ex : 10',
            helperText:
                'Si vide, l’ensemble suit le mode choisi à l’accueil '
                '(fixe ou illimité).',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 22),

        // Temps
        Row(
          children: [
            const Text(
              'Temps',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Text(
              '${_selectedTenses.length} choisis',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() {
                _selectedTenses
                  ..clear()
                  ..addAll(_availableTenses);
              }),
              child: const Text('Tout'),
            ),
            TextButton(
              onPressed: () => setState(_selectedTenses.clear),
              child: const Text('Effacer'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _availableTenses.map((tense) {
            return FilterChip(
              label: Text(_capitalize(tense)),
              selected: _selectedTenses.contains(tense),
              onSelected: (value) => setState(() {
                if (value) {
                  _selectedTenses.add(tense);
                } else {
                  _selectedTenses.remove(tense);
                }
              }),
            );
          }).toList(),
        ),
        const SizedBox(height: 22),

        // Verbes
        const Text(
          'Verbes',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _availableVerbs.isEmpty ? null : _pickVerbs,
          icon: const Icon(Icons.list_alt),
          label: Text(
            _selectedVerbs.isEmpty
                ? 'Choisir les verbes'
                : 'Verbes sélectionnés : ${_selectedVerbs.length}',
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: brandBlue.withValues(alpha: .6)),
          ),
        ),
        if (_selectedVerbs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: (_selectedVerbs.toList()..sort())
                .take(10)
                .map((v) => Chip(label: Text(v)))
                .toList(),
          ),
          if (_selectedVerbs.length > 10)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+ ${_selectedVerbs.length - 10} autres…',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ),
        ],
        const SizedBox(height: 26),

        // Bouton Enregistrer
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: brandBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check),
            label: Text(
              isEditing ? 'Enregistrer' : 'Créer',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}

class _VerbPickerSheet extends StatefulWidget {
  final List<String> allVerbs;
  final Set<String> initialSelection;

  const _VerbPickerSheet({
    required this.allVerbs,
    required this.initialSelection,
  });

  @override
  State<_VerbPickerSheet> createState() => _VerbPickerSheetState();
}

class _VerbPickerSheetState extends State<_VerbPickerSheet> {
  late Set<String> _selected;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialSelection);
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.allVerbs
        : widget.allVerbs
              .where((v) => v.toLowerCase().contains(query))
              .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Choisir les verbes',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Rechercher un verbe…',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _search = value),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // « Tout » agit sur la liste affichée (la recherche
                    // courante), pas sur les milliers de verbes d'un coup.
                    TextButton(
                      onPressed: () =>
                          setState(() => _selected.addAll(filtered)),
                      child: Text(query.isEmpty ? 'Tout' : 'Tout ajouter'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        if (query.isEmpty) {
                          _selected.clear();
                        } else {
                          _selected.removeAll(filtered);
                        }
                      }),
                      child: const Text('Aucun'),
                    ),
                    const Spacer(),
                    Text(
                      '${_selected.length} sélectionnés',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final verb = filtered[index];
                    return CheckboxListTile(
                      value: _selected.contains(verb),
                      title: Text(verb),
                      dense: true,
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          _selected.add(verb);
                        } else {
                          _selected.remove(verb);
                        }
                      }),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () =>
                          Navigator.of(context).pop<Set<String>>(_selected),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brandBlue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Terminé'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
