# is_documents_module

intersyntactic's documents module: what a document holds, as Dart types, and
pure-Dart readers that turn a file's bytes into one. It starts with a Word
document's text, so an agent asked to read the incoming reports is given
their words, not their XML.

It is not a driver. Reading a file is an effect: a tool describes it, the
airlock decides and records it, and the file driver hands back bytes.
Turning those bytes into a document touches nothing, so it is here, in pure
Dart, and starts no process: it runs on every Flutter target
([#1069](https://github.com/enspyrco/intersyntactic/issues/1069),
[#466](https://github.com/enspyrco/intersyntactic/issues/466)).

```dart
import 'package:is_documents_module/is_documents_module.dart';

final report = WordDocument.read(bytes); // throws FormatException, saying why
print(report.text);
```

## Types

- `HasText`: a document whose words can be read as one string. Open, not
  sealed, so a format in another package can implement it; a module that
  reads prose accepts `HasText`, not a file format.
- `WordDocument implements HasText`: a `.docx`, read with
  `WordDocument.read(bytes)`.

## What a Word document's text is

The document as a person reading it sees it now, in light Markdown:

| In the document | In the text |
| --- | --- |
| A word Word split into several runs | the word, joined |
| A heading (by style name, outline level, or a style it is based on) | `#`, `##`, … |
| A numbered or bulleted paragraph | its label as Word shows it, `3.2`, `(ii)`, `-`, indented by level |
| A heading numbered through its style | `# 3. Findings` |
| A table | `\|` between cells, first row the header |
| A one-column table (a box drawn round paragraphs) | the paragraphs |
| A text box | its paragraphs, once, after the paragraph it sits in |
| A footnote or endnote | `[^1]` where it is referenced, `[^1]: …` after the body |
| A field (page number, date, cross-reference) | the result Word shows |

Left out: tracked deletions, hidden text, field instructions, a table of
contents (it only repeats the headings), formatting, images, and the
fallback copy Word stores of anything new (`mc:AlternateContent`).

The parts are found as Office finds them, through the package's
relationships, not by fixed names. A part that unzips to more than 64 MiB is
refused, so a small file can't unzip into gigabytes.

`WordDocument.read` throws a `FormatException` when the bytes are not a
`.docx`: not a zip, a password-protected document or an old binary `.doc`
(both start the same way), or a zip with no document body.

## Tools over a folder of documents

`listDocuments(folder)` and `readDocument(folder)` are the two tools, each
an is_tool `ToolHandler`. `folder` is a `DriveFolder`: a SharePoint
document library and a folder in it (`GraphId`s: the drive's `b!…` id, and
the folder's item id or `root`), and the name of the sign-in the airlock
reads it as. A trajectory's starting rules hold it as JSON, and the agent
loop reads it with `DriveFolder.fromJson`:

```json
{"drive": "b!Xk3…", "folder": "root", "signIn": "cam-graph"}
```

Each call is one `Program.fetch`, a
GET to `graph.microsoft.com` with no body: the listing kept as text, the
file, addressed by its name in the folder, kept as bytes. A response with
any other body, or none, is an error saying what Graph answered, never an
empty document. A name that is not a `.docx` is refused before anything is
fetched.

What the model is given:

- `listDocumentsSpec` (`list_documents`, no input): a `FolderListing`, read
  from a Graph `children` page with `FolderListing.fromGraph`, newest
  first, each item's name, size and when it changed, and whether Graph has
  more than one page.
- `readDocumentSpec(byDefault:, atMost:)` (`read_document {name, offset?,
  maxChars?}`): a `DocumentPassage`, made with `DocumentPassage.read(call,
  bytes)`. `maxChars` is 20,000 unasked and 100,000 at most, both shown
  to the model in the schema; `readDocument` takes others as `byDefault`
  and `atMost`. The text comes
  back in a `TextWindow`, cut after a line break when there is one in the
  window's second half, ending with a line saying which characters it is,
  how far through the document that is, and the offset to read on from.
  The tool's description asks the model to tell the user how far it read
  when it answers from only part of a document.

A name is a `DocumentName`: a file in the folder, never a path. The same
call on the same bytes always gives the same text, since the loop replays a
tool's result from the record.

## Trying it on a file

```sh
dart run is_documents_module:word_text report.docx
```

## Tests

`dart test` builds small `.docx` files in the test, one per trap, and reads
documents written by pandoc and by macOS's `textutil` as referees. Those two
are never runtime dependencies, and their tests skip where they are not
installed.
