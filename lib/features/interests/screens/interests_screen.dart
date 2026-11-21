import '../../../core/notifications/push_center.dart';
import '../../../core/l10n/app_language.dart';
import '../../discover/widgets/profile_list_card.dart' show denominationLabels;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/widgets/skeleton.dart';
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

class _InterestsScreenState extends State<InterestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: _indexFor(widget.tab),
    );
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
    return BlocConsumer<InterestsBloc, InterestsState>(
      listenWhen: (_, curr) =>
          curr is InterestsLoaded && curr.actionError != null,
      listener: (context, state) {
        final msg = (state as InterestsLoaded).actionError!;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(msg),
            backgroundColor: AppColors.error,
          ),
        );
      },
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
            title: Text(tr('Interests'), style: AppTextStyles.headlineMedium),
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
                Tab(text: 'Accepted ($matchedCount)'),
                Tab(text: 'Sent ($sentCount)'),
              ],
            ),
          ),
          body: state is InterestsLoading || state is InterestsInitial
              ? const SkeletonList()
              : state is InterestsError
              ? Center(
                  child: Text(
                    state.message,
                    style: const TextStyle(color: Colors.white),
                  ),
                )
              : state is InterestsLoaded
              ? TabBarView(
                  controller: _tabController,
                  children: [
                    RefreshIndicator(
                      onRefresh: () async {
                        context.read<InterestsBloc>().add(
                          FetchInterestsEvent(),
                        );
                      },
                      color: AppColors.gold,
                      child: _buildInterestList(
                        state.received,
                        isReceived: true,
                      ),
                    ),
                    RefreshIndicator(
                      onRefresh: () async {
                        context.read<InterestsBloc>().add(
                          FetchInterestsEvent(),
                        );
                      },
                      color: AppColors.gold,
                      child: _buildInterestList(state.matches, isMatch: true),
                    ),
                    RefreshIndicator(
                      onRefresh: () async {
                        context.read<InterestsBloc>().add(
                          FetchInterestsEvent(),
                        );
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

  Widget _buildInterestList(
    List<Map<String, dynamic>> items, {
    bool isReceived = false,
    bool isMatch = false,
  }) {
    if (items.isEmpty) {
      String title = isMatch
          ? tr('No accepted interests yet')
          : (isReceived
                ? tr('No interests received')
                : tr('No interests sent'));
      String desc = isMatch
          ? tr(
              'When an interest is accepted on either side, you can talk here.',
            )
          : isReceived
          ? tr('Interests other members send you will appear here.')
          : tr('Send an interest from Discover to start a conversation.');
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
        final avatar = thumbOr(profile, 'photo_url_200', 'photo_url');
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
                        image: avatar != null
                            ? DecorationImage(
                                image: avatarImage(context, avatar, 56),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: avatar == null
                          ? const Icon(
                              Icons.person,
                              color: AppColors.textTertiary,
                              size: 28,
                            )
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            [
                              profile['name']?.toString() ?? 'Member',
                              if (profile['age'] != null) '${profile['age']}',
                            ].join(', '),
                            style: AppTextStyles.labelLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                                  if (denominationLabels[profile['denomination']
                                          ?.toString()]
                                      case final d?)
                                    tr(d),
                                  profile['profession']?.toString(),
                                ]
                                .whereType<String>()
                                .where((x) => x.isNotEmpty)
                                .join(' • '),
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
                            context.read<InterestsBloc>().add(
                              InterestActionEvent(
                                interestId: profile['interest_id'].toString(),
                                accept: true,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.gold,
                            foregroundColor: AppColors.textOnGold,
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(tr('Accept')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            context.read<InterestsBloc>().add(
                              InterestActionEvent(
                                interestId: profile['interest_id'].toString(),
                                accept: false,
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            side: const BorderSide(
                              color: AppColors.surfaceHighest,
                            ),
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(tr('Decline')),
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
                          context.push(
                            '/chat/$convId',
                            extra: {
                              'name': profile['name'],
                              'photo': profile['photo_url'],
                              'userId': profileId,
                            },
                          );
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
                      child: Text(tr('Message')),
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
          const Icon(
            Icons.mark_email_unread_outlined,
            size: 64,
            color: AppColors.surfaceHighest,
          ),
          const SizedBox(height: 16),
          Text(title, style: AppTextStyles.headlineSmall),
          const SizedBox(height: 8),
          Text(desc, style: AppTextStyles.bodyMedium),
        ],
      ),
    );
  }
}
