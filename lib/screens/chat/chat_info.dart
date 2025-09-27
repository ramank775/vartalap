import 'package:flutter/material.dart';
import 'package:vartalap/widgets/contact.dart';
import 'package:vartalap/screens/new_chat/select_group_member.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:vartalap/services/connectivity_service.dart';
import 'package:vartalap/utils/error_types.dart';
import 'package:vartalap/widgets/error_widgets.dart';

class ChatInfo extends StatefulWidget {
  final ChatClient chat;

  const ChatInfo(this.chat, {super.key});
  
  @override
  State<ChatInfo> createState() => _ChatInfoState();
}

class _ChatInfoState extends State<ChatInfo> with ErrorHandlingMixin {
  bool _isAddingMember = false;
  bool _isLeavingGroup = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const OfflineIndicator(),
          Expanded(
            child: Scaffold(
              appBar: AppBar(
                elevation: 0,
              ),
              body: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 80,
                      color: Theme.of(context).appBarTheme.backgroundColor,
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 30,
                          foregroundImage: null,
                          child: Avator(
                            height: 50,
                            width: 50,
                            text: widget.chat.displayName,
                          ),
                        ),
                        title: Text(
                          widget.chat.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          Card(
                            elevation: 5,
                            child: TextButton(
                              onPressed: _isAddingMember ? null : () => _addMembers(),
                              child: ListTile(
                                leading: _isAddingMember
                                    ? const SizedBox(
                                        width: 30,
                                        height: 30,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(
                                        Icons.group_add,
                                        size: 30,
                                      ),
                                title: Text(
                                  "Add members",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Card(
                            elevation: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: MediaQuery.of(context).size.width,
                                  margin: const EdgeInsets.only(left: 25, top: 10, bottom: 5),
                                  child: const Text(
                                    "Members",
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textAlign: TextAlign.left,
                                  ),
                                ),
                                const Divider(
                                  thickness: 2,
                                ),
                                StreamBuilder(
                                  stream: widget.chat.membersStream,
                                  builder: (context, snapshot) {
                                    if (snapshot.hasData) {
                                      final users = snapshot.data!;
                                      return Column(
                                        children: users
                                            .map((u) => ContactItem(contact: u.user))
                                            .toList(),
                                      );
                                    } else if (snapshot.hasError) {
                                      final error = ErrorMapper.mapException(snapshot.error);
                                      return Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: ErrorStateWidget(
                                          error: error,
                                          onRetry: () {
                                            setState(() {});
                                          },
                                          customMessage: "Failed to load group members",
                                        ),
                                      );
                                    } else {
                                      return const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(16.0),
                                          child: CircularProgressIndicator(),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                          Card(
                            elevation: 5,
                            child: TextButton(
                              onPressed: _isLeavingGroup ? null : () => _showExitConfirmation(),
                              child: ListTile(
                                leading: _isLeavingGroup
                                    ? const SizedBox(
                                        width: 30,
                                        height: 30,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.exit_to_app_outlined,
                                        color: Colors.red,
                                      ),
                                title: Text(
                                  "Exit group",
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addMembers() async {
    // Check connectivity before proceeding
    if (!ConnectivityService().isConnected) {
      showErrorSnackBar(
        const NetworkError('No internet connection. Please connect and try again.'),
        onRetry: _addMembers,
      );
      return;
    }

    setState(() {
      _isAddingMember = true;
    });

    try {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (context) {
          return SelectGroupMemberScreen(
            channel: widget.chat.channel,
          );
        }),
      );
    } catch (e) {
      final error = ErrorMapper.mapException(e);
      showErrorSnackBar(
        error,
        onRetry: error.isRetryable ? _addMembers : null,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAddingMember = false;
        });
      }
    }
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Exit group"),
          content: const Text("Are you sure you want to exit this group?"),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text(
                "Exit",
                style: TextStyle(color: Colors.red),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _exitGroup();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _exitGroup() async {
    // Check connectivity before proceeding
    if (!ConnectivityService().isConnected) {
      showErrorSnackBar(
        const NetworkError('No internet connection. Please connect and try again.'),
        onRetry: _exitGroup,
      );
      return;
    }

    await executeWithErrorHandling(
      () async {
        setState(() {
          _isLeavingGroup = true;
        });
        
        await RetryMechanism.withRetry(
          () async {
            await widget.chat.removeMember(self: true).timeout(
              const Duration(seconds: 30),
              onTimeout: () => throw TimeoutError(
                'Request timed out. Please check your connection and try again.',
              ),
            );
          },
          maxRetries: 2,
        );
      },
      loadingMessage: "Leaving group...",
      showLoadingDialog: true,
      onSuccess: () {
        if (mounted) {
          Navigator.of(context).pop(); // Close chat info screen
        }
      },
      onError: (error) {
        setState(() {
          _isLeavingGroup = false;
        });
        showErrorDialog(
          error,
          onRetry: error.isRetryable ? _exitGroup : null,
        );
      },
    );
  }

}
