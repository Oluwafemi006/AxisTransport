import React, { useState } from 'react';
import { View, Text, Pressable, StyleSheet, ScrollView, TextInput } from 'react-native';
import { palette, radius, spacing } from '../theme';
import { trips } from '../mock';

type Props = {
  onSelectTrip: (id: number) => void;
};

export function SearchScreen({ onSelectTrip }: Props) {
  const [from, setFrom] = useState('Cotonou');
  const [to, setTo] = useState('Parakou');

  return (
    <ScrollView contentContainerStyle={styles.container} showsVerticalScrollIndicator={false}>
      <Text style={styles.title}>Recherche de trajet</Text>

      <View style={styles.formCard}>
        <Text style={styles.label}>Départ</Text>
        <TextInput style={styles.input} value={from} onChangeText={setFrom} />

        <Text style={styles.label}>Destination</Text>
        <TextInput style={styles.input} value={to} onChangeText={setTo} />

        <Pressable style={styles.primaryButton}>
          <Text style={styles.primaryText}>Rechercher</Text>
        </Pressable>
      </View>

      <Text style={styles.sectionTitle}>Trajets disponibles</Text>
      {trips.map(trip => (
        <Pressable key={trip.id} onPress={() => onSelectTrip(trip.id)} style={styles.tripCard}>
          <View style={styles.tripHeader}>
            <Text style={styles.tripRoute}>{trip.route}</Text>
            <Text style={styles.tripPrice}>{trip.price}</Text>
          </View>
          <Text style={styles.tripMeta}>{trip.departure} → {trip.arrival}</Text>
          <View style={styles.tripFooter}>
            <Text style={styles.tripMeta}>{trip.time}</Text>
            <Text style={styles.seats}>{trip.seatsLeft} places libres</Text>
          </View>
        </Pressable>
      ))}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    padding: spacing.md,
    paddingBottom: 110,
    gap: spacing.md,
  },
  title: {
    fontSize: 24,
    fontWeight: '800',
    color: palette.black,
  },
  formCard: {
    backgroundColor: palette.white,
    borderRadius: radius.xl,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: '#E8EEF7',
  },
  label: {
    fontSize: 12,
    fontWeight: '700',
    color: '#53657B',
    marginBottom: 8,
    marginTop: 4,
  },
  input: {
    backgroundColor: '#F8FBFF',
    borderWidth: 1,
    borderColor: '#D9E4F4',
    borderRadius: radius.md,
    paddingHorizontal: spacing.md,
    paddingVertical: 12,
    fontSize: 14,
    color: palette.black,
  },
  primaryButton: {
    marginTop: spacing.md,
    backgroundColor: palette.navy,
    borderRadius: radius.md,
    paddingVertical: 14,
    alignItems: 'center',
  },
  primaryText: {
    color: palette.white,
    fontWeight: '800',
    fontSize: 14,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '800',
    color: palette.black,
  },
  tripCard: {
    backgroundColor: palette.white,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: '#E8EEF7',
    padding: spacing.md,
  },
  tripHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  tripRoute: {
    fontSize: 16,
    fontWeight: '800',
    color: palette.black,
  },
  tripPrice: {
    fontSize: 15,
    fontWeight: '800',
    color: palette.navy,
  },
  tripMeta: {
    marginTop: 6,
    fontSize: 12,
    color: '#64748B',
  },
  tripFooter: {
    marginTop: 14,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  seats: {
    fontSize: 12,
    fontWeight: '700',
    color: palette.navy,
  },
});
