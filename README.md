# qohi

This is a repository where I am experimenting with modifications to the [QOI](https://qoiformat.org/) format with Huffman coding.

## Efficiency

On average, this format currently beats QOI on every category of the testing corpus, though not by very much. To recreate these results, extract [the images](https://qoiformat.org/benchmark/qoi_benchmark_suite.tar) (1.07 GiB) into a folder called `corpus`, install [zx](https://npmjs.com/package/zx), and run `./bench.mjs`. Currently only compression efficiency, not speed, is tested.

The numbers reported are "space saving", both versus uncompressed image data and versus QOI. If QOI is 100 bytes and this format is 90 bytes, space saving is 10%. The average space saving and the standard deviation of space saving are reported for each category. Since I haven't developed the header for this format, the size of QOI is also reported excluding the header and trailer (so minus 22 bytes compared to an actual QOI file).

| category | saving vs. raw (avg, %) | stddev (pp) | saving vs. qoi (avg, %) | stddev (pp) |
|----------|-------------------------|-------------|-------------------------|-------------|
| icon_512 | 92.95 | 3.63 | 16.19 | 4.78 |
| icon_64 | 75.86 | 8.06 | 16.05 | 5.53 |
| photo_kodak | 47.77 | 7.96 | 10.62 | 2.51 |
| photo_tecnick | 44.27 | 11.64 | 7.19 | 3.86 |
| photo_wikipedia | 37.97 | 10.9 | 6.7 | 3.56 |
| pngimg | 81.33 | 13.32 | 15.01 | 13.82 |
| screenshot_game | 80.02 | 16.22 | 19.46 | 18.54 |
| screenshot_web | 92.17 | 4.33 | 8.34 | 6.68 |
| textures_photo | 48.39 | 13.73 | 20.9 | 5.75 |
| textures_pk | 53.93 | 14.27 | 15.56 | 6.03 |
| textures_pk01 | 69.23 | 17.59 | 16.45 | 7.71 |
| textures_pk02 | 66.7 | 14.44 | 16.69 | 8.48 |
| textures_plants | 77.79 | 11.39 | 11.16 | 4.19 |
| total | 67.59 | 19.94 | 16.01 | 11.05 |

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
| index   | 6-bit unsigned integer: index into array of recent colors |
| diff    | none    |
| luma    | 6-bit signed integer: green channel difference from the previous pixel |
| run     | 6-bit unsigned integer: run length |
| integer | 8-bit unsigned integer: some arbitrary value |

For `integer` symbols, if the integer value to encode is signed (such as the 2-bit signed integers used in `QOI_OP_DIFF` or the 4-bit signed integers `dr_dg` and `db_dg` in `QOI_OP_LUMA`), it is first reinterpreted as an unsigned integer of the same size (using two's complement), and then padded with zeroes to 8 bits. For instance, `-1` as a 4-bit signed integer is first written as a 4-bit unsigned integer (`0b1111`), and then padded to 8 bits (`0b00001111`).

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

- `QOI_OP_DIFF` is a `diff` symbol followed by three `integer` symbols for the red, green, and blue channel differences

    | diff | integer(DR) | integer(DG) | integer(DB) |
    |-|-|-|-|

- `QOI_OP_LUMA` is a `luma` symbol containing the green channel difference, followed by two `integer` symbols for `dr_dg` and `db_dg` as defined in the QOI specification:

    | luma(DG) | integer(DR_DG) | integer(DB_DG) |
    |-|-|-|

- `QOI_OP_RUN` is a `run` symbol containing the run length:

    | run(LENGTH) |
    |-|

At this point, the encoder has a histogram that tells it how many times each symbol occurs and a list of symbols in order. It uses the histogram to build two Huffman trees: one for only integer symbols, and one for all the other symbols.

Each symbol is written using the binary code determined by the tree for that type of symbol.

There will certainly be collisions between the Huffman codes from the two different trees. However, these do not matter in practice because the decoder knows based on the prior symbol whether it should expect an integer or another kind of symbol.

## Future

Places I may take this:

- Fine-tune the encoding scheme without breaking changes to the chunks as used by QOI
- Possible breaking changes to QOI: use [YCoCg](https://en.wikipedia.org/wiki/YCoCg) colorspace, increase maximum run length and/or hash table size, increase maximum representable difference between pixels
- Determine the header format and implement a decoder
- Support multithreaded encoding and decoding
    - The encoder could split an image into chunks where each chunk starts at a byte-aligned boundary and does not refer to data from previous chunks
    - The encoder could encode the chunk boundaries into the output file, which would let the decoder process chunks in parallel
- Support higher bit depth
