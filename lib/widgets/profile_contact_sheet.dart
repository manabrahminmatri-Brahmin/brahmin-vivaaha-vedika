import 'package:flutter/material.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';
import 'profile_photo.dart';

Future<void> showProfileContactSheet(
  BuildContext context,
  User user,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return DraggableScrollableSheet(
        expand: false,
        maxChildSize: 0.9,
        initialChildSize: 0.75,
        minChildSize: 0.5,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 60,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AC.textMuted(context),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  SimplePhotoAvatar(
                    photoUrl: user.profile?.profilePicture ?? '',
                    name: user.profile?.fullName ?? 'Unknown',
                    size: 72,
                    circle: true,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.profile?.fullName ?? 'Unknown',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${user.profile?.age ?? 0} yrs • ${user.profile?.height ?? ''} • ${user.profile?.city ?? ''}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (user.profile?.sect != null) Chip(label: Text(user.profile!.sect!)),
                  if (user.profile?.subSect != null) Chip(label: Text(user.profile!.subSect!)),
                  if (user.profile?.nakshatra != null) Chip(label: Text(user.profile!.nakshatra!)),
                  if (user.profile?.education != null) Chip(label: Text(user.profile!.education!)),
                  if (user.profile?.occupation != null) Chip(label: Text(user.profile!.occupation!)),
                ],
              ),
              const SizedBox(height: 20),
              Text(user.profile?.aboutMe ?? '', style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 24),
              Text(
                'Contact Information',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mobile Number',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AC.card(context),
                        ),
                      ),
                      SizedBox(height: 6),
                      SelectableText(
                        user.mobileNumber,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      ...[
                      const SizedBox(height: 16),
                      Text(
                        'Email',
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(color: AC.textMuted(context)),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(user.email),
                    ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check_circle),
                label: const Text('Mark as Contacted'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
