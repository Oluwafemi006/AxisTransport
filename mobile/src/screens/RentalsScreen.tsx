import React from 'react';
import { View, Text, StyleSheet, ScrollView, Pressable } from 'react-native';
import { palette, radius, spacing } from '../theme';
import { vehicles } from '../mock';

export function RentalsScreen() {
  return (
    <ScrollView contentContainerStyle={styles.container} showsVerticalScrollIndicator={false}>
      <Text style={styles.title}>Location</Text>

      {vehicles.map(vehicle => (
        <View key={vehicle.id} style={styles.card}>
          <Text style={styles.type}>{vehicle.type}</Text>
          <Text style={styles.name}>{vehicle.name}</Text>
          <Text style={styles.meta}>{vehicle.seats} places</Text>
          <Text style={styles.price}>{vehicle.price}</Text>
          <Pressable style={styles.button}>
            <Text style={styles.buttonText}>Choisir</Text>
          </Pressable>
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
    borderWidth: 1,
    borderColor: '#E8EEF7',
    padding: spacing.md,
  },
  type: {
    fontSize: 10,
    color: palette.navy,
    fontWeight: '800',
    letterSpacing: 1.2,
    textTransform: 'uppercase',
  },
  name: {
    marginTop: 10,
    fontSize: 20,
    fontWeight: '800',
    color: palette.black,
  },
  meta: {
    marginTop: 8,
    color: '#5B6F88',
    fontSize: 12,
  },
  price: {
    marginTop: 14,
    fontSize: 18,
    fontWeight: '800',
    color: palette.navy,
  },
  button: {
    marginTop: 18,
    backgroundColor: '#F4F8FF',
    borderRadius: radius.md,
    paddingVertical: 12,
    alignItems: 'center',
  },
  buttonText: {
    color: palette.navy,
    fontWeight: '800',
  },
});
