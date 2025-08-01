// lib/pages/home_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../config/app_config.dart';
import '../routes/route_helper.dart';
import 'download_list_page.dart';
import 'video_web_detail_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    RouteHelper.routes
        .firstWhere((element) => element.name == RouteHelper.videoWebDetail)
        .page(),
    RouteHelper.routes
        .firstWhere((element) => element.name == RouteHelper.downloadList)
        .page(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.web), label: '网页'),
          BottomNavigationBarItem(icon: Icon(Icons.download), label: '下载'),
        ],
      ),
    );
  }
}
