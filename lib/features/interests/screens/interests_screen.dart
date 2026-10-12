import '../../../core/notifications/push_center.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../bloc/interests_bloc.dart';
import '../bloc/interests_event.dart';
import '../bloc/interests_state.dart';
import 'package:go_router/go_router.dart';

class InterestsScreen extends StatefulWidget {
  /// Which tab to open on — a notification links straight to its tab.
  final String? tab;

  const InterestsScreen({super.key, this.tab});

  @override
  State<InterestsScreen> createState() => _InterestsScreenState();
}

class _InterestsScreenState extends State<InterestsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: _indexFor(widget.tab));
    PushCenter.clear(const ['interests']);
    context.read<InterestsBloc>().add(FetchInterestsEvent());
  }

  static const _tabNames = ['received', 'matches', 'sent'];

  int _indexFor(String? tab) {
    final i = tab == null ? -1 : _tabNames.indexOf(tab);
    return i < 0 ? 0 : i;
  }

  @override
  void didUpdateWidget(covariant InterestsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Already on this screen when the notification was tapped.
    if (widget.tab != null && widget.tab != oldWidget.tab) {
      _tabController.animateTo(_indexFor(widget.tab));
      PushCenter.clear(const ['interests']);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InterestsBloc, InterestsState>(
      builder: (context, state) {
        int receivedCount = 0;
        int matchedCount = 0;
        int sentCount = 0;

        if (state is InterestsLoaded) {
          receivedCount = state.received.length;
          matchedCount = state.matches.length;
          sentCount = state.sent.length;
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text('Interests', style: AppTextStyles.headlineMedium),
            elevation: 0,
            backgroundColor: AppColors.background,
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.gold,
              labelColor: AppColors.gold,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: AppTextStyles.labelMedium,
              dividerColor: AppColors.surfaceHighest,
              tabs: [
                Tab(text: 'Received ($receivedCount)'),
                Tab(text: 'Matches ($matchedCount)'),
                Tab(text: 'Sent ($sentCount)'),
              ],
            ),
          ),
          body: state is InterestsLoading 
            ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
            : state is InterestsError
            ? Center(child: Text(state.message, style: const TextStyle(color: Colors.white)))
            : state is InterestsLoaded
            ? TabBarView(
                controller: _tabController,
                children: [
                  RefreshIndicator(
                    onRefresh: () async {
                      context.read<InterestsBloc>().add(FetchInterestsEvent());
                    },
                    color: AppColors.gold,
                    child: _buildInterestList(state.received, isReceived: true),
                  ),
                  RefreshIndicator(
                    onRefresh: () async {
                      context.read<InterestsBloc>().add(FetchInterestsEvent());
                    },
                    color: AppColors.gold,
                    child: _buildInterestList(state.matches, isMatch: true),
                  ),
                  RefreshIndicator(
                    onRefresh: () async {
                      context.read<InterestsBloc>().add(FetchInterestsEvent());
                    },
                    color: AppColors.gold,
                    child: _buildInterestList(state.sent),
                  ),
                ],
              )
            : const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildInterestList(List<Map<String, dynamic>> items, {bool isReceived = false, bool isMatch = false}) {
    if (items.isEmpty) {
      String title = isMatch ? 'No matches yet' : (isReceived ? 'No interests received' : 'No interests sent');
      String desc = isMatch ? 'Keep exploring the discover feed.' : 'You haven\'t received any likes recently.';
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Container(
            height: constraints.maxHeight,
            alignment: Alignment.center,
            child: _buildEmptyTab(title, desc),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 16, bottom: 100),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final profile = items[index];
        return GestureDetector(
          onTap: () {
            final id =
                profile['profile_id']?.toString() ??
                profile['user_id']?.toString() ??
                profile['id']?.toString();
            if (id != null && id.isNotEmpty) {
              context.push('/profile/$id?source=interests');
            }
          },
          child: Container(
            margin: const EdgeInsets.only(left: 24, right: 24, bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.surfaceHighest),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surfaceHighest,
                        border: Border.all(color: AppColors.goldMild, width: 2),
                        image: profile['photo_url'] != null
                          ? DecorationImage(
                              image: CachedNetworkImageProvider(profile['photo_url']),
                              fit: BoxFit.cover,
                            )
                          : null,
                      ),
                      child: profile['photo_url'] == null
                        ? const Icon(Icons.person, color: AppColors.textTertiary, size: 28)
                        : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${profile['name'] ?? 'Member'}, ${profile['age'] ?? ''}'.trim(),
                            style: AppTextStyles.labelLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${profile['denomination'] ?? ''} • ${profile['profession'] ?? ''}',
                            style: AppTextStyles.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (isReceived) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            context.read<InterestsBloc>().add(InterestActionEvent(
                              interestId: profile['interest_id'].toString(),
                              accept: true,
                            ));
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.gold,
                            foregroundColor: AppColors.textOnGold,
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Accept'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            context.read<InterestsBloc>().add(InterestActionEvent(
                              interestId: profile['interest_id'].toString(),
                              accept: false,
                            ));
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            side: const BorderSide(color: AppColors.surfaceHighest),
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Decline'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (isMatch) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final convId = profile['conversation_id']?.toString();
                        if (convId != null) {
                          final profileId =
                              profile['profile_id']?.toString() ??
                              profile['user_id']?.toString() ??
                              profile['id']?.toString();
                          context.push('/chat/$convId', extra: {
                            'name': profile['name'],
                            'photo': profile['photo_url'],
                            'userId': profileId,
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.goldSubtle,
                        foregroundColor: AppColors.gold,
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Message'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyTab(String title, String desc) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.favorite_outline_rounded, size: 64, color: AppColors.surfaceHighest),
          const SizedBox(height: 16),
          Text(title, style: AppTextStyles.headlineSmall),
          const SizedBox(height: 8),
          Text(desc, style: AppTextStyles.bodyMedium),
        ],
      ),
    );
  }
}
