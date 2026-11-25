/// Prints the flight rules one folder's listing needs: the tool, and the
/// grant that lets it fetch the listing and nothing else, from the same ids:
///
///     dart run is_documents_module:listing_rules <drive> <folder> <sign-in>
///
/// `givenTools` and `fetchesMayReach` are the two keys of a rules file.
/// Exits 64 when an argument isn't a Graph id or a sign-in, saying which.
library;

import 'dart:convert';
import 'dart:io';

import 'package:is_documents_module/is_documents_module.dart';
import 'package:is_effects/is_effects.dart';

void main(List<String> args) {
  final files = switch (args) {
    [final drive, final folder, final signIn] => switch ((
      GraphId.parse(drive),
      GraphId.parse(folder),
      SignIn.parse(signIn),
    )) {
      (final drive?, final folder?, final signIn?) => DriveFolder(
        drive: drive,
        folder: folder,
        signIn: signIn,
      ),
      (null, _, _) => _usage('$drive is not a Graph drive id'),
      (_, null, _) => _usage('$folder is not a Graph item id'),
      (_, _, null) => _usage('$signIn is not a sign-in name'),
    },
    _ => _usage('takes three arguments'),
  };
  if (files == null) return;
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'givenTools': [files.listingTool.toJson()],
      'fetchesMayReach': [files.listingGrant.toJson()],
    }),
  );
}

Null _usage(String why) {
  stderr.writeln('listing_rules: $why');
  stderr.writeln('usage: listing_rules <drive> <folder> <sign-in>');
  exitCode = 64;
  return null;
}
