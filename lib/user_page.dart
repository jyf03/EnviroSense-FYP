import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'login_page.dart';

class UserPage extends StatefulWidget {
  const UserPage({super.key});

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;
    final bool isLoggedIn = user != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'User Profile',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 20),

          const CircleAvatar(
            radius: 45,
            child: Icon(
              Icons.person,
              size: 50,
            ),
          ),

          const SizedBox(height: 10),

          Center(
            child: Text(
              isLoggedIn
                  ? (user.displayName ?? 'User')
                  : 'Guest',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Only show user information after login
          if (isLoggedIn)
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.person_outline,
                      ),
                      title: const Text('Name'),
                      subtitle: Text(
                        user.displayName ?? 'User',
                      ),
                    ),

                    const Divider(height: 1),

                    ListTile(
                      leading: const Icon(
                        Icons.email_outlined,
                      ),
                      title: const Text('Email'),
                      subtitle: Text(
                        user.email ?? '',
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (isLoggedIn)
            const SizedBox(height: 16),

          Card(
            elevation: 3,
            child: Column(
              children: [
                if (isLoggedIn)
                  ListTile(
                    leading: const Icon(
                      Icons.edit_outlined,
                    ),
                    title: const Text(
                      'Edit Profile',
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                    ),
                    onTap: () {
                      // Add Edit Profile later
                    },
                  ),

                if (isLoggedIn)
                  const Divider(height: 1),

                ListTile(
                  leading: const Icon(
                    Icons.notifications_outlined,
                  ),
                  title: const Text(
                    'Notification Settings',
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                  ),
                  onTap: () {
                    // Add settings later
                  },
                ),

                const Divider(height: 1),

                ListTile(
                  leading: const Icon(
                    Icons.info_outline,
                  ),
                  title: const Text('About'),
                  trailing: const Icon(
                    Icons.chevron_right,
                  ),
                  onTap: () {
                    // Add About page later
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            height: 50,

            child: ElevatedButton.icon(
              onPressed: () async {
                if (isLoggedIn) {
                  final confirmLogout = await showDialog<bool>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text('Logout'),
                        content: const Text(
                          'Are you sure you want to log out?',
                        ),
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

                  if (confirmLogout == true) {
                    await FirebaseAuth.instance.signOut();

                    if (!mounted) return;

                    setState(() {});
                  }
                } else {
                  // Open login page
                  final result =
                  await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                      const LoginPage(),
                    ),
                  );

                  // Refresh page after successful login
                  if (result == true && mounted) {
                    setState(() {});
                  }
                }
              },

              icon: Icon(
                isLoggedIn
                    ? Icons.logout
                    : Icons.login,
              ),

              label: Text(
                isLoggedIn
                    ? 'Logout'
                    : 'Login',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}