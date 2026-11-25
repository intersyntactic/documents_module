# Changelog

## 0.1.0 (unreleased)

- `HasText`: a document whose words can be read as one string.
- `WordDocument.read(bytes)`: a `.docx`'s text as a person reading it sees
  it, in light Markdown: headings, list labels as Word numbers them, tables,
  text boxes and notes, numbered in the order the body first refers to
  them; tracked deletions, hidden text, field instructions
  and a table of contents left out.
- `word_text`: prints the text of the `.docx` files named.
