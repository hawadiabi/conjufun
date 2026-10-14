import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../data/app_db.dart';
import '../data/auth_repo.dart';
import '../models/custom_set.dart';
import 'edit_custom_set_page.dart';
import 'home_page.dart' show SessionMode;
import '../viewmodels/exercise_vm.dart' as vm;
import 'exercise_page.dart';
import '../ui/app_colors.dart';
import '../main.dart' show brandBlue, brandYellow;

class CreatorHomePage extends StatefulWidget {
  final SessionMode mode;
  final int fixedCount;
  final vm.GameLevel level;

  const CreatorHomePage({
    super.key,
    required this.mode,
    required this.fixedCount,
    required this.level,
  });

  @override
  State<CreatorHomePage> createState() => _CreatorHomePageState();
}

class _CreatorHomePageState extends State<CreatorHomePage> {
  bool _loading = true;
  List<CustomSet> _sets = [];

  @override
  void initState() {
    super.initState();
    _loadSets();
  }

  Future<void> _loadSets() async {
    // Les ensembles appartiennent au compte connecté (ou à l'invité).
    final userId = await AuthRepo.instance.getCurrentUserId();
    final sets = await AppDb.instance.getCustomSets(userId: userId);
    if (!mounted) return;
    setState(() {
      _sets = sets;
      _loading = false;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- OUVRIR / MODIFIER / SUPPRIMER ----------

  void _play(CustomSet set) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExercisePage(
          mode: widget.mode,
          fixedCount: widget.mode == SessionMode.fixed
              ? widget.fixedCount
              : null,
          level: widget.level,
          customSet: set,
        ),
      ),
    );
  }

  Future<void> _openEditor([CustomSet? existing]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditCustomSetPage(existing: existing)),
    );
    if (changed == true) await _loadSets();
  }

  Future<void> _confirmDelete(CustomSet set) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Supprimer cet ensemble ?'),
        content: Text('« ${set.name} » sera supprimé définitivement.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || set.id == null) return;
    await AppDb.instance.deleteCustomSet(set.id!);
    await _loadSets();
  }

  // ---------- EXPORT ----------

  Future<void> _exportSet(CustomSet set) async {
    final code = set.exportCode();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Code de partage',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ensemble : ${set.name}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Copie ce code pour partager l’ensemble.\n'
                'La personne qui le reçoit pourra l’importer dans ConjuFun.',
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.softPanel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: brandBlue.withValues(alpha: .25)),
                ),
                child: SelectableText(
                  code,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.only(right: 12, bottom: 8),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                if (mounted) _toast('Code copié dans le presse-papiers.');
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copier'),
              style: ElevatedButton.styleFrom(
                backgroundColor: brandBlue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------- IMPORT ----------

  /// Lit un code de partage et retourne l'ensemble prêt à enregistrer, ou
  /// lance un message lisible si le code est inutilisable.
  Future<CustomSet> _parseShareCode(String raw) async {
    final parsed = CustomSet.fromShareCode(raw.trim());
    if (parsed == null) {
      throw const FormatException(
        'Code invalide. Vérifie qu’il est complet (il commence par CFSET1|).',
      );
    }

    // On ne garde que les temps et les verbes que le jeu connaît vraiment.
    final knownTenses = vm.ExerciseViewModel.allTenseLabels().toSet();
    final knownVerbs = (await vm.ExerciseViewModel.allKnownVerbs()).toSet();
    final tenses = parsed.tenses.where(knownTenses.contains).toList();
    final verbs = parsed.verbs.where(knownVerbs.contains).toList();

    if (parsed.name.isEmpty) {
      throw const FormatException('Ce code ne contient pas de nom.');
    }
    if (tenses.isEmpty) {
      throw const FormatException('Ce code ne contient aucun temps reconnu.');
    }
    if (verbs.isEmpty) {
      throw const FormatException('Ce code ne contient aucun verbe reconnu.');
    }

    return parsed.copyWith(tenses: tenses, verbs: verbs);
  }

  Future<void> _showImportDialog() async {
    final controller = TextEditingController();
    String? error;
    var busy = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            Future<void> doImport() async {
              if (busy) return;
              final code = controller.text.trim();
              if (code.isEmpty) {
                setLocal(() => error = 'Colle un code de partage.');
                return;
              }
              setLocal(() {
                busy = true;
                error = null;
              });
              try {
                final parsed = await _parseShareCode(code);
                final userId = await AuthRepo.instance.getCurrentUserId();
                final now = DateTime.now();
                final toSave = parsed.copyWith(
                  createdAt: now,
                  updatedAt: now,
                  needsSync: true,
                );
                await AppDb.instance.insertCustomSet(toSave, userId: userId);

                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                if (!mounted) return;
                await _loadSets();
                _toast('Ensemble « ${toSave.name} » importé avec succès.');
              } on FormatException catch (e) {
                setLocal(() {
                  error = e.message;
                  busy = false;
                });
              } catch (_) {
                setLocal(() {
                  error = 'Erreur lors de l’import. Réessaie plus tard.';
                  busy = false;
                });
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text('Importer un ensemble'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Colle ici le code de partage (il commence par CFSET1|).',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'CFSET1|...',
                      errorText: error,
                    ),
                  ),
                ],
              ),
              actionsPadding: const EdgeInsets.only(right: 12, bottom: 8),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Annuler'),
                ),
                ElevatedButton(
                  onPressed: busy ? null : doImport,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandBlue,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(busy ? 'Import...' : 'Importer'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  // ---------- BUILD ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        title: const Text('Mode créateur'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Importer un ensemble',
            onPressed: _showImportDialog,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: brandYellow,
        foregroundColor: brandBlue,
        tooltip: 'Nouvel ensemble',
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
      body: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildIntroCard(),
                          const SizedBox(height: 16),
                          Expanded(
                            child: _sets.isEmpty
                                ? _buildEmptyState()
                                : ListView.separated(
                                    itemCount: _sets.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (context, index) {
                                      final set = _sets[index];
                                      return _SetCard(
                                        set: set,
                                        onPlay: () => _play(set),
                                        onEdit: () => _openEditor(set),
                                        onExport: () => _exportSet(set),
                                        onDelete: () => _confirmDelete(set),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntroCard() {
    return Card(
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: brandYellow.withValues(alpha: .3),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.auto_fix_high,
                color: brandBlue,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Crée tes propres exercices',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Sélectionne des verbes et des temps pour fabriquer des '
                    'ensembles personnalisés. Touche un ensemble pour jouer.',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Card(
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.library_add_outlined, size: 42, color: brandBlue),
              SizedBox(height: 10),
              Text(
                'Aucun ensemble personnalisé pour le moment.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 6),
              Text(
                'Appuie sur le bouton + pour créer ton premier ensemble, '
                'ou importe un code de partage.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Carte d'un ensemble dans la liste.
class _SetCard extends StatelessWidget {
  final CustomSet set;
  final VoidCallback onPlay;
  final VoidCallback onEdit;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  const _SetCard({
    required this.set,
    required this.onPlay,
    required this.onEdit,
    required this.onExport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final level = set.schoolLevel?.trim() ?? '';
    final hasMax = set.maxQuestions != null && set.maxQuestions! > 0;

    return Card(
      elevation: 2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: brandBlue.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.layers_outlined, color: brandBlue),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      set.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      set.tenses.join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: context.mutedText),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (level.isNotEmpty) _chip(level),
                        _chip('${set.verbs.length} verbes'),
                        _chip('${set.tenses.length} temps'),
                        if (hasMax) _chip('${set.maxQuestions} questions'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _icon(Icons.edit_outlined, 'Modifier', onEdit),
                      _icon(Icons.ios_share, 'Exporter', onExport),
                    ],
                  ),
                  _icon(Icons.delete_outline_rounded, 'Supprimer', onDelete),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String text) => Chip(
    label: Text(text),
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
  );

  Widget _icon(IconData icon, String tooltip, VoidCallback onPressed) =>
      IconButton(
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
      );
}
