import React, { useState } from 'react';
import { View, Text, Pressable, StyleSheet, ScrollView } from 'react-native';
import { palette, radius, spacing } from '../theme';
import { seats } from '../mock';

type Props = {
  tripName: string;
  onConfirmSeat: (seat: string) => void;
};

export function SeatScreen({ tripName, onConfirmSeat }: Props) {
  const [selected, setSelected] = useState<string | null>('A2');

  return (
    <ScrollView contentContainerStyle={styles.container} showsVerticalScrollIndicator={false}>
      <Text style={styles.title}>Sélection de siège</Text>
      <Text style={styles.tripLabel}>{tripName}</Text>

      <View style={styles.seatGrid}>
        {seats.map(seat => {
          const isSelected = selected === seat.id;
          const isAvailable = seat.available;

          return (
            <Pressable
              key={seat.id}
              onPress={() => {
                if (!isAvailable) return;
                setSelected(seat.id);
                onConfirmSeat(seat.id);
              }}
              style={[
                styles.seat,
                isSelected && styles.selectedSeat,
                !isAvailable && styles.disabledSeat,
              ]}
            >
              <Text style={[styles.seatText, !isAvailable && styles.disabledSeatText]}>{seat.number}</Text>
            </Pressable>
          );
        })}
      </View>

      <Pressable style={styles.primaryButton}>
        <Text style={styles.primaryText}>Réserver ce siège</Text>
      </Pressable>
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
  tripLabel: {
    fontSize: 14,
    color: '#53657B',
    fontWeight: '700',
  },
  seatGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
    backgroundColor: '#F8FBFF',
    borderRadius: radius.xl,
    padding: spacing.md,
    borderWidth: 1,
    borderColor: '#E8EEF7',
  },
  seat: {
    width: 48,
    height: 48,
    borderRadius: 14,
    backgroundColor: '#EAF3FF',
    borderWidth: 1,
    borderColor: '#D7E5F8',
    justifyContent: 'center',
    alignItems: 'center',
  },
  selectedSeat: {
    backgroundColor: palette.navy,
    borderColor: palette.navy,
  },
  disabledSeat: {
    backgroundColor: '#E9EEF4',
    borderColor: '#E2E8F0',
  },
  seatText: {
    fontWeight: '800',
    color: palette.black,
  },
  disabledSeatText: {
    color: '#8EA0B3',
  },
  primaryButton: {
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
