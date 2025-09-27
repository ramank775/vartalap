import 'package:flutter/material.dart';

enum ProfileImgSize { md, sm, other }

class ProfileImg extends StatelessWidget {
  final String _uri;
  final ProfileImgSize _size;
  const ProfileImg(this._uri, this._size, {super.key});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      foregroundColor: Theme.of(context).primaryColor,
      backgroundColor: Colors.grey,
      backgroundImage: AssetImage(_uri),
      radius: _size == ProfileImgSize.sm ? 15.0 : 20.0,
    );
  }
}
