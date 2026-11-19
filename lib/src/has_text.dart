/// A document whose words can be read as one string: what a reader of
/// prose, such as a model, is given in place of the file.
///
/// Open, not sealed, so a format in another package can implement it.
abstract interface class HasText {
  String get text;
}
