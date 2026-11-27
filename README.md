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
| A footnote or endnote | `[^1]` where it is referenced, `[^1]: …` after the body, numbered 1, 2, … in the order the body first refers to them; endnotes `[^e1]` |
| A field (page number, date, cross-reference) | the result Word shows |
| A comment | `[comment c1 by Priya Raman]` where its balloon is anchored |
| A tracked insertion not yet accepted | `[inserted i1 by Marcus Bell: approved]` |
| A tracked deletion not yet accepted | `[deleted d1 by Marcus Bell]` |
| An equation | `[equation eq1]` |
| An image | `[image im1: <its alt text>]`, or `[image im1]` with none |
| A chart | `[chart ch1]` |
| Any of those, or a header or footer | one line at the top: `[Also in this document: 1 header, 1 comment, …]` |

A part whose content isn't in the text leaves a hole that names it, so a
reader knows something is there rather than reading past a gap. Each is
numbered by kind in reading order (`c1`, `c2`, `d1`), as a handle for a
tool that reads that part.

Left out entirely: hidden text, field instructions, a table of contents (it
only repeats the headings), formatting, and the fallback copy Word stores of
anything new (`mc:AlternateContent`).

The parts are found as Office finds them, through the package's
relationships, not by fixed names. A part that unzips to more than 64 MiB is
refused, so a small file can't unzip into gigabytes.

`WordDocument.read` throws a `FormatException` when the bytes are not a
`.docx`: not a zip, a password-protected document or an old binary `.doc`
(both start the same way), or a zip with no document body.

## Tools over a folder's files

`listDocuments(files)` and `readDocument(files, byDefault:, atMost:)` are
the two tools, each an is_tool `ToolHandler`. `files` is a `DriveFolder`:
one folder in a SharePoint or OneDrive drive, its drive and item ids
(`GraphId`s) as configured, and the sign-in that reads it, such as an app
granted that folder through Sites.Selected. Each call is one `Program.fetch`, a
GET to `graph.microsoft.com` with no body: the listing kept as text, the
file, addressed by its name in the folder, kept as bytes. A response with
any other body, or none, is an error saying what Graph answered, never an
empty document. A name that is not a `.docx` is refused before anything is
fetched.

`files.grantToFetch` is the is_flight_rules `GrantToFetch` both tools need:
the folder's listing, which must carry a `$select` of only the fields the
model is shown (without one, Graph adds a no-sign-in `downloadUrl` to every
file), and a file in it by name,
`…/items/{folder}:/{name}:/content`, going as the sign-in. It is built from
the same paths the tools fetch, so it can't drift from them. It is for
whoever writes the rules, at configuration time, for a person to approve; a
running tool proposes requests and never grants them.

What the model is given:

- `listDocumentsSpec` (`list_documents`, no input): a `FolderListing`, read
  from a Graph `children` page with `FolderListing.fromGraph`, newest
  first, each item's name, size and when it changed, and whether Graph has
  more than one page.
- `readDocumentSpec(byDefault:, atMost:)` (`read_document {name, offset?,
  maxChars?}`): a `DocumentPassage`, made with `DocumentPassage.read(call,
  bytes)`. `maxChars` is 20,000 unasked and 100,000 at most, both shown
  to the model in the schema; a host can pass its own. The text comes
  back in a `TextWindow`, cut after a line break when there is one in the
  window's second half, ending with a line saying which characters it is,
  how far through the document that is, and the offset to read on from.
  The tool's description asks the model to tell the user how far it read
  when it answers from only part of a document. It also names what reading
  leaves out (images, charts, equations, comments, headers and footers),
  so the model can say an answer may depend on them rather than say they
  aren't there.

A name is a `DocumentName`: a file in the folder, never a path. The same
call on the same bytes always gives the same text, since the loop replays a
tool's result from the logbook.

## The listing as a tool sent as data

`files.listingTool` is `list_documents` as an is_tools_api `OneActionTool`,
stage 1 of tools as data: no input, and one `Fetch` of the folder's listing
as the sign-in, whose JSON the model reads as Graph sent it. Its description
says it returns the first page only, and that `@odata.nextLink` in the
result means the folder holds more. `files.listingGrant` is the grant it
needs and nothing more: the listing, and no file in the folder. Both come
from the same ids, and the tests check that the tool's path is one its grant
matches.

```sh
dart run is_documents_module:listing_rules <drive> <folder> <sign-in>
```

prints the two as the `givenTools` and `fetchesMayReach` of a rules file.

## Trying it on a file

```sh
dart run is_documents_module:word_text report.docx
```

## Tests

`dart test` builds small `.docx` files in the test, one per trap, and reads
documents written by pandoc and by macOS's `textutil` as referees. Those two
are never runtime dependencies, and their tests skip where they are not
installed.
