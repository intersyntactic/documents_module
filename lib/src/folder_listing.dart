import 'package:is_tool_definition_vocabulary/is_tool_definition_vocabulary.dart';

import 'document_name.dart';

/// What a folder holds, as Microsoft Graph lists a drive item's children:
/// each item's name, size and when it was last changed, newest first.
final class FolderListing {
  const FolderListing._(this.items, {required this.more});

  /// A Graph `children` page, read from [page], the response's JSON: its
  /// `value`, each item's `name`, `size`, `lastModifiedDateTime` and whether
  /// it has a `folder` facet, and whether an `@odata.nextLink` says there are
  /// more. Throws a [FormatException] naming the field Graph left out.
  factory FolderListing.fromGraph(JsonObject page) {
    final items = [
      for (final (i, item) in page.objects('value').indexed)
        ListedItem._(
          switch (item.raw('name')) {
                final String name => DocumentName.parse(name),
                _ => null,
              } ??
              (throw JsonFieldException('value[$i].name', 'a file name')),
          size: switch (item.raw('size')) {
            final int size => size,
            _ => 0,
          },
          modified:
              switch (item.raw('lastModifiedDateTime')) {
                final String time => DateTime.tryParse(time)?.toUtc(),
                _ => null,
              } ??
              (throw JsonFieldException(
                'value[$i].lastModifiedDateTime',
                'a date and time',
              )),
          isFolder: item.has('folder'),
        ),
    ]..sort(_newestFirst);
    return FolderListing._(
      List.unmodifiable(items),
      more: page.stringOrNull('@odata.nextLink') != null,
    );
  }

  final List<ListedItem> items;

  /// Whether Graph has more items than [items], on a page not fetched.
  final bool more;

  /// The listing as the model reads it, one item a line.
  String get forModel {
    if (items.isEmpty) return 'The folder is empty.';
    final lines = [
      for (final item in items)
        item.isFolder
            ? '- ${item.name}/ (folder, changed ${_when(item.modified)})'
            : '- ${item.name} (${_size(item.size)}, '
                  'changed ${_when(item.modified)})',
      if (more) '(Graph has more items than these, which are not listed.)',
    ];
    return lines.join('\n');
  }
}

/// One item of a [FolderListing].
final class ListedItem {
  const ListedItem._(
    this.name, {
    required this.size,
    required this.modified,
    required this.isFolder,
  });

  final DocumentName name;

  /// In bytes; for a folder, the bytes of everything in it.
  final int size;

  /// In UTC.
  final DateTime modified;
  final bool isFolder;
}

int _newestFirst(ListedItem a, ListedItem b) {
  final byTime = b.modified.compareTo(a.modified);
  return byTime != 0 ? byTime : a.name.value.compareTo(b.name.value);
}

/// [time], in UTC, to the minute: `2026-11-19 22:14 UTC`.
String _when(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)} UTC';
}

/// [bytes] as a person reads a file's size: `812 bytes`, `48 KB`, `3.4 MB`.
String _size(int bytes) => switch (bytes) {
  < 1024 => bytes == 1 ? '1 byte' : '$bytes bytes',
  < 1024 * 1024 => '${(bytes / 1024).round()} KB',
  _ => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB',
};
