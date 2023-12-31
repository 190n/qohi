# qohi

This is a repository where I am experimenting with modifications to the [QOI](https://qoiformat.org/) format with Huffman coding.

## Efficiency

On average, this format currently beats QOI on every category of the testing corpus, though not by very much. To recreate these results, extract [the images](https://qoiformat.org/benchmark/qoi_benchmark_suite.tar) (1.07 GiB) into a folder called `corpus`, install [zx](https://npmjs.com/package/zx), and run `./bench.mjs`. Currently only compression efficiency, not speed, is tested.

The numbers reported are "space saving", both versus uncompressed image data and versus QOI. If QOI is 100 bytes and this format is 90 bytes, space saving is 10%. The average space saving and the standard deviation of space saving are reported for each category. Since I haven't developed the header for this format, the size of QOI is also reported excluding the header and trailer (so minus 22 bytes compared to an actual QOI file).

| category | saving vs. raw (avg, %) | stddev (pp) | saving vs. qoi (avg, %) | stddev (pp) |
|----------|-------------------------|-------------|-------------------------|-------------|
| icon_512 | 93.59 | 3.39 | 24.54 | 6 |
| icon_64 | 77.96 | 7.43 | 23.28 | 5.83 |
| photo_kodak | 52.33 | 5.37 | 18 | 1.95 |
| photo_tecnick | 49.8 | 7.93 | 15.56 | 4.65 |
| photo_wikipedia | 45.22 | 6.94 | 16.86 | 5.28 |
| pngimg | 83.31 | 11.74 | 23.94 | 15.09 |
| screenshot_game | 81.75 | 14.63 | 26.78 | 18.59 |
| screenshot_web | 93.48 | 3.85 | 25.19 | 9.95 |
| textures_photo | 54.46 | 8.47 | 29.01 | 4.97 |
| textures_pk | 64.59 | 9.06 | 33.76 | 7.64 |
| textures_pk01 | 73.18 | 15.17 | 26.49 | 8.7 |
| textures_pk02 | 69.92 | 12.67 | 24.47 | 8.91 |
| textures_plants | 79.61 | 10.38 | 18.37 | 6.02 |
| total | 72.92 | 15.55 | 27.61 | 12.45 |

## Format

Subject to drastic change. Also note that you can't actually create an output file with this yet; I've only implemented enough to calculate what the size of the output would be, excluding however large the header is (larger than QOI since it will need to represent the Huffman tree). I also haven't even started writing a decoder, but I've tried to ensure that it would be possible.

To understand how this works you must first read [the QOI specification](https://qoiformat.org/qoi-specification.pdf), as this format is derived from QOI. Familiarity with Huffman coding is assumed too.

### Chunks

The encoder starts by reading each pixel and producing a series of chunks, exactly the same way a QOI encoder would (for benchmarks, the QOI filesize is actually calculated using these chunks, and they match what you get from any other QOI encoder).

### Symbols

Next, each chunk is broken into one or more _symbols_. These symbols make up the alphabet used for Huffman coding. Some symbols are unique (such as `rgb` which indicates that three integers follow for the red, green, and blue channels) and some contain a value (such as `index` which has another symbol for each 6-bit index). Some symbols are expected to be followed by additional symbols to complete the chunk. "payload" in the below table refers to a value represented _in the symbol itself_; the table mapping chunks to symbols indicates how larger payloads are stored as multiple symbols.

Here are the types of symbols available:

| name    | payload |
|---------|---------|
| rgb     | none    |
| rgba    | none    |
| index   | 8-bit unsigned integer: index into array of recent colors |
| diff    | none    |
| luma    | 8-bit signed integer: green channel difference from the previous pixel |
| run     | 8-bit unsigned integer: run length |
| integer | 8-bit unsigned integer: some arbitrary value |

For `integer` symbols, if the integer value to encode is signed (such as the 2-bit signed integers used in `QOI_OP_DIFF`), it is sign-extended to 8 bits if necessary and then reinterpreted as unsigned using two's complement. For instance, the difference of `-2` is:

- 2-bit signed integer: `0b10` = -2
- 8-bit signed integer: `0b11111110` = -2
- 8-bit unsigned integer: `0b11111110` = 254

Here is how each chunk is mapped to symbols:

- `QOI_OP_RGB` is an `rgb` symbol followed by three `integer` symbols for the red, green, and blue channels:

    | rgb | integer(RED) | integer(GREEN) | integer(BLUE) |
    |-|-|-|-|

- `QOI_OP_RGBA` is an `rgba` symbol followed by four `integer` symbols for the red, green, blue, and alpha channels:

    | rgb | integer(RED) | integer(GREEN) | integer(BLUE) | integer(ALPHA) |
    |-|-|-|-|-|

- `QOI_OP_INDEX` is an `index` symbol containing the index:

    | index(INDEX) |
    |-|

- `QOI_OP_DIFF` is a `diff` symbol followed by three `integer` symbols for the red, green, and blue channel differences. These differences are still 2-bit signed integers as in QOI; I found that making them larger reduced efficiency. This is probably because a larger range of differences clutters the Huffman tree with many more values so they all get longer codes.

    | diff | integer(DR) | integer(DG) | integer(DB) |
    |-|-|-|-|

- `QOI_OP_LUMA` is a `luma` symbol containing the green channel difference, followed by two `integer` symbols for `dr_dg` and `db_dg` as defined in the QOI specification (except, here they are all 8-bit signed values instead of 6- and 4-bit as in QOI):

    | luma(DG) | integer(DR_DG) | integer(DB_DG) |
    |-|-|-|

    Experimentally, I found this 8/8/8-bit setup to be better than 6/4/4, 8/4/4, and 8/6/6.

- `QOI_OP_RUN` is a `run` symbol containing the run length:

    | run(LENGTH) |
    |-|

At this point, the encoder has a histogram that tells it how many times each symbol occurs and a list of symbols in order. It uses the histogram to build two Huffman trees: one for only integer symbols, and one for all the other symbols.

Each symbol is written using the binary code determined by the tree for that type of symbol.

There will certainly be collisions between the Huffman codes from the two different trees. However, these do not matter in practice because the decoder knows based on the prior symbol whether it should expect an integer or another kind of symbol.

## Future

Places I may take this:

- [x] Fine-tune the encoding scheme without breaking changes to the chunks as used by QOI
- Possible breaking changes to QOI:
    - [ ] use [YCoCg](https://en.wikipedia.org/wiki/YCoCg) colorspace
    - [x] increase maximum run length and/or hash table size
    - [x] increase maximum representable difference between pixels
- [ ] Determine the header format and implement a decoder
- [ ] Support multithreaded encoding and decoding
    - [ ] The encoder could split an image into chunks where each chunk starts at a byte-aligned boundary and does not refer to data from previous chunks
    - [ ] The encoder could encode the chunk boundaries into the output file, which would let the decoder process chunks in parallel
- [ ] Support higher bit depth
