import 'package:flutter/material.dart';

enum ProfileImgSize { MD, SM }

class ProfileImg extends StatelessWidget {
  final String _uri;
  final ProfileImgSize _size;
  ProfileImg(this._uri, this._size);

  @override
  Widget build(BuildContext context) {
    return new CircleAvatar(
      foregroundColor: Theme.of(context).primaryColor,
      backgroundColor: Colors.grey,
      backgroundImage: new AssetImage(this._uri),
      radius: this._size == ProfileImgSize.SM ? 15.0 : 20.0,
    );
  }
}
