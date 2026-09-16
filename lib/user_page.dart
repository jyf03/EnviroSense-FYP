import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'edit_profile_page.dart';
import 'notification_settings_page.dart';
import 'about_page.dart';
import 'login_page.dart';

class UserPage extends StatefulWidget {
  const UserPage({super.key});

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  String name = '';
  String email = '';

  DatabaseReference? userRef;

  @override
  void initState() {
    super.initState();
  }

  void loadUserProfile(User user) {
    userRef = FirebaseDatabase.instance.ref('users/${user.uid}');

    userRef!.once().then((event) {
      final data = event.snapshot.value;

      if (!mounted) return;

      if (data != null) {
        final userData = Map<String, dynamic>.from(data as Map);

        setState(() {
          name = userData['name']?.toString() ?? user.displayName ?? '';

          email = userData['email']?.toString() ?? user.email ?? '';
        });
      } else {
        setState(() {
          name = user.displayName ?? '';
          email = user.email ?? '';
        });
      }
    });
  }

  Future<void> openLoginPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
    );
  }

  Future<void> logout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,

      builder: (context) {
        return AlertDialog(
          title: const Text('Logout'),

          content: const Text('Are you sure you want to logout?'),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),

            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    setState(() {
      name = '';
      email = '';
      userRef = null;
    });

    // No navigation to LoginPage.
    // User stays in the application as Guest.
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),

      builder: (context, snapshot) {
        final User? user = snapshot.data;

        final bool isLoggedIn = user != null;

        if (isLoggedIn && name.isEmpty && email.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            loadUserProfile(user);
          });
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,

            children: [
              const Text(
                'User Profile',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 20),

              CircleAvatar(
                radius: 45,

                backgroundColor: const Color(0xFFD4E3FF),

                child: Icon(
                  isLoggedIn ? Icons.person : Icons.person_outline,
                  size: 50,
                  color: const Color(0xFF174A7E),
                ),
              ),

              const SizedBox(height: 16),

              Text(
                isLoggedIn
                    ? (name.isEmpty ? user.displayName ?? 'User' : name)
                    : 'Guest',

                textAlign: TextAlign.center,

                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 20),

              // =================================
              // LOGGED-IN USER INFORMATION
              // =================================
              if (isLoggedIn)
                Card(
                  elevation: 3,

                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person_outline),

                        title: const Text('Name'),

                        subtitle: Text(
                          name.isEmpty
                              ? user.displayName ?? 'No name set'
                              : name,
                        ),
                      ),

                      const Divider(height: 1),

                      ListTile(
                        leading: const Icon(Icons.email_outlined),

                        title: const Text('Email'),

                        subtitle: Text(
                          email.isEmpty ? user.email ?? 'No email set' : email,
                        ),
                      ),
                    ],
                  ),
                ),

              if (isLoggedIn) const SizedBox(height: 16),

              // =================================
              // SETTINGS
              // =================================
              Card(
                elevation: 3,

                child: Column(
                  children: [
                    // Edit Profile is only visible
                    // after login.
                    if (isLoggedIn) ...[
                      ListTile(
                        leading: const Icon(Icons.edit_outlined),

                        title: const Text('Edit Profile'),

                        trailing: const Icon(Icons.chevron_right),

                        onTap: () async {
                          final updated = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (context) => EditProfilePage(
                                currentName: name,
                                currentEmail: email,
                              ),
                            ),
                          );

                          if (updated == true && user != null) {
                            loadUserProfile(user);
                          }
                        },
                      ),

                      const Divider(height: 1),
                    ],

                    // Guest and logged-in user
                    // can both access this.
                    ListTile(
                      leading: const Icon(Icons.notifications_outlined),

                      title: const Text('Notification Settings'),

                      trailing: const Icon(Icons.chevron_right),

                      onTap: () {
                        Navigator.push(
                          context,

                          MaterialPageRoute(
                            builder: (context) =>
                                const NotificationSettingsPage(),
                          ),
                        );
                      },
                    ),

                    const Divider(height: 1),

                    // Guest and logged-in user
                    // can both see About.
                    ListTile(
                      leading: const Icon(Icons.info_outline),

                      title: const Text('About'),

                      trailing: const Icon(Icons.chevron_right),

                      onTap: () {
                        Navigator.push(
                          context,

                          MaterialPageRoute(
                            builder: (context) => const AboutPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // =================================
              // LOGIN / LOGOUT BUTTON
              // =================================
              if (!isLoggedIn)
                ElevatedButton.icon(
                  onPressed: openLoginPage,

                  icon: const Icon(Icons.login),

                  label: const Text('Login'),

                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),

              if (isLoggedIn)
                OutlinedButton.icon(
                  onPressed: logout,

                  icon: const Icon(Icons.logout),

                  label: const Text('Logout'),

                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),

              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}
