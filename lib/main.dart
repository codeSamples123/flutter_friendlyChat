import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:math';
import 'dart:io';

// Plugin enhances the list of chat messages
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'dart:async';

final googleSignIn = new GoogleSignIn();
final analytics = new FirebaseAnalytics();
// Firebase Authentication lets you require your app's users to have
// a Google account. When a user signs in, Firebase Authentication verifies
// the credentials from Google Sign-In and returns a response to the app.
// Users who are signed in and authenticated can then connect to the Firebase
// Realtime Database and exhange chat messages with other users.
// You can apply authentication to make sure users see only messages
// they have access to, for example, and impose other types of restrictions on
// the contents of your database.
final auth = FirebaseAuth.instance;

final ThemeData kIOSTheme = new ThemeData(
  primarySwatch: Colors.orange,
  primaryColor: Colors.grey[100],
  primaryColorBrightness: Brightness.light,
);

final ThemeData kDefaultTheme = new ThemeData(
  primarySwatch: Colors.purple,
  accentColor: Colors.orangeAccent[400],
);

void main() {
  runApp(new FriendlychatApp());
}

class FriendlychatApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      title: "Friendlychat",
      theme: defaultTargetPlatform == TargetPlatform.iOS
          ? kIOSTheme
          : kDefaultTheme,
      home: new ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  @override
  State createState() => new ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = new TextEditingController();

  // Establish a connection with the Firebase realtime database
  final reference = FirebaseDatabase.instance.reference().child('messages');

  // The snippet uses multiple await expressions to execute
  // Google Sign-In methods in sequence. If the value of the currentUser
  // property is null, your app will first execute signInSilently(), get
  // the result and store it in the user variable. The signInSilently method
  // attempts to sign in a previously authenticated user, without interaction.
  // After this method finishes executing, if the value of user is still null,
  // your app will start the sign-in process by executing the signIn() method.
  Future<Null> _ensureLoggedIn() async {
    GoogleSignInAccount user = googleSignIn.currentUser;
    if (user == null) user = await googleSignIn.signInSilently();
    if (user == null) {
      await googleSignIn.signIn();
      // Track sign in
      analytics.logLogin();
    }
    // checks whether currentUser is set to null. The authentication property
    // is the user's credentials. The signInWithGoogle() method takes
    // an idToken and an accessToken as arguments.
    // This method is provided by the Flutter Firebase Authentication plugin.
    // It returns a new Firebase User object named currentUser.
    if (await auth.currentUser() == null) {
      GoogleSignInAuthentication credentials =
          await googleSignIn.currentUser.authentication;
      await auth.signInWithGoogle(
        idToken: credentials.idToken,
        accessToken: credentials.accessToken,
      );
    }
    return null;
  }

  // Variable controls the behavior and the visual appearance of the Send button.
  bool _isComposing = false;

  Widget _buildTextComposer() {
    return new IconTheme(
      data: new IconThemeData(color: Theme.of(context).accentColor),
      child: new Container(
        margin: const EdgeInsets.symmetric(horizontal: 8.0),
        child: new Row(
          children: <Widget>[
            new Container(
              margin: new EdgeInsets.symmetric(horizontal: 4.0),
              child: new IconButton(
                  icon: new Icon(Icons.photo_camera),
                  onPressed: () async {
                    await _ensureLoggedIn();
                    File imageFile = await ImagePicker.pickImage();
                    int random = new Random().nextInt(100000);
                    StorageReference ref = FirebaseStorage.instance
                        .ref()
                        .child("image_$random.jpg");
                    // Put methds takes a File object as an argument
                    // and uploads it to a Google Cloud Storage bucket.
                    StorageUploadTask uploadTask = ref.put(imageFile);
                    Uri downloadUrl = (await uploadTask.future).downloadUrl;
                    _sendMessage(imageUrl: downloadUrl.toString());
                  }),
            ),
            new Flexible(
              child: new TextField(
                controller: _textController,
                //  TextField calls this method whenever its value changes
                // with the current value of the field.
                onChanged: (String text) {
                  setState(() {
                    _isComposing = text.length > 0;
                  });
                },
                onSubmitted: _handleSubmitted,
                decoration:
                    new InputDecoration.collapsed(hintText: "Send a message"),
              ),
            ),
            new Container(
              margin: new EdgeInsets.symmetric(horizontal: 4.0),
              child: Theme.of(context).platform == TargetPlatform.iOS
                  ? new CupertinoButton(
                      child: new Text("Send"),
                      onPressed: _isComposing
                          ? () => _handleSubmitted(_textController.text)
                          : null,
                    )
                  : new IconButton(
                      icon: new Icon(Icons.send),
                      onPressed: _isComposing
                          ? () => _handleSubmitted(_textController.text)
                          //  onPressed is set to null, disabling the send button
                          : null,
                    ),
            )
          ],
        ),
      ),
    );
  }

  Future<Null> _handleSubmitted(String text) async {
    _textController.clear();
    setState(() {
      _isComposing = false;
    });
    await _ensureLoggedIn();
    _sendMessage(text: text);
  }

  void _sendMessage({String text, String imageUrl}) {
    reference.push().set({
      'text': text,
      'imageUrl': imageUrl,
      'senderName': googleSignIn.currentUser.displayName,
      'senderPhotoUrl': googleSignIn.currentUser.photoUrl,
    });

    // Track sending message
    analytics.logEvent(name: 'send_message');
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: new Text("Friendlychat"),
        elevation: Theme.of(context).platform == TargetPlatform.iOS ? 0.0 : 4.0,
      ),
      body: new Container(
        decoration: Theme.of(context).platform == TargetPlatform.iOS
            ? new BoxDecoration(
                border: new Border(
                  top: new BorderSide(color: Colors.grey[200]),
                ),
              )
            : null,
        child: new Column(
          children: <Widget>[
            new Flexible(
              // The associated class is a wrapper around
              // the AnimatedList class, enhancing it to interact with
              // the Firebase Database.
              child: new FirebaseAnimatedList(
                query: reference,
                sort: (a, b) => b.key.compareTo(a.key),
                padding: new EdgeInsets.all(8.0),
                reverse: true,
                itemBuilder: (_, DataSnapshot snapshot,
                    Animation<double> animation, int x) {
                  return new ChatMessage(
                      snapshot: snapshot, animation: animation);
                },
              ),
            ),
            new Divider(height: 1.0),
            new Container(
              decoration: new BoxDecoration(color: Theme.of(context).cardColor),
              child: _buildTextComposer(),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatMessage extends StatelessWidget {
  ChatMessage({this.snapshot, this.animation});

  final Animation animation;
  final DataSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    // The SizeTransition class provides an animation effect where the width
    // or height of its child is multiplied by a given size factor value.
    return new SizeTransition(
      //The CurvedAnimation object, in conjunction with the SizeTransition
      // class, produces an ease-out animation effect. The ease-out effect
      // causes the message to slide in quickly at the beginning of
      // the animation and slow down until it comes to a stop.
      sizeFactor: new CurvedAnimation(parent: animation, curve: Curves.easeOut),
      axisAlignment: 0.0,
      child: new Container(
        margin: const EdgeInsets.symmetric(vertical: 10.0),
        child: new Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            new Container(
              margin: const EdgeInsets.only(right: 16.0),
              child: new CircleAvatar(
                backgroundImage:
                    new NetworkImage(snapshot.value['senderPhotoUrl']),
              ),
            ),
            // Expanded allows a widget like Column to impose layout
            // constraints (in this case the Column's width), on a child widget.
            // Here it constrains the width of the Text widget,
            // which is normally determined by its contents.
            new Expanded(
              child: new Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  new Text(snapshot.value['senderName'],
                      style: Theme.of(context).textTheme.subhead),
                  new Container(
                    margin: const EdgeInsets.only(top: 5.0),
                    child: snapshot.value['imageUrl'] != null
                        ? new Image.network(
                            snapshot.value['imageUrl'],
                            width: 250.0,
                          )
                        : new Text(snapshot.value['text']),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
