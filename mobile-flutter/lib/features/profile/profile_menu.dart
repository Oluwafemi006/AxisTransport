import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_version.dart';
import '../../core/config.dart';
import '../../core/models.dart';

/// Numéro masqué pour l'en-tête : seuls les 2 derniers chiffres restent visibles.
String maskPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 4) return '';
  return '${'•' * (digits.length - 2)}${digits.substring(digits.length - 2)}';
}

/// Adresse du site, déduite de l’adresse de l’API quand elle suit la forme `api.domaine` ;
/// sinon vide, et « Partager l'application » n'est pas proposé (aucune adresse écrite dans le code).
String siteUrlFromApi([String? apiUrl]) {
  final uri = Uri.tryParse(apiUrl ?? AppConfig.apiUrl);
  if (uri == null || uri.scheme != 'https' || !uri.host.startsWith('api.')) return '';
  return 'https://${uri.host.substring(4)}';
}

void shareApp(String siteUrl) {
  SharePlus.instance.share(ShareParams(text: 'AXIS Transport : réservez vos billets de car sur $siteUrl'));
}

/// En-tête du profil : avatar, nom, identifiant, rôle (personnel) et numéro masqué s'il existe.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({super.key, required this.user, this.roleLabel});
  final User user;
  final String? roleLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = user.displayName;
    final masked = maskPhone(user.phone);
    final lines = <String>[
      'Identifiant : ${user.username}',
      if (roleLabel != null && roleLabel!.isNotEmpty) 'Rôle : $roleLabel',
      if (masked.isNotEmpty) 'Téléphone : $masked',
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: theme.colorScheme.primary,
              child: Text(
                name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.onPrimary),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, key: const Key('profile-name'), style: theme.textTheme.titleMedium),
                  for (final line in lines)
                    Text(line, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileMenuItem {
  const ProfileMenuItem({required this.icon, required this.label, required this.onTap, this.keyName});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? keyName;
}

/// Groupe de lignes dans une carte : icône, libellé, flèche.
class ProfileMenuGroup extends StatelessWidget {
  const ProfileMenuGroup({super.key, required this.items});
  final List<ProfileMenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              key: items[i].keyName == null ? null : Key(items[i].keyName!),
              leading: Icon(items[i].icon),
              title: Text(items[i].label),
              trailing: const Icon(Icons.chevron_right),
              onTap: items[i].onTap,
            ),
          ],
        ],
      ),
    );
  }
}

/// À propos : nom et version de l'application.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('À propos')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ListTile(title: Text('Application'), subtitle: Text('AXIS Transport')),
          ListTile(title: Text('Version'), subtitle: Text(appVersion, key: Key('about-version'))),
        ],
      ),
    );
  }
}
