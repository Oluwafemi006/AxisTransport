import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../../core/models.dart';

/// Local copies of issued tickets, scoped to the account that fetched them.
/// This is a display cache; the server remains authoritative for ticket status.
class ConfirmedTicketStore {
  ConfirmedTicketStore({this.databasePath});

  final String? databasePath;
  Future<Database>? _database;

  Future<Database> get _db => _database ??= _open();

  Future<Database> _open() async {
    final location =
        databasePath ??
        path.join(await getDatabasesPath(), 'axis_confirmed_tickets.db');
    return openDatabase(
      location,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE confirmed_tickets (
            owner_key TEXT NOT NULL,
            ticket_id INTEGER NOT NULL,
            payload TEXT NOT NULL,
            saved_at TEXT NOT NULL,
            PRIMARY KEY (owner_key, ticket_id)
          )
        ''');
      },
    );
  }

  Future<List<Ticket>> read(String ownerKey) async {
    final rows = await (await _db).query(
      'confirmed_tickets',
      columns: ['payload'],
      where: 'owner_key = ?',
      whereArgs: [ownerKey],
      orderBy: 'saved_at DESC',
    );
    return rows
        .map((row) {
          final decoded = jsonDecode(row['payload']! as String);
          return Ticket.fromJson(decoded as Map<String, dynamic>);
        })
        .where((ticket) => ticket.isConfirmed)
        .toList();
  }

  Future<Ticket?> find(String ownerKey, int ticketId) async {
    final rows = await (await _db).query(
      'confirmed_tickets',
      columns: ['payload'],
      where: 'owner_key = ? AND ticket_id = ?',
      whereArgs: [ownerKey, ticketId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final decoded = jsonDecode(rows.first['payload']! as String);
    final ticket = Ticket.fromJson(decoded as Map<String, dynamic>);
    return ticket.isConfirmed ? ticket : null;
  }

  Future<void> replace(String ownerKey, List<Ticket> tickets) async {
    final db = await _db;
    await db.transaction((transaction) async {
      await transaction.delete(
        'confirmed_tickets',
        where: 'owner_key = ?',
        whereArgs: [ownerKey],
      );
      for (final ticket in tickets.where((item) => item.isConfirmed)) {
        await transaction.insert('confirmed_tickets', _row(ownerKey, ticket));
      }
    });
  }

  Future<void> upsert(String ownerKey, Ticket ticket) async {
    if (!ticket.isConfirmed) return;
    await (await _db).insert(
      'confirmed_tickets',
      _row(ownerKey, ticket),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> close() async {
    final pending = _database;
    _database = null;
    if (pending != null) await (await pending).close();
  }

  Map<String, Object?> _row(String ownerKey, Ticket ticket) => {
    'owner_key': ownerKey,
    'ticket_id': ticket.id,
    'payload': jsonEncode(ticket.toJson()),
    'saved_at': DateTime.now().toUtc().toIso8601String(),
  };
}
