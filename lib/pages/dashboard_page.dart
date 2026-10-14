import 'package:flutter/material.dart';
import '../pages/badges_pages.dart';
import '../pages/stats_overview_page.dart';
import '../main.dart' show brandBlue, brandYellow;
import '../ui/app_colors.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tableau de bord'),
          backgroundColor: brandBlue,
          foregroundColor: Colors.white,
          centerTitle: true,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: brandYellow,
            unselectedLabelColor: Colors.white,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            tabs: [
              Tab(icon: Icon(Icons.emoji_events), text: 'Badges'),
              Tab(icon: Icon(Icons.show_chart), text: 'Statistiques'),
            ],
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: context.pageGradient,
            ),
          ),
          child: const TabBarView(
            children: [
              // 1) Badges
              BadgesPage(),

              // 2) Statistiques
              StatsOverviewContent(),
            ],
          ),
        ),
      ),
    );
  }
}
