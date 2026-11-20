import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Terms of Service and Community Rules, shipped in the app so they can be
/// read before sign-up and without a network. Every member agrees to these
/// when they create a profile (onboarding, last step). App Store guideline
/// 1.2 asks for terms that make clear abusive or objectionable content is not
/// tolerated.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const _sections = <(String, List<String>)>[
    (
      'What Grace Match is',
      [
        'Grace Match is a matrimony service that helps Christian men and women, '
            'and their families, find a life partner for marriage. It is not a '
            'casual dating service.',
        'You must be at least 18 years old (21 for men, under Indian law) and '
            'legally free to marry to use Grace Match.',
      ],
    ),
    (
      'Your profile',
      [
        'Everything you enter must be true and about you, or about the family '
            'member whose profile you manage with their consent.',
        'Our team reviews every profile and photo before anyone else can see '
            'it, and may ask you to correct or verify details.',
        'One profile per person. Do not impersonate anyone.',
      ],
    ),
    (
      'Zero tolerance for abuse',
      [
        'There is no tolerance for objectionable content or abusive members. '
            'You must not post or send:',
        '• sexual, nude or suggestive photos or messages;',
        '• harassment, threats, hate speech or bullying;',
        '• requests for money, gifts, investments or bank details;',
        '• spam, advertising, or links to other services;',
        '• anything illegal, or anything involving a minor.',
        'We remove such content and suspend or permanently ban the account '
            'responsible, usually within 24 hours of a report, and we may '
            'inform the police where the law requires.',
      ],
    ),
    (
      'Reporting and blocking',
      [
        'You can report or block any member from their profile (the ⋯ menu) '
            'or from a chat. Reports are reviewed by our team and the person '
            'is not told who reported them.',
        'A blocked member cannot see your profile or contact you.',
      ],
    ),
    (
      'Your privacy',
      [
        'Your phone number is never shown to other members unless you approve '
            'a request to share it. Calls happen inside the app.',
        'You can delete your account at any time in Settings. How we handle '
            'your data is described in our Privacy Policy.',
      ],
    ),
    (
      'Memberships',
      [
        'Basic use of Grace Match is free. Paid memberships add features such '
            'as more daily profiles or calls; what each includes is shown on '
            'the plans page.',
      ],
    ),
    (
      'Your safety',
      [
        'Meet in public places with family present, and never send money to '
            'someone you have not met. Grace Match reviews profiles but cannot '
            'guarantee what any member says about themselves.',
        'We may suspend accounts that break these rules, and may update these '
            'terms; we will tell you in the app when we do.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Terms & Community Rules', style: AppTextStyles.labelLarge),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        children: [
          for (final (title, paras) in _sections) ...[
            const SizedBox(height: 16),
            Text(title, style: AppTextStyles.headlineSmall),
            const SizedBox(height: 8),
            for (final p in paras)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  p,
                  style: AppTextStyles.bodyMedium.copyWith(height: 1.5),
                ),
              ),
          ],
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse('${AppConstants.siteUrl}/privacy'),
              mode: LaunchMode.inAppBrowserView,
            ),
            child: Text(
              'Read the Privacy Policy',
              style: TextStyle(color: AppColors.gold),
            ),
          ),
          Text(
            'Questions: ${AppConstants.siteUrl}/contact',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
