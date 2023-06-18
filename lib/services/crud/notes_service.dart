import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mynotes/services/auth/auth_exceptions.dart';
import 'package:sqflite/sqflite.dart' as my_db;
import 'package:path/path.dart' as my_path show join;
import 'package:path_provider/path_provider.dart' as my_path_provider
    show getApplicationDocumentsDirectory;
import 'crud_exceptions.dart';
import 'crud_constants.dart';

/*
We don't have a list of nodes here. It doesn't have the ability to catch the list of nodes
and then, for each operation it goes to the database
 */

class NotesService {
  my_db.Database? _db;
  List<DataBaseNote> _notes = [];
  //Broadcast: - It is intended for individual messages that can be handled one at a time.
  late final StreamController<List<DataBaseNote>> _notesStreamController;

  Stream<List<DataBaseNote>> get allNotesStream =>
      _notesStreamController.stream;

//SingleTone creation
  NotesService._shareInstance() {
    _notesStreamController = StreamController<List<DataBaseNote>>.broadcast(
        //onListen is called whenever a new listener suscribes to our notesStreamController
        onListen: () {
      //sink is the destination of the data, so when a new suscriber is
      //suscribing, it will send it all the current notes _notes
      _notesStreamController.sink.add(_notes);
    });
  }
  static final NotesService _shared = NotesService._shareInstance();
  factory NotesService() {
    return _shared;
  }

  Future<void> _catchNotes() async {
    await _ensureDbIsOpen();
    /* This is getting all notes in the table, maybe good to change it to all notes from user*/
    try {
      final allNotes = await getAllNotes();
      _notes = allNotes;
      _notesStreamController.add(_notes);
    } on NoteDoesNotExistException {
      _notesStreamController.add(_notes);
    }
  }

  Future<DataBaseUser> getOrCreateUser({required String email}) async {
    await _ensureDbIsOpen();
    try {
      final user = await getUser(email: email);
      return user;
    } on UserNotFoundException {
      return await createUser(email: email);
    } catch (e) {
      // this helps to add a breakpoint in here, in case it's necessary to debug the app
      rethrow;
    }
  }

//We might need to fix this
  Future<DataBaseNote> updateNote(
      {required DataBaseNote note, required String text}) async {
    await _ensureDbIsOpen();
    final db = _getDatabaseorThrow();
//Optional try catch. Just so that you are aware that the method get note will throw an exception if note not-found. Remember, in this case we don't need to rethrow it as it would do it automatically
    try {
      await getNote(id: note.id);
    } catch (_) {
      rethrow;
    }

    int numberOfChanges = await db.update(
      noteTable,
      {
        textColumn: text,
        isSyncWithCloudColumn: 0,
      },
      where: '$idColumn = ?',
      whereArgs: [note.id],
    );
    if (numberOfChanges == 0) {
      throw CouldNotUpdateNoteException();
    }
    //19:57
    int noteIndex = _notes.indexOf(note);
    final updatedNote = await getNote(id: note.id);
    if (noteIndex != -1) {
      _notes.remove(note);
      _notes.insert(noteIndex, updatedNote);
    } else {
      _notes.add(updatedNote);
    }

    return updatedNote;
  }

  Future<List<DataBaseNote>> getAllNotesUser(DataBaseUser owner) async {
    await _ensureDbIsOpen();
    final db = _getDatabaseorThrow();

    List<Map<String, Object?>> allNotes = await db.query(
      noteTable,
      where: '$userIDColumn = ?',
      whereArgs: [owner.id],
    );
    if (allNotes.isEmpty) {
      throw NoteDoesNotExistException();
    }

    final notesIterable = allNotes.map((e) => DataBaseNote.fromRow(e));
    final notesList = notesIterable.toList();
    return notesList;
  }

  Future<List<DataBaseNote>> getAllNotes() async {
    await _ensureDbIsOpen();
    final db = _getDatabaseorThrow();

    List<Map<String, Object?>> allNotes = await db.query(noteTable);
    if (allNotes.isEmpty) {
      throw NoteDoesNotExistException();
    }
    final notesIterable = allNotes.map((e) => DataBaseNote.fromRow(e));
    final notesList = notesIterable.toList();
    return notesList;
  }

  Future<DataBaseNote> getNote({required int id}) async {
    await _ensureDbIsOpen();
    final db = _getDatabaseorThrow();
    final myNoteList = await db.query(
      noteTable,
      limit: 1,
      columns: [idColumn, userIDColumn, textColumn],
      where: '$idColumn = ?',
      whereArgs: [id],
    );
    if (myNoteList.isEmpty) {
      throw NoteDoesNotExistException();
    }
    DataBaseNote myNote = DataBaseNote.fromRow(myNoteList.first);
    _notes.removeWhere((note) => note.id == id);
    //Question: Doesn't it change its original place in the list?
    _notes.add(myNote);
    _notesStreamController.add(_notes);
    return myNote;
  }

  Future<int> deleteAllNotes() async {
    await _ensureDbIsOpen();
    my_db.Database db = _getDatabaseorThrow();
    int affectedRows = await db.delete(noteTable);
    if (affectedRows != 0) {
      _notes = [];
      _notesStreamController.add(_notes);
    }
    return affectedRows;
  }

  Future<int> deleteAllNotesOfUser({required DataBaseUser owner}) async {
    await _ensureDbIsOpen();
    final db = _getDatabaseorThrow();
    //For security reasons
    final myUser = await getUser(email: owner.email);
    if (myUser != owner) {
      throw UserNotFoundException();
    }
    int affectedRows = await db.delete(
      noteTable,
      where: '$userIDColumn = ?',
      whereArgs: [owner.id],
    );
    return affectedRows;
  }

  Future<DataBaseNote> createNote({required DataBaseUser owner}) async {
    await _ensureDbIsOpen();
    final db = _getDatabaseorThrow();
    //Check if the user exits
    final dbUser = await getUser(email: owner.email);
    if (dbUser != owner) {
      throw UserNotFoundException();
    }
    const String text = '';
    //Create the note
    final id = await db.insert(noteTable, {
      userIDColumn: owner.id,
      textColumn: text,
      isSyncWithCloudColumn: 1,
    });
    if (id == 0) {
      throw UnableToInsertNoteException();
    }
    DataBaseNote myNote = DataBaseNote(
      id: id,
      userID: owner.id,
      text: text,
      isSyncWithCloud: true,
    );
    _notes.add(myNote);
    _notesStreamController.add(_notes);

    return myNote;
  }

  Future<void> deleteNote({required int id}) async {
    await _ensureDbIsOpen();
    final db = _getDatabaseorThrow();
    int affectedRows = await db.delete(
      noteTable,
      where: '$idColumn = ?',
      whereArgs: [id],
    );
    if (affectedRows == 0) {
      throw UnableToDeleteNoteException();
    }

    //_notes.removeWhere((element) => element.hashCode == id);
    _notes.removeWhere((element) => element.id == id);
    _notesStreamController.add(_notes);
  }

  Future<DataBaseUser> getUser({required String email}) async {
    await _ensureDbIsOpen();
    final db = _getDatabaseorThrow();
    email = email.toLowerCase();
    final myUserList = await db.query(
      userTable,
      distinct: true,
      where: '$emailColumn = ?',
      whereArgs: [email],
    );
    if (myUserList.isEmpty) {
      throw UserNotFoundException();
    }
    final myUser = DataBaseUser.fromRow(myUserList.first);
    return myUser;
  }

  Future<DataBaseUser> createUser({required String email}) async {
    await _ensureDbIsOpen();
    email = email.toLowerCase();
    final db = _getDatabaseorThrow();
    final results = await db.query(
      userTable,
      distinct: true,
      where: '$emailColumn = ?',
      whereArgs: [email],
    );
    if (results.isNotEmpty) {
      throw UserAlreadyExistsException('The email is already in use');
    }

    final userId = await db.insert(userTable, {emailColumn: email});
    if (userId == 0) {
      throw UnableToInsertNoteException();
    }

    final newUser = DataBaseUser(id: userId, email: email);
    return newUser;
  }

  Future<void> deleteUser({required String email}) async {
    await _ensureDbIsOpen();
    final db = _getDatabaseorThrow();
    final int deleteCount = await db.delete(
      userTable,
      where: 'email = ?',
      whereArgs: [email.toLowerCase()],
    );

    if (deleteCount != 1) {
      throw UnableToDeleteUserException(
          'The provided user was not deleted, please, review your query');
    }
  }

  my_db.Database _getDatabaseorThrow() {
    final db = _db;
    if (db != null) {
      return db;
    } else {
      throw DatabaseIsNotOpenedException('The dabase is not open yet!');
    }
  }

  Future<void> close() async {
    await _ensureDbIsOpen();
    final db = _db;
    if (db == null) {
      throw DatabaseIsNotOpenedException(
          'You cannot close the database if it is not open');
    }

    await db.close();
    _db = null;
  }

  Future<void> _ensureDbIsOpen() async {
    try {
      await open();
    } on DatabaseAlreadyOpenedException {
      //empty
    }
  }

  Future<void> open() async {
    if (_db != null) {
      throw DatabaseAlreadyOpenedException('The database is already opened');
    }
    //If the system (in this case the app) is unable to provide the its document directory, it will trhow and exception
    try {
      final docsPath = await my_path_provider
          .getApplicationDocumentsDirectory(); //This might throw an exception
      final dbPath = my_path.join(docsPath.path, dbName);
      //If database does not exist, it creates one
      final db = await my_db.openDatabase(dbPath);
      _db = db;
      //Create user table
      db.execute(createUserTableCommand);
      //Create note table
      db.execute(createNoteTableCommand);
      //We are gettin all the notes from out database in _notes for the stream
      await _catchNotes();
    } catch (e) {
      /* throw MissingPlatformDirectoryException(
        'Unable to get application documents directory'); */
      rethrow;
    }
  }
}

@immutable
class DataBaseUser {
  final int id;
  final String email;

  const DataBaseUser({
    required this.id,
    required this.email,
  });

  DataBaseUser.fromRow(Map<String, Object?> map)
      : id = map[idColumn] as int,
        email = map[emailColumn] as String;
  @override
  String toString() {
    String user = '$idColumn : $id. $emailColumn: $email';
    return user;
  }

  //: https://medium.com/@mdsatriaalamshah/dart-classes-advanced-the-equality-operator-and-the-hash-code-7475c2cd5608
  //Overriding the iqual operation
  @override
  bool operator ==(covariant DataBaseUser other) => id == other.id;

  @override
  int get hashCode => id.hashCode;

/*
  @override
  bool operator == (Object other) {
    if (other is DataBaseUser) {
      return other.id == id;
    } else {
      return false;
    }
  }*/

/**** 
CREATE TABLE "user" (
	"id"	INTEGER NOT NULL,
	"email"	TEXT NOT NULL UNIQUE,
	PRIMARY KEY("id" AUTOINCREMENT)
);

  Every user in the dabase table user will be represented as:
  Map<String, Object?> <-- This is a row



Map<String, Object?>:
- String is 


//The key (String) represnts the column name and the Object its value

  Map<String, Object?> person = {
    'name': 'John',
    'age': 30,
    'isEmployed': true,
    'address': null,
  };
*****/
}

@immutable
class DataBaseNote {
  final int id;
  final int userID;
  final String text;
  final bool isSyncWithCloud;

  const DataBaseNote(
      {required this.id,
      required this.userID,
      required this.text,
      required this.isSyncWithCloud});

  DataBaseNote.fromRow(Map<String, Object?> map)
      : id = map[idColumn] as int,
        userID = map[userIDColumn] as int,
        text = map[textColumn] as String,
        isSyncWithCloud = (map[isSyncWithCloudColumn]) == 1 ? true : false;
  @override
  String toString() {
    String note =
        '$idColumn: $id. $userIDColumn: $userID. $isSyncWithCloudColumn: $isSyncWithCloud $textColumn';
    return note;
  }

  @override
  operator ==(covariant DataBaseNote other) {
    return other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  /* 
  CREATE TABLE "note" (
	"id"	INTEGER NOT NULL,
	"user_id"	INTEGER NOT NULL,
	"text"	TEXT,
	"is_sync_with_cloud"	INTEGER NOT NULL DEFAULT 0,
	PRIMARY KEY("id" AUTOINCREMENT),
	FOREIGN KEY("user_id") REFERENCES "user"("id")
);
  */
}
