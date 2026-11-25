# Model words

The words people say for the models on a shelf: one small JSON file beside the models, and the rules for matching a spoken word to the models it names.
`ProjectFormat.ModelWords` reads the file and answers by these rules; any other reader of the file follows the same ones. The vectors in
[`model-words-vectors.json`](../Tests/ProjectFormatTests/Fixtures/model-words-vectors.json) pin every rule below (questions, lists, files that read, files that do not).

**Table version: 1**

- [The file](#the-file) — rules 1–12
- [Matching](#matching) — rules 13–24
- [Listing](#listing) — rules 25–27
- [Languages](#languages) — rules 28–31
- [What an app must do](#what-an-app-must-do) — rules 32–33
- [Versions and compatibility](#versions-and-compatibility)

```swift
let words = try ModelWords.load(shelf: shelfFolder)                     // no file — the empty table
words.candidates(for: "화분", language: "ko-KR", among: names)           // what one word names
words.words(language: "ko-KR", among: names)                             // every word that names something, longest first
```

`names` are the models the caller can use, in the order it prefers. The table never adds a model the caller did not name.

## The file

```json
{
  "version": 1,
  "about": "An example — three kinds, five models, Korean and English",
  "kinds": {
    "vessel": { "words": { "ko": ["그릇"], "en": ["vessel"] } },
    "pot": { "parent": "vessel", "words": { "ko": ["화분", "분", "토분", "걸이분"], "en": ["pot", "planter", "hanger"] } },
    "herb": { "words": { "ko": ["허브"], "en": ["herb", "herbs"] } }
  },
  "models": {
    "pot": { "kind": "pot" },
    "pot-xl": { "kind": "pot", "words": { "ko": ["XL", "엑스라지"], "en": ["XL"] } },
    "pot-box": { "kind": "pot", "words": { "ko": ["화분함", "함"], "en": ["crate"] } },
    "sage": { "kind": "herb" },
    "mint": { "kind": "herb", "words": { "ko": ["박하"], "en": ["mint", "mint herb"] } }
  }
}
```

| Field | Shape | Meaning |
|---|---|---|
| `version` | whole number ≥ 1 · required | The version of this table. Not a version of the models or of any other format |
| `about` | anything | A note for people. Readers do not look at it, not even at its type |
| `kinds` | {kind id: entry} | A kind id should be 1–64 of ASCII letters, digits, `.` `_` `-` — advice for a tool that checks tables; readers take any id |
| `kinds.*.parent` | kind id | The one kind above |
| `models` | {model name: entry} | A model's name on the shelf — its file name without the extension. Not the name of a variant |
| `models.*.kind` | kind id | The one kind the model is of |
| `*.words` | {language tag: [word]} | Words people say. Not display names |

**Rule 1.** The table is `model-words.json` at the top of the model shelf — the folder a project's manifest names as its models (a scene opened outside a project: the `Models` folder beside it). No file is the empty table, and not an error. One project has one table: models that live elsewhere (in a theme, say) are listed in it by name.

**Rule 2.** The name is exact, upper and lower case included, on every volume. Subfolders and packages are not searched. A file that is there and cannot be read is an error, a link to nothing included.

**Rule 3.** Each place is *absent* or of the *wrong shape* as below. Absent is the same as not written. A wrong shape refuses the whole file (`file.unreadable`).

| Place | Not written · `null` | Empty | Wrong shape |
|---|---|---|---|
| the top | `null` is a wrong shape | `{}` is `version.missing` | anything but an object |
| `kinds` · `models` | absent | `{}` — no entries | anything but an object |
| an entry (`kinds.x` · `models.x`) | **no such entry** | `{}` — **the entry exists**, with nothing in it | anything but an object |
| `parent` · `kind` | absent | `""` — names no kind, even if a kind has the empty id | anything but a string |
| `words` | absent | `{}` — no words | anything but an object |
| a list in `words` | absent | `[]` — that language is absent | anything but an array |
| a word | `null` is a wrong shape | a word that folds to nothing (rule 13) or is too long (rule 7) is not a word | anything but a string |
| `about` · unknown fields | — | — | none — their type is not looked at |

"Anything but" includes `true`, `false` and numbers.

**Rule 4.** `"name": {}` says the model is known and deliberately given no words. `"name": null` says nothing.

**Rule 5.** Neither the order of keys nor the order of words means anything, and a repeated word counts once.

**Rule 6.** The file is JSON by RFC 8259, to the letter — in the ignored fields too. A trailing comma, a comment, a byte order mark, a number such as `01`, a lone surrogate escape or a second value is `file.unreadable`. So is an object with the same key twice; keys are kept in NFC, so keys that are equal in NFC are the same key. Objects and arrays nest at most 64 levels, the outermost object included (the table itself uses five); deeper is `file.unreadable`, whatever the file says after that.

**Rule 7 — bounds.** The file is UTF-8 and at most 2 MiB (2097152 bytes); more is `file.tooLarge`.

**A text is too long** when its UTF-8 is over 4096 bytes, or over 1024 bytes once put into NFC. What is measured is the text itself, with the escapes of JSON undone. (NFC shortens a text to a third at most, so the first test only spares the work of the second: two spellings of one text are too long together or not at all.) One rule for every text — what follows depends on what the text is:

| Text | Too long |
|---|---|
| a key (any key, ignored ones too) · `kind` · `parent` | `file.unreadable` |
| a listed word | not a word — neither matched nor listed; the table reads (rule 16) |
| a spoken word · a model name given · a language asked | matches nothing — an empty answer, not an error |

The *reach* of a table is at most 2097152: for each model, the words written in its entry and in every kind on its walk (rule 21), all languages, blank, repeated and too long ones counted, added up over the models. More is `file.tooLarge`. So a listing holds at most that many candidates over its folded words, however a table is made (rows that fold alike share theirs).

**Rule 8.** Unknown fields are ignored. A field added within a version is one whose absence changes no answer: a reader that ignores it answers as one that knows it. For the same reason no check of such a field — its type, its bounds — refuses a table within the version.

**Rule 9.** `version` is read as the *value* of a number in IEEE double precision — `1`, `1.0` and `1e0` are all 1. Not a number, not whole, below 1, beyond double precision (`1e400`) or not written is `version.missing`. Elsewhere a number beyond double precision is nothing special — no field uses one.

**Rule 10.** A value above the version the reader knows refuses the whole file (`version.tooNew`), and is judged before any other field — but after the bounds that come before fields: size, encoding, depth, long and repeated keys (rules 6 and 7).

**Rule 11.** A table is read whole or not at all. A caller that goes on without one uses the empty table.

The order of judging: size → JSON (encoding, depth, long and repeated keys included) → the top is an object → version → shapes (a `kind` or a `parent` too long included) → reach.

| Code | When |
|---|---|
| `file.tooLarge` | over the size or the reach of rule 7 |
| `file.unreadable` | the file cannot be opened · not JSON (rule 6) · a wrong shape (rule 3) · a key, a `kind` or a `parent` too long (rule 7) |
| `version.missing` | rule 9 |
| `version.tooNew` | rule 10 |

**Rule 12.** This package does not write the file. A writer keeps the fields it does not know and does not write over a table of a newer version.

## Matching

**Rule 13 — folding.** Words are compared after these steps, in this order (code points as JSON escapes):

1. NFKC
2. Unicode lower case, scalar by scalar — no locale, no context (no final sigma; `İ` becomes `i` + `\u0307`)
3. Out go White_Space (`\u0009`–`\u000D` · `\u0020` · `\u0085` · `\u00A0` · `\u1680` · `\u2000`–`\u200A` · `\u2028` · `\u2029` · `\u202F` · `\u205F` · `\u3000`) and `\u002D` · `\u00AD` · `\u2010`–`\u2015` · `\u200B`–`\u200D` · `\u2060` · `\uFEFF`
4. `\u2019` and `\u02BC` become `\u0027`
5. NFC

**Rule 14.** A spoken word and a listed word match when their folded forms are equal, whole to whole. A word that folds to nothing matches nothing.

**Rule 15.** Nothing else is done: no particles cut, no plurals, no inflection, no partial match, no accents dropped, no translation, no sound-alikes. A form that should match is listed.

**Rule 16 — length.** A listed word should be at most 64 scalars — advice for a tool that checks tables; readers do not enforce it. What readers do enforce is the bound of rule 7, before folding: a word that is too long, spoken or listed, matches nothing.

**Rule 17 — asking.** `candidates(for:language:among:)` takes each named model once (a name given again is dropped), if the table has it:

- the model's own word matches → `exact`, no `kind`, rank 0
- else a word of the model's kind matches → `exact`, `kind` = that kind, rank 1
- else the first kind that matches going up by `parent` → `broader`, `kind` = that kind, rank 1 + steps up
- else the model is no candidate

**Rule 18.** Lower rank first; within a rank, the order the models were named in. There are no scores.

**Rule 19.** A word of two kinds names the models of both. A model is a candidate once — the closest wins.

**Rule 20.** Words are not inherited. They are found by walking up, which is why a match above is `broader`. Nothing walks down: a word of the kind below does not name the models of the kind above.

**Rule 21.** The walk passes at most 64 kinds — the model's own kind is the first; the 64th is reached, the 65th is not. It also ends at a kind it has passed (a loop) and at a kind the table does not have. What it found before that stands.

**Rule 22.** A candidate's `word` is the matched word as the table writes it, in NFC. If several words of that entry match (spellings that fold alike, two tags in use), it is the one whose UTF-8 bytes come first.

**Rule 23.** Model names and kind ids are not folded — upper and lower case differ. They are kept and compared in NFC; a name too long (rule 7) is in no table. A candidate carries the model's name as the caller gave it and the kind's id in NFC. A model that shares its name with a kind is not thereby of that kind.

**Rule 24.** A model and its kind may list the same word; only the rank differs.

## Listing

An app that looks for words in a sentence needs all of them. `words(language:among:)` lists them with their answers, so the app keeps no copy of the words and need not ask again.

**Rule 25 — what.** Every word, in the lists in use (rule 29), of the named models and of the kinds on their walks (rule 21). Each names at least one of the models. What an entry that none of them reaches writes is left out — also where it folds to a word that is listed.

**Rule 26 — rows.** One row for each different text (NFC): the `text` as written, and the `candidates` exactly as asking for it answers. The same text listed by several entries is one row. Texts that fold alike but differ are separate rows with the same candidates — a search in a sentence needs each form.

**Rule 27 — order.** More scalars in the folded form first, then the folded form's UTF-8, then the text's UTF-8. The order of `among` moves the candidates of a row, never the rows.

What always holds:

- **I1** For each row `w` of `words(L, A)`, `candidates(w.text, L, A)` equals `w.candidates` and is not empty.
- **I2** For any `q` that is not too long (rule 7), `candidates(q, L, A)` is not empty exactly when some row's text folds to `fold(q)`; that row's candidates are the answer.
- **I3** `words(L, [])` is empty, and so is the list of an empty or unknown language.

Scanning the sentence is the caller's work, and so are particles, numbers and places. A row's text finds what is written that way. What only folding equates — upper and lower case (`Plant a Herb` for `herb`), another normal form (NFD), full-width letters, other hyphens and apostrophes, spaces left out or put in — a plain search for the text does not find, and folding is not offered as a call of its own. Search with a normalizing of the caller's own (NFC and ignoring case, at the least), cut the words out of the sentence first and ask (`candidates` folds what it is given), or list the form people write.

## Languages

**Rule 28.** Tags have the shape of BCP 47 and are compared in NFC. `_` reads as `-`, ASCII letters are lowered (no others), and empty segments are dropped. A tag with no segment — asked or listed — and an asked one that is too long (rule 7) match nothing; a listed tag is a key, so one too long refuses the file (rule 7).

**Rule 29.** The lists in use are *all* those whose tag is a segment prefix of the asked tag (or equal), or the other way round, taken together in no order. Two tags that mean the same (`ko` · `KO`) are both used. It is not a prefix of letters: `f` is not `fr`.

**Rule 30.** There is no fallback to another language and no guessing of scripts (`zh-CN` is not `zh-Hans`). Ask for Chinese with the script.

**Rule 31.** List words under the language alone (Chinese: with the script). Add a region only for words said in that region alone.

| asked \ listed | `ko` | `pt` | `pt-BR` | `zh-Hans` |
|---|---|---|---|---|
| `ko` · `ko-KR` · `KO_kr` | used | | | |
| `pt` | | used | used | |
| `pt-PT` | | used | not used | |
| `zh` · `zh-Hans-CN` | | | | used |
| `zh-CN` | | | | not used |

## What an app must do

**Rule 32.** An app that ships a table has a test that opens *the resource it ships* (the file at the end of the link, taken from the bundle, not a copy made for the test) with the reader, and asks `words` in each language the app offers, among the models it ships. An error fails the test, and so does an empty answer: it is what a table that is missing, names none of those models, or says nothing in that language gives. At run time such a table is silently empty (rule 11), so this is where it is caught.

```swift
let table = try ModelWords.load(shelf: shippedFolder)                    // unreadable, newer: throws
for language in shippedLanguages {
    #expect(!table.words(language: language, among: shippedModels).isEmpty)
}
```

**Rule 33.** Words of the table are not display names. Repeating the word the person said is fine.

Reading, and the first listing, belong off the main thread; keep the results. A table is a value and can be used from any thread.

## Versions and compatibility

- The answers are the contract: same table, same language, same models — the same answer from every reader of the version, words of `Match` and refusals with their codes included. The text of `message` is not part of it.
- What would answer a table made of the fields of this version differently raises the version: a change of a rule, of a bound (rules 6, 7, 16, 21 — and what a name given to `among` may be), a new word of `Match`, a new code. None of it comes within this version.
- A field added later does not raise the version, because it adds no words and moves no answer: an older reader that ignores it gives the very answer (rule 8). A field that would change what `candidates` or `words` answer is a change of the version.
- An SDK reads the version it knows and the ones before it, each by its own rules. Raising the version makes the SDKs already released refuse the new tables (`version.tooNew`), so it is a major version of the SDK ([SDK.md §5](SDK.md#5-판)).
- `Match` is an open word (a raw string with two constants, no list of known ones) and `code` is a string, so that a reader of a later version can say more without breaking the code that calls it. Handle words you do not know as "other"; in this version there are none.
- New Unicode versions may fold newly added characters differently on different systems. Words made of long-standing characters fold alike everywhere.
- The table changes no model file, no scene and no saved data; taking it out is deleting one file.
