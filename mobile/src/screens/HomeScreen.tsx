import React from 'react';
import { View, Text, Pressable, StyleSheet, ScrollView } from 'react-native';
import { palette, radius, spacing } from '../theme';
import { trips } from '../mock';

const quickActions = [
  { label: 'Billet', sub: 'Réserver', key: 'search' },
  { label: 'Colis', sub: 'Envoyer', key: 'parcels' },
  { label: 'Location', sub: 'Véhicule', key: 'rentals' },
];

type Props = {
  onNavigate: (screen: string) => void;
};

export function HomeScreen({ onNavigate }: Props) {
  const nextTrip = trips[0];

  return (
    <ScrollView contentContainerStyle={styles.container} showsVerticalScrollIndicator={false}>
      <View style={styles.headerCard}>
        <Text style={styles.greeting}>Bonjour</Text>
        <Text style={styles.title}>La route, les colis et vos déplacements réunis.</Text>
        <Text style={styles.subtitle}>Réservez depuis votre navigateur, conservez votre ticket et suivez chaque étape de votre expédition.</Text>
      </View>

      <View style={styles.quickRow}>
        {quickActions.map((item, index) => (
          <Pressable
            key={item.key}
            onPress={() => onNavigate(item.key)}
            style={styles.quickCard}
          >
            <Text style={styles.quickIndex}>0{index + 1}</Text>
            <Text style={styles.quickLabel}>{item.label}</Text>
            <Text style={styles.quickSub}>{item.sub}</Text>
          </Pressable>
        ))}
      </View>

      <View style={styles.sectionCard}> 
        <View style={styles.sectionHeader}>
          <Text style={styles.sectionEyebrow}>Prochain départ</Text>
          <Pressable onPress={() => onNavigate('search')}>
            <Text style={styles.linkText}>Voir tout</Text>
          </Pressable>
        </View>

        <View style={styles.tripCard}> 
          <Text style={styles.tripRoute}>{nextTrip.route}</Text>
          <Text style={styles.tripMeta}>{nextTrip.departure} • {nextTrip.time} • {nextTrip.seatsLeft} places</Text>
          <Text style={styles.tripPrice}>{nextTrip.price}</Text>
        </View>
      </View>

      <View style={styles.sectionCardSmall}>
        <View style={styles.sectionHeader}>
          <Text style={styles.sectionEyebrow}>Colis en cours</Text>
          <Pressable onPress={() => onNavigate('parcels')}>
            <Text style={styles.linkText}>Suivre</Text>
          </Pressable>
        </View>
        <View style={styles.emptyBox}>
          <Text style={styles.emptyTitle}>Aucun colis</Text>
          <Text style={styles.emptyText}>Connectez-vous pour voir votre suivi.</Text>
        </View>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    padding: spacing.md,
    paddingBottom: 110,
    gap: spacing.md,
  },
  headerCard: {
    backgroundColor: palette.navy,
    borderRadius: radius.xl,
    padding: spacing.lg,
  },
  greeting: {
    color: '#D9E9FF',
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 0.2,
  },
  title: {
    color: palette.white,
    fontSize: 25,
    fontWeight: '800',
    marginTop: 10,
    lineHeight: 32,
  },
  subtitle: {
    color: '#E6F0FF',
    fontSize: 12,
    lineHeight: 18,
    marginTop: 10,
  },
  quickRow: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  quickCard: {
    flex: 1,
    borderRadius: radius.lg,
    backgroundColor: '#F5F8FD',
    borderWidth: 1,
    borderColor: '#E2E9F4',
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.sm,
    alignItems: 'center',
  },
  quickIndex: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: palette.navy,
    color: palette.white,
    textAlign: 'center',
    lineHeight: 36,
    fontSize: 12,
    fontWeight: '800',
  },
  quickLabel: {
    marginTop: 12,
    fontSize: 13,
    fontWeight: '800',
    color: palette.black,
  },
  quickSub: {
    marginTop: 4,
    fontSize: 10,
    color: '#64748B',
  },
  sectionCard: {
    backgroundColor: '#1F3F5D',
    borderRadius: radius.xl,
    padding: spacing.md,
  },
  sectionCardSmall: {
    backgroundColor: palette.white,
    borderRadius: radius.xl,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: '#E5EDF6',
  },
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  sectionEyebrow: {
    fontSize: 11,
    color: '#D5E1F4',
    fontWeight: '800',
    letterSpacing: 1.2,
    textTransform: 'uppercase',
  },
  linkText: {
    fontSize: 11,
    color: '#D5E1F4',
    fontWeight: '800',
  },
  tripCard: {
    backgroundColor: '#DDE7F1',
    borderRadius: radius.md,
    padding: spacing.md,
  },
  tripRoute: {
    color: palette.navy,
    fontSize: 16,
    fontWeight: '800',
  },
  tripMeta: {
    color: '#4E607A',
    marginTop: 6,
    fontSize: 12,
  },
  tripPrice: {
    marginTop: 12,
    fontSize: 18,
    fontWeight: '800',
    color: palette.navy,
    textAlign: 'right',
  },
  emptyBox: {
    borderRadius: radius.md,
    padding: spacing.md,
    backgroundColor: '#F5F8FD',
    alignItems: 'center',
    borderWidth: 1,
    borderStyle: 'dashed',
    borderColor: '#D8E2F0',
  },
  emptyTitle: {
    fontSize: 14,
    fontWeight: '800',
    color: palette.black,
  },
  emptyText: {
    marginTop: 6,
    fontSize: 11,
    color: '#64748B',
  },
});
