import React, { useMemo, useState } from 'react';
import { View, Text, Pressable, StyleSheet, ScrollView, StatusBar } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { palette } from './src/theme';
import { HomeScreen } from './src/screens/HomeScreen';
import { SearchScreen } from './src/screens/SearchScreen';
import { SeatScreen } from './src/screens/SeatScreen';
import { TicketScreen } from './src/screens/TicketScreen';
import { ParcelsScreen } from './src/screens/ParcelsScreen';
import { RentalsScreen } from './src/screens/RentalsScreen';
import { ProfileScreen } from './src/screens/ProfileScreen';

type ScreenName = 'home' | 'search' | 'seat' | 'ticket' | 'parcels' | 'rentals' | 'profile';

function App() {
  const [screen, setScreen] = useState<ScreenName>('home');
  const [selectedTripName, setSelectedTripName] = useState('Cotonou → Parakou');

  const content = useMemo(() => {
    switch (screen) {
      case 'search':
        return <SearchScreen onSelectTrip={(id) => { setSelectedTripName(id === 1 ? 'Cotonou → Parakou' : 'Parakou → Okédama'); setScreen('seat'); }} />;
      case 'seat':
        return <SeatScreen tripName={selectedTripName} onConfirmSeat={() => setScreen('ticket')} />;
      case 'ticket':
        return <TicketScreen />;
      case 'parcels':
        return <ParcelsScreen />;
      case 'rentals':
        return <RentalsScreen />;
      case 'profile':
        return <ProfileScreen />;
      case 'home':
      default:
        return <HomeScreen onNavigate={(nextScreen) => setScreen(nextScreen as ScreenName)} />;
    }
  }, [screen, selectedTripName]);

  return (
    <SafeAreaProvider>
      <SafeAreaView style={styles.root} edges={['top', 'bottom']}>
        <StatusBar barStyle="dark-content" />
        <View style={styles.topBar}>
          <Text style={styles.time}>09:41</Text>
          <Text style={styles.status}>••• 4G</Text>
        </View>

        <ScrollView style={styles.body} contentContainerStyle={styles.bodyContent} showsVerticalScrollIndicator={false}>
          {content}
        </ScrollView>

        <View style={styles.bottomNav}>
          {[
            ['home', 'Accueil', '⌂'],
            ['search', 'Billets', '▤'],
            ['parcels', 'Colis', '□'],
            ['rentals', 'Location', '◇'],
            ['profile', 'Profil', '○'],
          ].map(([key, label, icon]) => (
            <Pressable key={key} style={styles.bottomItem} onPress={() => setScreen(key as ScreenName)}>
              <Text style={[styles.bottomIcon, screen === key && styles.bottomActive]}>{icon}</Text>
              <Text style={[styles.bottomLabel, screen === key && styles.bottomActiveLabel]}>{label}</Text>
            </Pressable>
          ))}
        </View>
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: '#EAF2F8',
  },
  topBar: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingTop: 12,
    paddingBottom: 6,
    backgroundColor: '#EAF2F8',
  },
  time: {
    fontSize: 12,
    fontWeight: '800',
    color: '#10243F',
  },
  status: {
    fontSize: 12,
    fontWeight: '800',
    color: '#10243F',
  },
  body: {
    flex: 1,
  },
  bodyContent: {
    paddingBottom: 24,
  },
  bottomNav: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: '#EDF4FB',
    borderTopWidth: 1,
    borderTopColor: '#DDE7F3',
    paddingHorizontal: 10,
    paddingTop: 10,
    paddingBottom: 24,
  },
  bottomItem: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 4,
  },
  bottomIcon: {
    fontSize: 22,
    color: '#8EA0B3',
    textAlign: 'center',
  },
  bottomActive: {
    color: palette.navy,
  },
  bottomLabel: {
    fontSize: 11,
    color: '#8EA0B3',
    fontWeight: '700',
  },
  bottomActiveLabel: {
    color: palette.navy,
  },
});

export default App;
