import 'package:flutter/material.dart';
import 'package:vartalap/widgets/Inherited/vartalap_client_provider.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/widgets/contact_preview_item.dart';
import 'package:vartalap/widgets/loading_indicator.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:vartalap/services/connectivity_service.dart';
import 'package:vartalap/utils/error_types.dart';
import 'package:vartalap/widgets/error_widgets.dart';

class CreateGroup extends StatefulWidget {
  final List<Contact> _members;
  const CreateGroup(this._members, {super.key});

  @override
  State<CreateGroup> createState() => _CreateGroupState();
}

class _CreateGroupState extends State<CreateGroup> with ErrorHandlingMixin {
  bool _isCreatingGroup = false;

  Future<void> _onGroupNameConfirm(String name) async {
    final client = VartalapClientProvider.of(context).client;

    if (name.trim().isEmpty) {
      showErrorSnackBar(
        const ValidationError('Group name cannot be empty'),
      );
      return;
    }

    if (name.trim().length > 50) {
      showErrorSnackBar(
        const ValidationError('Group name cannot exceed 50 characters'),
      );
      return;
    }

    // Check connectivity before proceeding
    if (!ConnectivityService().isConnected) {
      showErrorSnackBar(
        const NetworkError(
            'No internet connection. Please connect and try again.'),
        onRetry: () => _onGroupNameConfirm(name),
      );
      return;
    }

    setState(() {
      _isCreatingGroup = true;
    });

    await executeWithErrorHandling(
      () async {
        await RetryMechanism.withRetry(
          () async {
            final channelMembers = widget._members
                .map((contact) => Member(
                      user: contact,
                      role: 'member',
                      since: DateTime.now(),
                    ))
                .toList();

                      final channel = ChannelModel.initial(
                        type: ChannelType.group,
                        extraData: {
                          'name': name.trim(),
                        },
                      );

            await client.createChannel(channel, channelMembers).timeout(
                  const Duration(seconds: 30),
                  onTimeout: () => throw TimeoutError(
                    'Group creation timed out. Please try again.',
                  ),
                );
          },
          maxRetries: 2,
        );
      },
      loadingMessage: "Creating your group...",
      showLoadingDialog: true,
      onSuccess: () {
        if (mounted) {
          Navigator.of(context).pop();
          Navigator.of(context).pop();
        }
      },
      onError: (error) {
        setState(() {
          _isCreatingGroup = false;
        });
        showErrorDialog(error, onRetry: () => _onGroupNameConfirm(name));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const OfflineIndicator(),
          Expanded(child: _buildContent(context)),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 2.0),
              child: Text(
                'New Group',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Container(
          margin: EdgeInsets.only(left: 20, top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _CreateGroupForm(
                onConfirm: _onGroupNameConfirm,
                isLoading: _isCreatingGroup,
              ),
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 18,
                    color: Theme.of(context).textTheme.bodyLarge!.color,
                  ),
                  children: [
                    TextSpan(text: "Members:"),
                    TextSpan(
                      text: widget._members.length.toString(),
                    )
                  ],
                ),
              ),
              Expanded(
                flex: 10,
                child: GridView.count(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  crossAxisCount: 5,
                  childAspectRatio: 0.5,
                  children: widget._members
                      .map((e) => ContactPreviewItem(contact: e))
                      .toList(),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  void showLoadingIndicator(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: LoadingIndicator(
              text: "While we are creating group for you.",
            ),
          ),
        );
      },
    );
  }

  void showOldErrorDialog(BuildContext context, List<String> error) {
    var dialog = AlertDialog(
      title: Text('Error'),
      content: SingleChildScrollView(
        child: ListBody(
          children: error.map((err) => Text(err)).toList(),
        ),
      ),
      actions: [
        TextButton(
          child: Text('OK'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );
    showDialog(
      context: context,
      builder: (context) => dialog,
    );
  }
}

class _CreateGroupForm extends StatefulWidget {
  final Function(String) onConfirm;
  final bool isLoading;

  const _CreateGroupForm({
    required this.onConfirm,
    this.isLoading = false,
  });

  @override
  __CreateGroupFormState createState() => __CreateGroupFormState();
}

class __CreateGroupFormState extends State<_CreateGroupForm> {
  String value = "";
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.rectangle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ListTile(
            leading: Avator(
              width: 55,
              height: 55,
              text: value.isEmpty ? "Group Icon" : value,
            ),
            title: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: TextField(
                maxLines: 1,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                style: TextStyle(
                  fontSize: 18,
                ),
                onChanged: (val) {
                  setState(() {
                    value = val;
                  });
                },
              ),
            ),
            subtitle: Container(),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: widget.isLoading
                      ? null
                      : () async {
                          if (value.isNotEmpty) {
                            widget.onConfirm(value);
                          } else {
                            final snackBar = SnackBar(
                                content: Text('Group name can\'t be empty!'));
                            ScaffoldMessenger.of(context)
                                .showSnackBar(snackBar);
                          }
                        },
                  style: TextButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    shape: const CircleBorder(side: BorderSide.none),
                  ),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    child: widget.isLoading
                        ? const SizedBox(
                            width: 30,
                            height: 30,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(
                            Icons.done,
                            size: 30,
                          ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
