import 'package:flutter/material.dart';

class MessageInputWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
        child: Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: <Widget>[
          Flexible(
            flex: 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(const Radius.circular(30.0)),
                color: Colors.white,
              ),
              child: Row(
                children: <Widget>[
                  IconButton(
                    padding: const EdgeInsets.all(0.0),
                    // disabledColor: iconColor,
                    // color: iconColor,
                    icon: Icon(Icons.insert_emoticon),
                    onPressed: () {},
                  ),
                  Flexible(
                    child: TextField(
                      // controller: textFieldController,
                      textCapitalization: TextCapitalization.sentences,
                      // textInputAction: _textInputAction,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(0.0),
                        hintText: 'Type a message',
                        hintStyle: TextStyle(
                          // color: textFieldHintColor,
                          fontSize: 16.0,
                        ),
                        counterText: '',
                      ),
                      onSubmitted: (String text) {
                        // if(_textInputAction == TextInputAction.send) {
                        //   _sendMessage();
                        // }
                      },
                      keyboardType: TextInputType.multiline,
                      maxLines: null,
                      maxLength: 100,
                    ),
                  ),
                  IconButton(
                    // color: iconColor,
                    icon: Icon(Icons.attach_file),
                    onPressed: () {},
                  ),
                  // _message.isEmpty || _message == null
                  //     ? IconButton(
                  //         color: iconColor,
                  //         icon: Icon(Icons.camera_alt),
                  //         onPressed: () {},
                  //       )
                  //     : Container(),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4.0),
            child: IconButton(
              // elevation: 2.0,
              // backgroundColor: secondaryColor,
              // foregroundColor: Colors.white,
              // child: _message.isEmpty || _message == null
              //     ? Icon(Icons.settings_voice)
              //     : Icon(Icons.send),
              onPressed: () => {},
              icon: Icon(Icons.send),
            ),
          )
        ],
      ),
    ));
  }
}
