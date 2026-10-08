import React from 'react';
import { View, Text, StyleSheet, ScrollView } from 'react-native';
import { palette, radius, spacing } from '../theme';
import { parcels } from '../mock';

export function ParcelsScreen() {
  return (
    <ScrollView contentContainerStyle={styles.container} showsVerticalScrollIndicator={false}>
      <Text style={styles.title}>Colis</Text>

      {parcels.map(item => (
        <View key={item.id} style={styles.card}>
          <Text style={styles.tracking}>{item.tracking}</Text>
          <Text style={styles.route}>{item.route}</Text>
          <Text style={styles.status}>{item.status}</Text>

          <View style={styles.progressTrack}>
            <View style={[styles.progressFill, { width: `${item.progress}%` }]} />
          </View>
        </View>
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
  card: {
    backgroundColor: palette.white,
    borderRadius: radius.xl,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: '#E8EEF7',
  },
  tracking: {
    fontSize: 12,
    fontWeight: '800',
    color: palette.navy,
    letterSpacing: 0.8,
  },
  route: {
    marginTop: 8,
    fontSize: 15,
    fontWeight: '800',
    color: palette.black,
  },
  status: {
    marginTop: 8,
    fontSize: 12,
    color: '#46617E',
  },
  progressTrack: {
    marginTop: 16,
    height: 8,
    backgroundColor: '#E8EEF6',
    borderRadius: 999,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    backgroundColor: palette.navy,
    borderRadius: 999,
  },
});
