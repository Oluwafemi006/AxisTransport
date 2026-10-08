import React from 'react';
import { View, Text, StyleSheet, Pressable } from 'react-native';
import { palette, radius, spacing } from '../theme';

export function TicketScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>Billet QR</Text>

      <View style={styles.ticketCard}>
        <View style={styles.headerRow}>
          <Text style={styles.route}>Cotonou → Parakou</Text>
          <Text style={styles.badge}>Émis</Text>
        </View>

        <Text style={styles.meta}>22 août 2026 • 08:30</Text>
        <Text style={styles.meta}>Passager : A. Dossou</Text>
        <Text style={styles.meta}>Siège : A2</Text>

        <View style={styles.qrBox}>
          <Text style={styles.qrText}>QR</Text>
        </View>

        <Text style={styles.reference}>Réf. AX-2048</Text>
      </View>

      <Pressable style={styles.primaryButton}>
        <Text style={styles.primaryText}>Partager</Text>
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
  title: {
    fontSize: 24,
    fontWeight: '800',
    color: palette.black,
    marginBottom: spacing.md,
  },
  ticketCard: {
    backgroundColor: palette.navyDark,
    borderRadius: radius.xl,
    padding: spacing.lg,
  },
  headerRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  route: {
    color: palette.white,
    fontSize: 18,
    fontWeight: '800',
  },
  badge: {
    color: palette.white,
    backgroundColor: '#1E8E68',
    paddingHorizontal: 9,
    paddingVertical: 6,
    borderRadius: 999,
    fontSize: 11,
    fontWeight: '800',
  },
  meta: {
    color: '#D5E9FF',
    fontSize: 12,
    marginTop: 8,
  },
  qrBox: {
    marginTop: 24,
    backgroundColor: '#EFF6FF',
    borderRadius: radius.lg,
    height: 170,
    justifyContent: 'center',
    alignItems: 'center',
  },
  qrText: {
    fontSize: 40,
    fontWeight: '900',
    color: palette.navy,
  },
  reference: {
    marginTop: 18,
    color: '#D5E9FF',
    fontSize: 13,
    fontWeight: '700',
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
});
