import React from 'react';
import { View, Text, StyleSheet, Pressable } from 'react-native';
import { palette, radius, spacing } from '../theme';
import { profileStats } from '../mock';

export function ProfileScreen() {
  return (
    <View style={styles.container}>
      <View style={styles.headerCard}>
        <View style={styles.avatar}><Text style={styles.avatarText}>A</Text></View>
        <View style={styles.identity}>
          <Text style={styles.name}>A. Dossou</Text>
          <Text style={styles.phone}>+229 97 00 00 00</Text>
        </View>
      </View>

      <View style={styles.statsRow}>
        {profileStats.map(stat => (
          <View key={stat.label} style={styles.statCard}>
            <Text style={styles.statValue}>{stat.value}</Text>
            <Text style={styles.statLabel}>{stat.label}</Text>
          </View>
        ))}
      </View>

      <View style={styles.infoCard}>
        <Text style={styles.cardTitle}>Fonctions optionnelles</Text>
        <Text style={styles.cardText}>Fidélité : active • Wallet : inactif</Text>
      </View>

      <Pressable style={styles.button}>
        <Text style={styles.buttonText}>Se déconnecter</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: spacing.md,
    paddingBottom: 110,
    backgroundColor: palette.muted,
  },
  headerCard: {
    backgroundColor: palette.white,
    borderRadius: radius.xl,
    borderWidth: 1,
    borderColor: '#E8EEF7',
    padding: spacing.md,
    flexDirection: 'row',
    alignItems: 'center',
  },
  avatar: {
    width: 70,
    height: 70,
    borderRadius: 20,
    backgroundColor: palette.navy,
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarText: {
    color: palette.white,
    fontSize: 28,
    fontWeight: '800',
  },
  identity: {
    marginLeft: spacing.md,
  },
  name: {
    fontSize: 22,
    fontWeight: '800',
    color: palette.black,
  },
  phone: {
    marginTop: 6,
    fontSize: 12,
    color: '#5B6F88',
  },
  statsRow: {
    marginTop: spacing.md,
    flexDirection: 'row',
    gap: spacing.sm,
  },
  statCard: {
    flex: 1,
    backgroundColor: palette.white,
    borderRadius: radius.lg,
    padding: spacing.md,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#E8EEF7',
  },
  statValue: {
    fontSize: 24,
    fontWeight: '800',
    color: palette.black,
  },
  statLabel: {
    marginTop: 4,
    fontSize: 11,
    color: '#64748B',
  },
  infoCard: {
    marginTop: spacing.md,
    backgroundColor: palette.white,
    borderRadius: radius.xl,
    borderWidth: 1,
    borderColor: '#E8EEF7',
    padding: spacing.md,
  },
  cardTitle: {
    fontSize: 14,
    fontWeight: '800',
    color: palette.black,
  },
  cardText: {
    marginTop: 10,
    color: '#53657B',
    fontSize: 13,
  },
  button: {
    marginTop: spacing.lg,
    backgroundColor: '#EEF2FF',
    paddingVertical: 14,
    borderRadius: radius.md,
    alignItems: 'center',
  },
  buttonText: {
    color: '#B91C1C',
    fontWeight: '800',
  },
});
