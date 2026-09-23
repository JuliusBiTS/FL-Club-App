import 'package:cached_network_image/cached_network_image.dart';
import 'package:flc_core/flc_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/auth/profile_provider.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../membership/membership_providers.dart';
import '../data/profile_photo_repository.dart';

/// "I also need an in app way to change user settings and maybe add a picture
/// to the account and membership card." One screen: picture, name, phone and
/// the news opt-in. Everything membership-related (status, number, expiry) is
/// deliberately absent — that's only changeable by an admin, enforced by a
/// database trigger, not just by this screen leaving it out.
class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  ConsumerState<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends ConsumerState<ProfileSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _displayName = TextEditingController();
  final _phone = TextEditingController();
  bool _marketing = false;
  bool _loaded = false;
  bool _saving = false;
  bool _photoBusy = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fullName.dispose();
    _displayName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) throw StateError('signed out');
      final row = await ref
          .read(supabaseClientProvider)
          .from('profiles')
          .select('full_name, display_name, phone, marketing_opt_in')
          .eq('id', user.id)
          .single();
      if (!mounted) return;
      setState(() {
        _fullName.text = (row['full_name'] as String?) ?? '';
        _displayName.text = (row['display_name'] as String?) ?? '';
        _phone.text = (row['phone'] as String?) ?? '';
        _marketing = (row['marketing_opt_in'] as bool?) ?? false;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loadError = "Couldn't load your details. Check your connection and try again.");
    }
  }

  /// The card caches the name and photo on the phone; pull the new ones now
  /// (members only — anyone else simply has no card, which is fine).
  Future<void> _refreshCard() async {
    try {
      await ref.read(memberCardRepositoryProvider).refresh();
    } catch (_) {}
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final user = ref.read(currentUserProvider)!;
      String? nullIfBlank(String s) => s.trim().isEmpty ? null : s.trim();
      await ref.read(supabaseClientProvider).from('profiles').update(<String, dynamic>{
        'full_name': nullIfBlank(_fullName.text),
        'display_name': nullIfBlank(_displayName.text),
        'phone': nullIfBlank(_phone.text),
        'marketing_opt_in': _marketing,
      }).eq('id', user.id);
      ref.invalidate(currentProfileProvider);
      await _refreshCard();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved.')));
      Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save. Please try again.")));
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      // Re-encoded and shrunk on the phone before upload: small, and any
      // location data in the original is left behind.
      final XFile? file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 640,
        maxHeight: 640,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );
      if (file == null) return;
      setState(() => _photoBusy = true);
      await ref.read(profilePhotoRepositoryProvider).upload(await file.readAsBytes());
      ref.invalidate(profilePhotoUrlProvider);
      await _refreshCard();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Picture updated.')));
    } on ProfilePhotoException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't use that picture.")));
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _removePhoto() async {
    setState(() => _photoBusy = true);
    try {
      await ref.read(profilePhotoRepositoryProvider).remove();
      ref.invalidate(profilePhotoUrlProvider);
      await _refreshCard();
    } on ProfilePhotoException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  void _photoSheet(bool hasPhoto) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from your photos'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: Icon(Icons.delete_outline, color: FlcColors.errorAccent(context)),
                title: Text('Remove picture', style: TextStyle(color: FlcColors.errorAccent(context))),
                onTap: () {
                  Navigator.pop(ctx);
                  _removePhoto();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? photoUrl = ref.watch(profilePhotoUrlProvider).valueOrNull;
    final String email = ref.watch(currentUserProvider)?.email ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Your details')),
      body: _loadError != null
          ? Center(child: Padding(padding: const EdgeInsets.all(FlcSpace.lg), child: Text(_loadError!, textAlign: TextAlign.center)))
          : !_loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(FlcSpace.md),
                  children: <Widget>[
                    Center(
                      child: Column(
                        children: <Widget>[
                          Stack(
                            alignment: Alignment.center,
                            children: <Widget>[
                              CircleAvatar(
                                radius: 52,
                                backgroundColor: FlcColors.ink,
                                backgroundImage: photoUrl == null ? null : CachedNetworkImageProvider(photoUrl, cacheKey: 'profile-photo'),
                                child: photoUrl == null ? const Icon(Icons.person_outline, size: 44, color: Colors.white) : null,
                              ),
                              if (_photoBusy) const CircularProgressIndicator(),
                            ],
                          ),
                          const SizedBox(height: FlcSpace.sm),
                          TextButton.icon(
                            onPressed: _photoBusy ? null : () => _photoSheet(photoUrl != null),
                            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                            label: Text(photoUrl == null ? 'Add a picture' : 'Change picture'),
                          ),
                          Text(
                            'Used on your account and, if you\'re a member, your membership card — staff see it when checking you in. '
                            'It\'s stored privately and never shown to other members or the public.',
                            textAlign: TextAlign.center,
                            style: FlcTextStyles.bodySmall.copyWith(color: FlcColors.secondary(context)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: FlcSpace.lg),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: <Widget>[
                          TextFormField(
                            controller: _fullName,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(labelText: 'Full name'),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                          ),
                          const SizedBox(height: FlcSpace.sm),
                          TextFormField(
                            controller: _displayName,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(labelText: 'Display name (optional)', helperText: 'What we call you in the app'),
                          ),
                          const SizedBox(height: FlcSpace.sm),
                          TextFormField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(labelText: 'Phone (optional)'),
                          ),
                          const SizedBox(height: FlcSpace.sm),
                          TextFormField(
                            initialValue: email,
                            enabled: false,
                            decoration: const InputDecoration(labelText: 'Email', helperText: 'Contact the club to change this'),
                          ),
                          const SizedBox(height: FlcSpace.xs),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Keep me posted about events and news'),
                            value: _marketing,
                            onChanged: (v) => setState(() => _marketing = v),
                          ),
                          const SizedBox(height: FlcSpace.md),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _saving ? null : _save,
                              child: _saving
                                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('Save'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
