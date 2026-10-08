import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

const _parcelSteps = [
  'REGISTERED',
  'DEPOSITED',
  'ACCEPTED',
  'ASSIGNED',
  'LOADED',
  'IN_TRANSIT',
  'ARRIVED',
  'READY_FOR_PICKUP',
  'PICKED_UP',
];

class ParcelsScreen extends ConsumerStatefulWidget {
  const ParcelsScreen({super.key});

  @override
  ConsumerState<ParcelsScreen> createState() => _ParcelsScreenState();
}

class _ParcelsScreenState extends ConsumerState<ParcelsScreen> {
  final _sender = TextEditingController();
  final _senderPhone = TextEditingController();
  final _recipient = TextEditingController();
  final _recipientPhone = TextEditingController();
  final _description = TextEditingController();
  final _weight = TextEditingController();
  List<Place> _locations = [];
  List<Parcel> _parcels = [];
  int? _origin;
  int? _destination;
  bool _loading = true;
  bool _authenticated = false;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _sender,
      _senderPhone,
      _recipient,
      _recipientPhone,
      _description,
      _weight,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    try {
      final locations = await api.locations();
      var parcels = <Parcel>[];
      var authenticated = false;
      try {
        final user = await api.me();
        authenticated = user.isClient;
        if (authenticated) parcels = await api.parcels();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _locations = locations;
          _parcels = parcels;
          _authenticated = authenticated;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = error.toString();
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_authenticated) {
      context.push('/login');
      return;
    }
    if (_origin == null || _destination == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final parcel = await ref
          .read(apiClientProvider)
          .createParcel(
            senderName: _sender.text.trim(),
            senderPhone: _senderPhone.text.trim(),
            recipientName: _recipient.text.trim(),
            recipientPhone: _recipientPhone.text.trim(),
            origin: _origin!,
            destination: _destination!,
            description: _description.text.trim(),
            weightKg: _weight.text.trim(),
          );
      _sender.clear();
      _senderPhone.clear();
      _recipient.clear();
      _recipientPhone.clear();
      _description.clear();
      _weight.clear();
      if (mounted) {
        setState(() {
          _parcels = [parcel, ..._parcels];
          _message = 'Colis enregistré : ${parcel.trackingNumber}';
          _origin = null;
          _destination = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _complete =>
      _sender.text.trim().isNotEmpty &&
      _senderPhone.text.trim().isNotEmpty &&
      _recipient.text.trim().isNotEmpty &&
      _recipientPhone.text.trim().isNotEmpty &&
      _description.text.trim().isNotEmpty &&
      _origin != null &&
      _destination != null &&
      _origin != _destination;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
      children: [
        const Text(
          'NOUVEL ENVOI',
          style: TextStyle(
            color: AxisColors.blue,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Déclarer un colis',
          style: TextStyle(
            color: AxisColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 14),
        if (!_authenticated)
          AxisCard(
            onTap: () => context.push('/login'),
            child: const Column(
              children: [
                Text(
                  'Connectez-vous pour expédier',
                  style: TextStyle(
                    color: AxisColors.navy,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Votre colis et son suivi seront rattachés uniquement à votre compte client.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AxisColors.muted, height: 1.4),
                ),
              ],
            ),
          )
        else
          AxisCard(
            child: Column(
              children: [
                TextField(
                  controller: _sender,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Nom de l’expéditeur',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _senderPhone,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Téléphone de l’expéditeur',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _recipient,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Nom du destinataire',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _recipientPhone,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Téléphone du destinataire',
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  initialValue: _origin,
                  decoration: const InputDecoration(
                    labelText: 'Agence de départ',
                  ),
                  items: _locations
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _origin = value),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  initialValue: _destination,
                  decoration: const InputDecoration(
                    labelText: 'Agence de destination',
                  ),
                  items: _locations
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _destination = value),
                ),
                if (_origin != null && _origin == _destination)
                  const Notice(
                    'Le départ et la destination doivent être différents.',
                    error: true,
                  ),
                const SizedBox(height: 14),
                TextField(
                  controller: _description,
                  onChanged: (_) => setState(() {}),
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description du colis',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _weight,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Poids en kg (facultatif)',
                  ),
                ),
                if (_message != null)
                  Notice(
                    _message!,
                    error: !_message!.startsWith('Colis enregistré'),
                  ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _busy || !_complete ? null : _submit,
                  child: Text(_busy ? 'Patientez…' : 'Enregistrer le colis'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 22),
        const Text(
          'Suivre mes colis',
          style: TextStyle(
            color: AxisColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 14),
        if (_parcels.isEmpty)
          const AxisCard(
            child: Text(
              'Aucun colis enregistré',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          )
        else
          ..._parcels.map((parcel) => _ParcelCard(parcel: parcel)),
      ],
    );
  }
}

class _ParcelCard extends StatelessWidget {
  const _ParcelCard({required this.parcel});
  final Parcel parcel;

  @override
  Widget build(BuildContext context) {
    final current = _parcelSteps.indexOf(parcel.status);
    return AxisCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      parcel.trackingNumber,
                      style: const TextStyle(
                        color: AxisColors.blue,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${parcel.origin.name} → ${parcel.destination.name}',
                      style: const TextStyle(
                        color: AxisColors.text,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F1FB),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  parcel.statusDisplay,
                  style: const TextStyle(
                    color: AxisColors.navy,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(
              _parcelSteps.length,
              (index) => Expanded(
                child: Container(
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: index <= current
                        ? AxisColors.blue
                        : const Color(0xFFDDE7F1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
